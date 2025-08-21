import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../event.dart';
import '../../../network/connection_manager.dart';
import '../core/lsl_api_manager.dart';
import '../core/lsl_stream_manager.dart';
import '../core/lsl_data_stream.dart';
import '../config/lsl_stream_config.dart';
import '../config/lsl_channel_format.dart';
import '../../../session/stream_config.dart';
import '../../../utils/stream_controller_extensions.dart';
import '../../../utils/logging.dart';

/// Manages LSL inlet/outlet connections with metadata-based discovery
/// This is a pure ResourceManager that manages LSLStreamManager instances
class LSLConnectionManager implements ConnectionManager {
  @override
  final String managerId;

  final String nodeId;

  // Managed LSL stream managers
  final Map<String, LSLStreamManager> _streamManagers = {};
  final Set<String> _erroredResources = {};

  final StreamController<LSLConnectionEvent> _connectionEventController =
      StreamController<LSLConnectionEvent>.broadcast();

  bool _isActive = false;
  late final ConfiguredLSL _lsl;

  LSLConnectionManager({required this.managerId, required this.nodeId}) {
    _lsl = LSLApiManager.lsl;
  }

  @override
  bool get isActive => _isActive;

  @override
  Stream<ResourceEvent> get events =>
      _connectionEventController.stream.cast<ResourceEvent>();

  /// Stream of LSL-specific connection events
  Stream<LSLConnectionEvent> get connectionEvents =>
      _connectionEventController.stream;

  @override
  Future<void> initialize() async {
    // Connection manager requires LSL to be already initialized
    if (!LSLApiManager.isInitialized) {
      throw LSLApiConfigurationException(
        'LSL API must be initialized before creating connection manager',
      );
    }
  }

  @override
  Future<void> start() async {
    _isActive = true;
    _connectionEventController.addEvent(LSLConnectionManagerStarted(managerId));
  }

  @override
  Future<void> stop() async {
    // Stop all managed stream managers
    final stopFutures = _streamManagers.values.map((manager) async {
      try {
        await manager.deactivate();
      } catch (e) {
        _connectionEventController.addEvent(
          LSLConnectionError(
            managerId,
            'Error stopping manager ${manager.resourceId}: $e',
          ),
        );
      }
    });
    await Future.wait(stopFutures);

    _isActive = false;
    _connectionEventController.addEvent(LSLConnectionManagerStopped(managerId));
  }

  @override
  Future<void> dispose() async {
    await stop();

    // Dispose all managed stream managers
    final disposeFutures = _streamManagers.values.map((manager) async {
      try {
        await manager.dispose();
      } catch (e) {
        logger.warning(
          'Error disposing stream manager ${manager.resourceId}: $e',
        );
      }
    });
    await Future.wait(disposeFutures);
    _streamManagers.clear();

    // Clear error tracking
    _erroredResources.clear();

    try {
      await _connectionEventController.close();
    } catch (e) {
      // Ignore errors during disposal
    }
  }

  @override
  NetworkStats getUsageStats() {
    final totalManagers = _streamManagers.length;

    // Aggregate stats from all managed stream managers
    int totalOutlets = 0;
    int totalInlets = 0;
    int totalResolvers = 0;

    for (final manager in _streamManagers.values) {
      final metadata = manager.metadata;
      totalOutlets += metadata['outlets'] as int? ?? 0;
      totalInlets += metadata['inlets'] as int? ?? 0;
      totalResolvers += metadata['resolvers'] as int? ?? 0;
    }

    return NetworkStats(
      totalResources: totalManagers,
      activeResources: totalManagers,
      idleResources: 0,
      erroredResources: _erroredResources.length,
      lastUpdated: DateTime.now(),
      customMetrics: {
        'streamManagers': totalManagers,
        'totalOutlets': totalOutlets,
        'totalInlets': totalInlets,
        'totalResolvers': totalResolvers,
      },
    );
  }

  /// Create a stream manager and outlet for the given config
  Future<LSLOutlet> createOutletForConfig({
    required LSLStreamConfig config,
    String? outletId,
  }) async {
    final id = outletId ?? '${config.sourceId}_${config.id}_outlet';
    final managerId = '${this.managerId}_manager_${config.sourceId}';

    try {
      // Create a dedicated stream manager for this outlet
      final streamManager = await _prepareOrReuseStreamManager(
        managerId,
        config,
      );
      // Create the outlet through the stream manager
      final streamInfo = await config.toStreamInfo();
      final outlet = await streamManager.createOutlet(
        outletId: id,
        streamInfo: streamInfo,
        pollingConfig: config.pollingConfig,
      );

      _connectionEventController.addEvent(
        LSLOutletCreated(this.managerId, id, config),
      );
      return outlet;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(this.managerId, 'Failed to create outlet $id: $e'),
      );
      rethrow;
    }
  }

  /// Create an LSL inlet for data consumption with continuous discovery
  /// Uses continuous resolver - never blocking, supports dynamic networks
  Future<LSLInlet> createInletByDiscovery({
    required String streamName,
    Map<String, String>? metadataFilters,
    String? inletId,
    LSLTransportConfig? transportConfig,
  }) async {
    final transportConf = transportConfig ?? const LSLTransportConfig();

    try {
      // Build predicate for discovery - NO METADATA, only basic stream matching
      final predicate = transportConf.resolverConfig.dataPredicate(
        streamName,
        metadataFilters: metadataFilters,
      );

      // ALWAYS use continuous resolver - supports dynamic network changes
      final resolver = _lsl.createContinuousStreamResolverByPredicate(
        predicate: predicate,
        forgetAfter: transportConf.resolverConfig.forgetAfter,
        maxStreams: 1,
      );

      // Get currently available streams (non-blocking check)
      var streams = await resolver.resolve(waitTime: 0.0); // Non-blocking
      if (streams.isEmpty) {
        // Wait briefly for streams to appear, but still use continuous discovery
        streams = await resolver.resolve(
          waitTime: transportConf.resolverConfig.resolveWaitTime,
        );
        if (streams.isEmpty) {
          // Keep resolver active for future discovery, don't destroy it
          throw LSLConnectionException(
            'No streams found matching predicate: $predicate (resolver remains active)',
          );
        }
      }

      final streamInfo = streams.first;

      // Create stream config based on basic stream info (NO METADATA YET)
      // Note: Only basic properties available from LSLStreamInfo during discovery
      final discoveredConfig = LSLStreamConfig(
        id: streamInfo.streamName,
        maxSampleRate:
            streamInfo.sampleRate > 0 ? streamInfo.sampleRate : 1000.0,
        pollingFrequency:
            streamInfo.sampleRate > 0 ? streamInfo.sampleRate : 100.0,
        channelCount: streamInfo.channelCount,
        channelFormat: CoordinatorLSLChannelFormat.fromLSL(
          streamInfo.channelFormat,
        ),
        protocol: const ConsumerOnlyProtocol(), // Inlet is consumer
        sourceId:
            streamInfo
                .streamName, // Use streamName as sourceId during discovery
        pollingConfig: const LSLPollingConfig(),
        transportConfig: transportConf,
      );

      // Create stream manager with discovered config
      final streamManagerId = '${managerId}_manager_$streamName';

      final streamManager = await _prepareOrReuseStreamManager(
        streamManagerId,
        discoveredConfig,
      );

      final id =
          inletId ?? '${streamInfo.sourceId}_${discoveredConfig.id}_inlet';
      // Create inlet - metadata will be available via inlet.getFullInfo() if needed
      final inlet = await streamManager.createInlet(
        inletId: id,
        streamInfo: streamInfo,
      );

      // Clean up unused streams but KEEP resolver active for ongoing discovery
      streams.skip(1).toList().destroy();
      // Note: resolver stays active to detect dynamic network changes

      _connectionEventController.addEvent(
        LSLInletCreated(managerId, id, streamInfo),
      );
      return inlet;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(
          managerId,
          'Failed to create inlet ${inletId ?? 'unknown'}: $e',
        ),
      );
      rethrow;
    }
  }

  /// Create a continuous resolver for ongoing stream discovery
  /// Pure discovery - no stream managers or configs needed!
  LSLStreamResolverContinuous createContinuousResolver({
    String? predicate,
    String? resolverId,
    double? forgetAfter,
    int? maxStreams,
  }) {
    final id =
        resolverId ?? 'resolver_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Pure discovery using LSL API directly
      final resolver =
          predicate != null
              ? _lsl.createContinuousStreamResolverByPredicate(
                predicate: predicate,
                forgetAfter: forgetAfter ?? 5.0,
                maxStreams: maxStreams ?? 50,
              )
              : _lsl.createContinuousStreamResolver(
                forgetAfter: forgetAfter ?? 5.0,
                maxStreams: maxStreams ?? 50,
              );

      _connectionEventController.addEvent(
        LSLResolverCreated(managerId, id, predicate),
      );

      // Store resolver reference for cleanup (no stream manager needed)
      // Note: We could track these separately if needed for cleanup

      return resolver;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Failed to create resolver $id: $e'),
      );
      rethrow;
    }
  }

  /// Get an outlet by ID (searches all managed stream managers)
  LSLOutlet? getOutlet(String outletId) {
    for (final manager in _streamManagers.values) {
      final outlet = manager.getOutlet(outletId);
      if (outlet != null) return outlet;
    }
    return null;
  }

  /// Get an inlet by ID (searches all managed stream managers)
  LSLInlet? getInlet(String inletId) {
    for (final manager in _streamManagers.values) {
      final inlet = manager.getInlet(inletId);
      if (inlet != null) return inlet;
    }
    return null;
  }

  /// Get a resolver by ID (searches all managed stream managers)
  LSLStreamResolverContinuous? getResolver(String resolverId) {
    for (final manager in _streamManagers.values) {
      final resolver = manager.getResolver(resolverId);
      if (resolver != null) return resolver;
    }
    return null;
  }

  /// Destroy an outlet and remove from management
  Future<void> destroyOutlet(String outletId) async {
    try {
      // Find and remove outlet from appropriate stream manager
      for (final manager in _streamManagers.values) {
        if (manager.hasOutlet(outletId)) {
          await manager.removeOutlet(outletId);
          _connectionEventController.addEvent(
            LSLOutletDestroyed(managerId, outletId),
          );
          return;
        }
      }
      throw LSLConnectionException('Outlet $outletId not found');
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Error destroying outlet $outletId: $e'),
      );
      rethrow;
    }
  }

  /// Destroy an inlet and remove from management
  Future<void> destroyInlet(String inletId) async {
    try {
      // Find and remove inlet from appropriate stream manager
      for (final manager in _streamManagers.values) {
        if (manager.hasInlet(inletId)) {
          await manager.removeInlet(inletId);
          _connectionEventController.addEvent(
            LSLInletDestroyed(managerId, inletId),
          );
          return;
        }
      }
      throw LSLConnectionException('Inlet $inletId not found');
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Error destroying inlet $inletId: $e'),
      );
      rethrow;
    }
  }

  /// Destroy a resolver and remove from management
  void destroyResolver(String resolverId) {
    try {
      // Find and remove resolver from appropriate stream manager
      for (final manager in _streamManagers.values) {
        if (manager.hasResolver(resolverId)) {
          manager.removeResolver(resolverId);
          _connectionEventController.addEvent(
            LSLResolverDestroyed(managerId, resolverId),
          );
          return;
        }
      }
      throw LSLConnectionException('Resolver $resolverId not found');
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(
          managerId,
          'Error destroying resolver $resolverId: $e',
        ),
      );
    }
  }

  /// List all managed outlet IDs
  List<String> get outletIds {
    // Extract from metadata or iterate through base class resources
    final outlets = <String>[];
    // Base class doesn't expose internal maps, so we rely on metadata
    return outlets;
  }

  /// List all managed inlet IDs
  List<String> get inletIds {
    final inlets = <String>[];
    return inlets;
  }

  /// List all managed resolver IDs
  List<String> get resolverIds {
    final resolvers = <String>[];
    return resolvers;
  }

  /// List all errored resource IDs
  List<String> get erroredResourceIds {
    // Extract from base class metadata
    return [];
  }

  /// Mark a resource as errored
  void markResourceErrored(String resourceId, String error) {
    if (!_connectionEventController.isClosed) {
      _connectionEventController.add(
        LSLConnectionError(managerId, 'Resource $resourceId errored: $error'),
      );
    }
  }

  /// Clear error state for a resource (when it recovers)
  void clearResourceError(String resourceId) {
    if (!_connectionEventController.isClosed) {
      _connectionEventController.add(
        LSLConnectionRecovered(managerId, resourceId),
      );
    }
  }

  /// Check if a resource is in error state
  bool isResourceErrored(String resourceId) {
    // This would need to check base class error tracking
    return false;
  }

  /// Check if an inlet exists (compatibility method for coordination session)
  bool hasInlet(String inletId) {
    return getInlet(inletId) != null;
  }

  /// Create an inlet using a stream info (compatibility method)
  Future<LSLInlet> createInlet({
    required String inletId,
    required LSLStreamInfo streamInfo,
  }) async {
    final managerId = '${this.managerId}_manager_${streamInfo.streamName}';

    try {
      // Create a dedicated stream manager for this inlet
      final tempConfig = LSLStreamConfig(
        id: streamInfo.streamName,
        maxSampleRate: 1000.0, // Default sample rate
        pollingFrequency: 100.0, // Default polling frequency
        channelCount: streamInfo.channelCount,
        channelFormat: CoordinatorLSLChannelFormat.float32, // Default format
        protocol: const ConsumerOnlyProtocol(), // Default consumer-only
        sourceId: streamInfo.streamName,
        pollingConfig: const LSLPollingConfig(),
        transportConfig: const LSLTransportConfig(),
      );
      final streamManager = await _prepareOrReuseStreamManager(
        managerId,
        tempConfig,
      );

      final inlet = await streamManager.createInlet(
        inletId: inletId,
        streamInfo: streamInfo,
      );

      _connectionEventController.addEvent(
        LSLInletCreated(this.managerId, inletId, streamInfo),
      );
      return inlet;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(
          this.managerId,
          'Failed to create inlet $inletId: $e',
        ),
      );
      rethrow;
    }
  }

  /// Create an outlet using a stream config (compatibility method)
  Future<LSLOutlet> createOutlet({
    required String outletId,
    required LSLStreamConfig config,
  }) async {
    return createOutletForConfig(config: config, outletId: outletId);
  }

  /// Create a stream manager for a given config
  LSLStreamManager _createStreamManager(
    String managerId,
    LSLStreamConfig config,
  ) {
    return LSLDataStream(
      streamId: config.id,
      nodeId: nodeId,
      config: config,
      connectionManager: this,
    );
  }

  Future<LSLStreamManager> _prepareOrReuseStreamManager(
    String managerId,
    LSLStreamConfig config,
  ) async {
    if (!_streamManagers.containsKey(managerId)) {
      final streamManager = _createStreamManager(managerId, config);
      _streamManagers[managerId] = streamManager;
      await streamManager.initialize();
      await streamManager.activate();
    }
    return _streamManagers[managerId]!;
  }
}

/// Exception for LSL connection operations
class LSLConnectionException implements Exception {
  final String message;

  const LSLConnectionException(this.message);

  @override
  String toString() => 'LSLConnectionException: $message';
}

/// Events specific to LSL connections
sealed class LSLConnectionEvent extends TimestampedEvent {
  final String resourceId;

  const LSLConnectionEvent(this.resourceId, DateTime timestamp)
    : super(eventId: 'lsl_connection_event_$resourceId', timestamp: timestamp);
}

class LSLConnectionManagerStarted extends LSLConnectionEvent {
  LSLConnectionManagerStarted(String managerId)
    : super(managerId, DateTime.now());
}

class LSLConnectionManagerStopped extends LSLConnectionEvent {
  LSLConnectionManagerStopped(String managerId)
    : super(managerId, DateTime.now());
}

class LSLOutletCreated extends LSLConnectionEvent {
  final LSLStreamConfig config;

  LSLOutletCreated(String managerId, String outletId, this.config)
    : super('${managerId}_outlet_$outletId', DateTime.now());
}

class LSLOutletDestroyed extends LSLConnectionEvent {
  LSLOutletDestroyed(String managerId, String outletId)
    : super('${managerId}_outlet_$outletId', DateTime.now());
}

class LSLInletCreated extends LSLConnectionEvent {
  final LSLStreamInfo streamInfo;

  LSLInletCreated(String managerId, String inletId, this.streamInfo)
    : super('${managerId}_inlet_$inletId', DateTime.now());
}

class LSLInletDestroyed extends LSLConnectionEvent {
  LSLInletDestroyed(String managerId, String inletId)
    : super('${managerId}_inlet_$inletId', DateTime.now());
}

class LSLResolverCreated extends LSLConnectionEvent {
  final String? predicate;

  LSLResolverCreated(String managerId, String resolverId, this.predicate)
    : super('${managerId}_resolver_$resolverId', DateTime.now());
}

class LSLResolverDestroyed extends LSLConnectionEvent {
  LSLResolverDestroyed(String managerId, String resolverId)
    : super('${managerId}_resolver_$resolverId', DateTime.now());
}

class LSLConnectionError extends LSLConnectionEvent {
  final String error;

  LSLConnectionError(String managerId, this.error)
    : super('${managerId}_error', DateTime.now());
}

class LSLConnectionRecovered extends LSLConnectionEvent {
  LSLConnectionRecovered(String managerId, String resourceId)
    : super('${managerId}_recovered_$resourceId', DateTime.now());
}
