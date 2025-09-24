import 'dart:async';

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
// import 'package:synchronized/extension.dart';
import 'package:synchronized/synchronized.dart';

/// Discovery events for stream resolution
class DiscoveryEvent extends CoordinationEvent {
  DiscoveryEvent({
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(name: name ?? 'discovery-event-$id');
}

extension StreamDestroyMapExtension on Map<String, StreamInfoResource> {
  /// Destroys all StreamInfo resources in the map
  void destroy() {
    for (var resource in values) {
      resource.dispose();
    }
  }

  /// Adds all the stream infos and wraps them in StreamInfoResources
  void addAllStreamInfos(
    List<LSLStreamInfo> streamInfos, {
    IResourceManager? manager,
  }) {
    for (var info in streamInfos) {
      final resource = StreamInfoResource(streamInfo: info, manager: manager);
      this[resource.id] = resource;
    }
  }
}

class StreamInfoResource extends LSLResource {
  final LSLStreamInfo streamInfo;

  StreamInfoResource({required this.streamInfo, super.manager})
    : super(id: 'stream-info') {
    create();
  }

  @override
  String get id => 'lsl-streaminfo-${streamInfo.uid ?? streamInfo.streamName}';

  @override
  String? get description =>
      'LSL StreamInfo Resource for ${streamInfo.streamName} (id: ${streamInfo.uid})';

  @override
  Future<void> create() async {
    await super.create();
    // No additional creation needed for StreamInfo
  }

  @override
  Future<void> dispose() async {
    streamInfo.destroy();
    await super.dispose();
  }

  static List<StreamInfoResource> fromStreamInfos(
    List<LSLStreamInfo> streamInfos, {
    IResourceManager? manager,
  }) {
    return streamInfos
        .map((info) {
          final r = StreamInfoResource(streamInfo: info, manager: manager);
          manager?.manageResource<StreamInfoResource>(r);
          return r;
        })
        .toList(growable: false);
  }
}

class LSLDiscoveryEvent extends DiscoveryEvent {
  final String predicate;

  LSLDiscoveryEvent({
    required this.predicate,
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(name: name ?? 'lsl-discovery-event');
}

/// Event fired when streams are discovered via continuous resolution
class StreamDiscoveredEvent extends LSLDiscoveryEvent {
  /// This is a list of key information from streamInfos so that the caller
  /// can retrieve the full StreamInfo objects if needed from the discovery
  /// instance
  final List<StreamInfoResource> streams;

  StreamDiscoveredEvent({
    required this.streams,
    required super.predicate,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(
         id: 'stream_discovered_${DateTime.now().millisecondsSinceEpoch}',
         description:
             'Discovered ${streams.length} stream(s) matching predicate',
         name: name ?? 'stream-discovered',
       );
}

/// Event fired when discovery times out without finding streams
class DiscoveryTimeoutEvent extends LSLDiscoveryEvent {
  final Duration timeoutDuration;

  DiscoveryTimeoutEvent({
    required this.timeoutDuration,
    required super.predicate,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(
         id: 'discovery_timeout_${DateTime.now().millisecondsSinceEpoch}',
         description:
             'Discovery timed out after ${timeoutDuration.inSeconds}s for predicate',
         name: name ?? 'discovery-timeout',
       );
}

/// LSL-based discovery mechanism for network nodes with event-driven pattern
class LslDiscovery extends LSLResource implements IPausable, IResourceManager {
  /// Configuration for coordination
  final NetworkStreamConfig streamConfig;
  final CoordinationConfig coordinationConfig;

  bool _paused = false;
  @override
  bool get paused => _paused;

  Timer? _discoveryInterval;
  Timer? _timeoutTimer;
  final Lock _discoveryLock = Lock();

  final Map<String, StreamInfoResource> _discoveredStreams = {};

  // Event-driven discovery
  final StreamController<DiscoveryEvent> _eventController =
      StreamController<DiscoveryEvent>();
  Stream<DiscoveryEvent> get events => _eventController.stream;

  // Mutable predicate for destroy/recreate pattern
  String? _currentPredicate;

  LSLStreamResolverContinuous? _resolver;

  LslDiscovery({
    required this.streamConfig,
    required this.coordinationConfig,
    required super.id,
    String? predicate,
    super.manager,
  }) : _currentPredicate = predicate;

  @override
  String get id => 'lsl-discovery-${streamConfig.id}';

  @override
  void manageResource<R extends IResource>(R resource) {
    if (resource is StreamInfoResource) {
      resource.updateManager(this);
      _discoveredStreams[resource.id] = resource;
    } else {
      throw ArgumentError(
        'LSLDiscovery can only manage StreamInfoResource instances',
      );
    }
  }

  @override
  R releaseResource<R extends IResource>(String resourceUId) {
    final resource = _discoveredStreams.remove(resourceUId);

    if (resource == null) {
      throw ArgumentError('Resource with id $resourceUId not found');
    }
    resource.updateManager(null);
    return resource as R;
  }

  /// Ensures that the resource is created before performing operations.
  void _ensureCreated() {
    if (!created || disposed) {
      throw StateError('Discovery resource is not created');
    }
  }

  @override
  Future<void> create() async {
    if (created) return;
    await super.create();
  }

  /// Start event-driven discovery with the given predicate and optional timeout
  void startDiscovery({
    required String predicate,
    Duration? timeout,
    int? maxStreams,
  }) {
    _ensureCreated();

    // If predicate changed, destroy old resolver and create new one
    if (_currentPredicate != predicate || _resolver == null) {
      stopDiscovery();
      _currentPredicate = predicate;
      logger.finest('Creating new resolver for predicate: $predicate');
      _resolver = LSLStreamResolverContinuousByPredicate(
        predicate: predicate,
        maxStreams: maxStreams ?? coordinationConfig.topologyConfig.maxNodes,
        forgetAfter:
            coordinationConfig.sessionConfig.nodeTimeout.inMilliseconds /
            1000.0,
      );
      _resolver!.create();
    }

    // Set up timeout if specified
    if (timeout != null) {
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(timeout, () {
        if (disposed || !created) return;
        _eventController.add(
          DiscoveryTimeoutEvent(timeoutDuration: timeout, predicate: predicate),
        );
      });
    }

    // Start continuous discovery
    _startContinuousDiscovery();
  }

  /// no-op if no timeout is active
  void cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  /// Starts continuous discovery that emits events when streams are found
  Future<void> _startContinuousDiscovery() async {
    if (_resolver == null) return;

    _discoveryInterval?.cancel();
    _discoveryInterval = Timer.periodic(
      coordinationConfig.sessionConfig.discoveryInterval,
      (timer) async {
        if (_paused || disposed) return;
        await _performContinuousDiscovery();
      },
    );
    await _performContinuousDiscovery();
  }

  void stopDiscovery() {
    logger.fine('Stopping discovery');
    _discoveryInterval?.cancel();
    _discoveryInterval = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _resolver?.destroy();
    _resolver = null;
  }

  /// Performs continuous discovery and emits events when streams are found
  Future<void> _performContinuousDiscovery() async {
    if (_resolver == null ||
        _currentPredicate == null ||
        disposed ||
        !created) {
      return;
    }

    return _discoveryLock.synchronized(() async {
      if (disposed || !created) return;

      try {
        // Update internal list
        _discoveredStreams.destroy();
        _discoveredStreams.clear();

        final newStreams = await _resolver!.resolve();

        // Debug: Log what the resolver returned
        logger.finest('Resolver returned ${newStreams.length} streams:');
        for (int i = 0; i < newStreams.length; i++) {
          logger.finest(
            '  [$i] ${newStreams[i].streamName} sourceId=${newStreams[i].sourceId}',
          );
        }

        // Update internal list
        _discoveredStreams.addAllStreamInfos(newStreams, manager: this);

        // Check if we found new streams
        if (newStreams.isNotEmpty) {
          // Cancel timeout since we found streams
          _timeoutTimer?.cancel();
          _timeoutTimer = null;

          // Emit discovery event
          _eventController.add(
            StreamDiscoveredEvent(
              streams: _discoveredStreams.values.toList(growable: false),
              predicate: _currentPredicate!,
            ),
          );
        }
      } catch (e) {
        // Handle discovery errors gracefully
        logger.warning('Discovery error for predicate $_currentPredicate: $e');
      }
    });
  }

  @override
  void pause() {
    _ensureCreated();
    if (_paused) return;
    _paused = true;
    _discoveryInterval?.cancel();
  }

  @override
  void resume() {
    _ensureCreated();
    if (!_paused) return;
    _paused = false;
    _startContinuousDiscovery();
  }

  /// Gets the current list of discovered streams' resource UIDs
  List<String> get discoveredStreams =>
      List.unmodifiable(_discoveredStreams.keys);

  /// Safely removes and returns streams matching the given filters.
  /// This transfers ownership/responsibility for destroying the StreamInfos to the caller.
  ///
  /// [streamNameFilter] - Optional filter for stream name (supports prefix, suffix, exact match)
  /// [sourceIdFilter] - Optional filter for source ID (supports prefix, suffix, exact match)
  ///
  /// Returns the matching streams and removes them from the internal list.
  List<StreamInfoResource> takeMatching({
    String? streamNameFilter,
    String? sourceIdFilter,
  }) {
    final matching = <StreamInfoResource>[];
    // convert to list to avoid concurrent modification issues
    for (var entry in _discoveredStreams.entries.toList(growable: false)) {
      final streamInfo = entry.value.streamInfo;
      final matchesName =
          streamNameFilter == null ||
          _matchesFilter(streamInfo.streamName, streamNameFilter);
      final matchesSourceId =
          sourceIdFilter == null ||
          _matchesFilter(streamInfo.sourceId, sourceIdFilter);

      if (matchesName && matchesSourceId) {
        // Ownership is transferred to caller
        final resource = releaseResource<StreamInfoResource>(entry.key);
        matching.add(resource);
      }
    }

    return matching;
  }

  /// Helper method for string matching with prefix/suffix/exact support.
  bool _matchesFilter(String value, String filter) {
    if (filter.startsWith('*') && filter.endsWith('*')) {
      // Contains match: "*text*"
      final searchText = filter.substring(1, filter.length - 1);
      return value.contains(searchText);
    } else if (filter.startsWith('*')) {
      // Suffix match: "*suffix"
      final suffix = filter.substring(1);
      return value.endsWith(suffix);
    } else if (filter.endsWith('*')) {
      // Prefix match: "prefix*"
      final prefix = filter.substring(0, filter.length - 1);
      return value.startsWith(prefix);
    } else {
      // Exact match
      return value == filter;
    }
  }

  /// Performs a one-time discovery and returns the matching streams.
  /// IMPORTANT: The caller is responsible for destroying the returned StreamInfos.
  /// this can be done with [LSLStreamInfo.destroy] or [List<LSLStreamInfo>.destroy]
  ///
  /// This method now runs in an isolate to avoid blocking the main thread.
  static Future<List<LSLStreamInfo>> discoverOnceByPredicate(
    String predicate, {
    Duration timeout = const Duration(seconds: 2),
    int minStreams = 0,
    int maxStreams = 10,
  }) async {
    // Use isolate to avoid blocking main thread
    final streams = await IsolateStreamManager.discoverOnceIsolated(
      predicate: predicate,
      timeout: timeout,
      minStreams: minStreams,
      maxStreams: maxStreams,
    );
    logger.finer(
      'One-time discovery found ${streams.length} stream(s) for predicate: $predicate',
    );
    return streams;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    // Clean up LSL discovery
    logger.fine('Disposing LSL discovery');
    stopDiscovery();
    await _discoveryLock.synchronized(() async {
      if (disposed) return;
      await super.dispose();

      // Close event controller
      logger.finest('Closing discovery event controller');
      // TODO: investigate every stream close with timeout
      // it's happening too often indicating that there are listeners not being
      // properly disposed

      // if (!_eventController.isClosed) {
      //   // await events.drain();
      //   // await _eventController.close().timeout(
      //   //   const Duration(seconds: 2),
      //   //   onTimeout: () {
      //   //     logger.warning('Timeout while closing discovery event controller');
      //   //   },
      //   // );
      // }

      // Ensure no discovery is in progress so we can safely clear the stream
      // infos
      logger.finest('Destroying discovered streams');
      _discoveredStreams.destroy();
      _discoveredStreams.clear();
    });
  }
}
