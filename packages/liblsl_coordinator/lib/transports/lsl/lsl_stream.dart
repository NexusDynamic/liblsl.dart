import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

extension LSLType on StreamDataType {
  /// Converts a [StreamDataType] to the corresponding LSL channel format.
  LSLChannelFormat toLSLChannelFormat() {
    switch (this) {
      case StreamDataType.int8:
        return LSLChannelFormat.int8;
      case StreamDataType.int16:
        return LSLChannelFormat.int16;
      case StreamDataType.int32:
        return LSLChannelFormat.int32;
      case StreamDataType.int64:
        return LSLChannelFormat.int64;
      case StreamDataType.float32:
        return LSLChannelFormat.float32;
      case StreamDataType.double64:
        return LSLChannelFormat.double64;
      case StreamDataType.string:
        return LSLChannelFormat.string;
    }
  }
}

/// Helper class with static methods for working with LSL StreamInfo
/// Especially a unified way of working with the metadata, or standardized
/// stream names for discovery.
class LSLStreamInfoHelper {
  static const String streamNameKey = 'stream_name';
  static const String sessionNameKey = 'session';
  static const String nodeIdKey = 'node_id';
  static const String nodeUIdKey = 'node_uid';
  static const String nodeRoleKey = 'node_role';
  static const String nodeCapabilitiesKey = 'node_capabilities';
  static const String randomRollKey = 'random_roll';
  static const String nodeStartedAtKey = 'node_started_at';

  /// Generates a standardized stream name for a given stream configuration
  /// and node information.
  /// Now uses clean names without encoding node/role information in the name.
  /// All filtering information is stored in metadata instead.
  static String generateStreamName(
    NetworkStreamConfig config, {
    required Node node,
  }) {
    // Use clean stream name - all other info goes in metadata
    return config.name;
  }

  /// Generates a unique source ID for a given stream configuration and node.
  /// This ensures each outlet has a globally unique source ID that identifies:
  /// 1. The source node (nodeId)
  /// 2. The stream type/name
  /// 3. A unique identifier (nodeUID) to guarantee uniqueness per outlet
  /// Format: nodeId_streamName_nodeUID
  static String generateSourceID(
    NetworkStreamConfig config, {
    required Node node,
  }) {
    return '${config.name}//${node.role}//${node.uId}//${node.id}';
  }

  static Map<String, String> parseSourceId(String name) {
    final parts = name.split('//');
    if (parts.length < 4) {
      throw FormatException('Invalid stream name format: $name');
    }
    return {
      nodeIdKey: parts[3],
      nodeRoleKey: parts[1],
      nodeUIdKey: parts[2],
      streamNameKey: parts[0],
    };
  }

  /// Creates a stream info for use in an inlet, based on the expected
  /// configuration based on the node and session.
  static Future<LSLStreamInfo> generateInletStreamInfo({
    required NetworkStreamConfig config,
    required CoordinationSessionConfig sessionConfig,
    required Node node,
  }) async {
    final streamName = generateStreamName(config, node: node);
    final sourceId = generateSourceID(config, node: node);
    final LSLStreamInfo info = await LSL.createStreamInfo(
      streamName: streamName,
      streamType: LSLContentType.markers,
      channelCount: config.channels,
      channelFormat: config.dataType.toLSLChannelFormat(),
      sampleRate: config.sampleRate,
      sourceId: sourceId, // Use unique source ID
    );
    return info;
  }

  /// Create a stream info (for use in an outlet) from the given parameters.
  static Future<LSLStreamInfoWithMetadata> createStreamInfo({
    required NetworkStreamConfig config,
    required CoordinationSessionConfig sessionConfig,
    required Node node,
  }) async {
    final streamName = generateStreamName(config, node: node);
    final sourceId = generateSourceID(config, node: node);

    final LSLStreamInfoWithMetadata info = await LSL.createStreamInfo(
      streamName: streamName,
      streamType: LSLContentType.markers,
      channelCount: config.channels,
      channelFormat: config.dataType.toLSLChannelFormat(),
      sampleRate: config.sampleRate,
      sourceId: sourceId, // Use unique source ID
    );

    // Add standard metadata
    final LSLDescription infoMetadata = info.description;
    final LSLXmlNode rootElement = infoMetadata.value;
    rootElement.addChildValue(sessionNameKey, sessionConfig.name);
    rootElement.addChildValue(nodeIdKey, node.id);
    rootElement.addChildValue(
      nodeRoleKey,
      node.getMetadata('role', defaultValue: 'none'),
    );
    rootElement.addChildValue(
      nodeCapabilitiesKey,
      (node.capabilities.join(',')),
    );

    // Add random roll if available
    final randomRoll = node.getMetadata('randomRoll');
    if (randomRoll != null) {
      rootElement.addChildValue(randomRollKey, randomRoll);
    }

    // Add node started time if available
    final nodeStartedAt = node.getMetadata('nodeStartedAt');
    if (nodeStartedAt != null) {
      rootElement.addChildValue(nodeStartedAtKey, nodeStartedAt);
    }

    rootElement.addChildValue(nodeUIdKey, node.uId);

    logger.finer("Created streamInfo from for node: $node");

    return info;
  }

  /// Parses standard metadata from the given [LSLStreamInfoWithMetadata].
  static Map<String, String> parseMetadata(LSLStreamInfoWithMetadata info) {
    final Map<String, String> metadata = {};
    final LSLDescription description = info.description;
    final LSLXmlNode rootElement = description.value;
    for (final child in rootElement.children) {
      if (!child.isText()) continue;
      try {
        metadata[child.name] = child.textValue;
      } catch (e) {
        // ignore malformed metadata entries
        logger.warning('Failed to parse metadata entry ${child.name}: $e');
        continue;
      }
    }
    return metadata;
  }

  /// Generates an LSL stream resolver predicate based on the given parameters.
  /// Any parameter that is null is ignored in the predicate.
  /// For example, to find streams with a specific name prefix and session name:
  /// ```dart
  /// final predicate = LSLStreamInfoHelper.generatePredicate(
  ///   streamNamePrefix: 'mystream',
  ///   sessionName: 'mysession',
  /// );```
  /// This would generate a predicate like:
  /// "starts-with(name, 'mystream') and //info/desc/session='mysession'"
  ///
  /// For metadata filtering (promotion strategy):
  /// ```dart
  /// final predicate = LSLStreamInfoHelper.generatePredicate(
  ///   streamNamePrefix: 'coordination',
  ///   sessionName: 'mysession',
  ///   randomRollLessThan: myRandomRoll,
  /// );```
  ///
  /// which can be used with [LSLStreamResolverContinuousByPredicate].
  static String generatePredicate({
    String? streamNamePrefix,
    String? streamNameSuffix,
    String? sessionName,
    String? nodeId,
    String? nodeUId,
    String? nodeRole,
    String? nodeCapabilities,
    String? sourceIdPrefix,
    String? sourceIdSuffix,
    String? excludeSourceId,
    String? excludeSourceIdPrefix, // New parameter for prefix exclusion
    // Metadata filtering options for promotion strategy
    double? randomRollLessThan,
    double? randomRollGreaterThan,
    String? nodeStartedBefore,
    String? nodeStartedAfter,
  }) {
    final List<String> conditions = [];
    if (streamNamePrefix != null) {
      conditions.add("starts-with(name, '$streamNamePrefix')");
    }
    if (streamNameSuffix != null) {
      conditions.add("ends-with(name, '$streamNameSuffix')");
    }
    if (sourceIdPrefix != null) {
      conditions.add("starts-with(source_id, '$sourceIdPrefix')");
    }
    if (sourceIdSuffix != null) {
      conditions.add("ends-with(source_id, '$sourceIdSuffix')");
    }
    if (excludeSourceId != null) {
      conditions.add("not(source_id='$excludeSourceId')");
    }
    if (excludeSourceIdPrefix != null) {
      conditions.add("not(starts-with(source_id, '$excludeSourceIdPrefix'))");
    }
    if (sessionName != null) {
      conditions.add("//info/desc/$sessionNameKey='$sessionName'");
    }
    if (nodeId != null) {
      conditions.add("//info/desc/$nodeIdKey='$nodeId'");
    }
    if (nodeUId != null) {
      conditions.add("//info/desc/$nodeUIdKey='$nodeUId'");
    }
    if (nodeRole != null) {
      conditions.add("//info/desc/$nodeRoleKey='$nodeRole'");
    }
    if (nodeCapabilities != null) {
      conditions.add("//info/desc/$nodeCapabilitiesKey='$nodeCapabilities'");
    }
    // Metadata filtering for promotion strategy
    if (randomRollLessThan != null) {
      conditions.add("//info/desc/$randomRollKey < $randomRollLessThan");
    }
    if (randomRollGreaterThan != null) {
      conditions.add("//info/desc/$randomRollKey > $randomRollGreaterThan");
    }
    if (nodeStartedBefore != null) {
      conditions.add("//info/desc/$nodeStartedAtKey < '$nodeStartedBefore'");
    }
    if (nodeStartedAfter != null) {
      conditions.add("//info/desc/$nodeStartedAtKey > '$nodeStartedAfter'");
    }

    if (conditions.isEmpty) {
      throw ArgumentError('At least one parameter must be provided');
    }
    return conditions.join(' and ');
  }

  /// Generates a predicate for coordinator election that checks for:
  /// - Existing coordinators, OR
  /// - Better candidates based on the election strategy
  static String generateElectionPredicate({
    required String streamName,
    required String sessionName,
    required String excludeSourceIdPrefix,
    required bool isRandomStrategy,
    double? myRandomRoll,
    String? myStartTime,
  }) {
    // Base conditions that apply to all candidates
    final baseConditions = [
      "starts-with(name, '$streamName')",
      "//info/desc/$sessionNameKey='$sessionName'",
      "not(starts-with(source_id, '$excludeSourceIdPrefix'))",
    ];

    // Election-specific conditions (OR logic)
    final List<String> electionConditions = [];

    // Always check for existing coordinators
    electionConditions.add("//info/desc/$nodeRoleKey='coordinator'");

    if (isRandomStrategy && myRandomRoll != null) {
      // For random strategy: also check for better random rolls
      electionConditions.add("//info/desc/$randomRollKey < $myRandomRoll");
    } else if (!isRandomStrategy && myStartTime != null) {
      // For first strategy: also check for earlier nodes
      electionConditions.add("//info/desc/$nodeStartedAtKey < '$myStartTime'");
    }

    // Combine base conditions (AND) with election conditions (OR)
    final baseQuery = baseConditions.join(' and ');
    final electionQuery = electionConditions.join(' or ');

    return '$baseQuery and ($electionQuery)';
  }

  /// f
}

/// Mixin providing shared LSL functionality for both coordination and data streams
/// mixin with isolate support for LSL streams
mixin LSLStreamMixin<T extends NetworkStreamConfig, M extends IMessage>
    on NetworkStream<T, M> {
  // Abstract getters to be implemented
  Node get streamNode;
  CoordinationSessionConfig get streamSessionConfig;
  LSLTransport get lslTransport;

  // Control flags
  bool get useIsolates => true; // Default to using isolates
  // Separate settings for inlets vs outlets
  bool get useBusyWaitInlets => false; // Override in data streams
  bool get useBusyWaitOutlets => false; // Event-driven outlets by default

  // Isolate instances
  StreamInletIsolate? _inletIsolate;
  StreamOutletIsolate? _outletIsolate;

  // LSL resources
  OutletResource? _outletResource;
  final List<InletResource> _inletResources = <InletResource>[];
  final List<LSLStreamInfo> _inletStreamInfos = <LSLStreamInfo>[];

  // Message handling
  final StreamController<M> _incomingController = StreamController<M>();
  final StreamController<M> _outgoingController = StreamController<M>();

  StreamSubscription? _outgoingSubscription;
  StreamSubscription? _incomingSubscription;

  // State
  bool _created = true;
  bool _disposed = false;
  bool _started = false;
  IResourceManager? _manager;

  @override
  bool get created => _created;

  @override
  bool get disposed => _disposed;

  @override
  IResourceManager? get manager => _manager;

  bool get started => _started;

  @override
  Future<void> create() async {
    if (_created) return;
    if (_disposed) throw StateError('Cannot create disposed stream');

    // No isolate setup needed here - isolates are created per stream operation

    // // Create outlet
    // final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
    //   config: config,
    //   sessionConfig: streamSessionConfig,
    //   node: streamNode,
    // );

    // // Setup outlet based on isolate usage
    // if (useIsolates) {
    //   // Create outlet isolate instance
    //   _outletIsolate = IsolateStreamManager.createOutletIsolate(
    //     streamId: id,
    //     dataType: config.dataType,
    //     useBusyWaitInlets: useBusyWaitInlets,
    //     useBusyWaitOutlets: useBusyWaitOutlets,
    //     pollingInterval: _getPollingInterval(),
    //     outletAddress: streamInfo.streamInfo.address,
    //     channelCount: config.channels,
    //     sampleRate: config.sampleRate,
    //   );
    //   await _outletIsolate!.create();
    //   // Don't create outlet in main thread when using isolates
    //   _outletResource = null;
    // } else {
    //   // When not using isolates: create outlet in main thread
    //   _outletResource = await lslTransport.createOutlet(streamInfo: streamInfo);
    // }

    _created = true;

    // Start processing outbox
    _startOutboxProcessing();
  }

  Duration _getPollingInterval() {
    if (useBusyWaitOutlets) {
      // For busy-wait, use microsecond precision based on sample rate
      final microsecondsPerSample = (1000000 / config.sampleRate).round();
      return Duration(microseconds: microsecondsPerSample);
    } else {
      // For coordination streams, use reasonable polling interval
      return Duration(milliseconds: 10);
    }
  }

  @override
  void updateManager(IResourceManager? newManager) {
    if (_disposed) {
      throw StateError('Resource has been disposed');
    }
    if (_manager == newManager) {
      logger.finest(
        'Resource manager is already set to ${newManager?.name} (${newManager?.uId})',
      );
      return;
    }
    if (_manager != null && newManager != null) {
      throw StateError(
        'Resource is already managed by ${_manager!.name} (${_manager!.uId}) '
        'please release it before assigning a new manager',
      );
    }
    _manager = newManager;
  }

  /// Add inlet for receiving from another node
  /// Checks if an inlet already exists for the given source ID
  bool hasInletForSource(String sourceId) {
    if (useIsolates) {
      // When using isolates, check StreamInfo list
      return _inletStreamInfos.any(
        (streamInfo) => streamInfo.sourceId == sourceId,
      );
    } else {
      // When not using isolates, check inlet resources
      return _inletResources.any(
        (inletResource) => inletResource.inlet.streamInfo.sourceId == sourceId,
      );
    }
  }

  void updateNode(Node newNode);

  Future<void> addInlet(LSLStreamInfo streamInfo) async {
    if (_disposed) return;

    if (hasInletForSource(streamInfo.sourceId)) {
      logger.finer('Inlet for source ${streamInfo.sourceId} already exists');
      return;
    }

    if (useIsolates) {
      _inletStreamInfos.add(streamInfo);

      // Create inlet isolate if it doesn't exist
      if (_inletIsolate == null) {
        final mySourceId = LSLStreamInfoHelper.generateSourceID(
          config,
          node: streamNode,
        );
        _inletIsolate = IsolateStreamManager.createInletIsolate(
          streamId: id,
          dataType: config.dataType,
          useBusyWaitInlets: useBusyWaitInlets,
          useBusyWaitOutlets: useBusyWaitOutlets,
          pollingInterval: _getPollingInterval(),
          initialInletAddresses:
              _inletStreamInfos.map((info) => info.streamInfo.address).toList(),
          isolateDebugName: 'inlet:$mySourceId',
        );
        await _inletIsolate!.create();

        // Listen to incoming data from inlet isolate
        _incomingSubscription = _inletIsolate!.incomingData.listen((
          dataMessage,
        ) {
          final message = _createMessageFromIsolateData(dataMessage);
          if (message != null) {
            _incomingController.add(message);
          }
        });

        // Start the inlet isolate if the stream is already started
        if (_started) {
          await _inletIsolate!.start();
        }
      } else {
        // Add inlet to existing isolate
        await _inletIsolate!.addInlet(streamInfo.streamInfo.address);
      }
    } else {
      // When not using isolates: create inlet in main thread
      final inletResource = await lslTransport.createInlet(
        streamInfo: streamInfo,
        includeMetadata: true,
      );
      _inletResources.add(inletResource);
    }

    // we don't want to auto start
    // Start if not already started
    // if (!_started) {
    //   await start();
    // }
  }

  Future<void> createResolvedInletsForStream(
    Iterable<Node> nodes, {
    Duration resolveTimeout = const Duration(seconds: 10),
  }) async {
    if (nodes.isEmpty) return;
    final streamInfos = await LslDiscovery.discoverOnceByPredicate(
      LSLStreamInfoHelper.generatePredicate(
        streamNamePrefix: config.name,
        sessionName: streamSessionConfig.name,
      ),
      minStreams: nodes.length,
      maxStreams: nodes.length,
      timeout: resolveTimeout,
    );

    for (final node in nodes) {
      final matchingInfo = streamInfos.firstWhere(
        (info) {
          final parsedSource = LSLStreamInfoHelper.parseSourceId(info.sourceId);
          return parsedSource[LSLStreamInfoHelper.nodeUIdKey] == node.uId;
        },
        orElse:
            () =>
                throw StateError(
                  'No matching stream info found for node ${node.id} (${node.uId})',
                ),
      );
      await addInlet(matchingInfo);
      logger.finest('Created resolved inlet for node ${node.id} (${node.uId})');
    }
  }

  /// Generates a streamInfo and creates an inlet based on the expected node
  /// and session
  Future<void> createInletForNode(
    Node node, {
    bool resolveInfo = false,
    Duration resolveTimeout = const Duration(seconds: 5),
  }) async {
    if (_disposed) return;
    if (hasInletForSource(node.uId)) {
      logger.finer('Inlet for node ${node.id} (${node.uId}) already exists');
      return;
    }

    LSLStreamInfo streamInfo;
    if (!resolveInfo) {
      streamInfo = await LSLStreamInfoHelper.generateInletStreamInfo(
        config: config,
        sessionConfig: streamSessionConfig,
        node: node,
      );
    } else {
      final streamInfos = await LslDiscovery.discoverOnceByPredicate(
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: config.name,
          sessionName: streamSessionConfig.name,
          nodeUId: node.uId,
        ),
        minStreams: 1,
        maxStreams: 1,
        timeout: resolveTimeout,
      );
      if (streamInfos.isEmpty) {
        throw StateError(
          'Failed to resolve stream info for node ${node.id} (${node.uId})',
        );
      }
      streamInfo = streamInfos.first;
    }

    logger.fine(
      'INLET: ${config.name} - targeting sourceId: ${LSLStreamInfoHelper.generateSourceID(config, node: node)}, dataType: ${config.dataType}, channels: ${config.channels}, sampleRate: ${config.sampleRate}',
    );

    await addInlet(streamInfo);
  }

  Future<void> start() async {
    if (_started) return;
    logger.info('Starting LSL stream ${config.name}');
    _started = true;

    if (useIsolates) {
      if (_outletIsolate != null) {
        await _outletIsolate!.start();
      }
      if (_inletIsolate != null) {
        await _inletIsolate!.start();
      }
    } else {
      // Direct mode - start polling timers
      _startDirectPolling();
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    logger.info('Stopping LSL stream ${config.name}');

    if (_outletIsolate != null) {
      await _outletIsolate!.stop();
    }
    if (_inletIsolate != null) {
      await _inletIsolate!.stop();
    }
  }

  void _startDirectPolling() {
    // For non-isolate mode, use regular timers
    Timer.periodic(_getPollingInterval(), (_) async {
      if (!_started || paused) return;

      for (final inletResource in _inletResources) {
        try {
          final sample = await inletResource.inlet.pullSample(timeout: 0.0);
          if (sample.isNotEmpty) {
            final message = _createMessageFromSample(sample);
            if (message != null) {
              _incomingController.add(message);
            }
          }
        } catch (e) {
          logger.warning('Error polling inlet: $e');
        }
      }
    });
  }

  void _startOutboxProcessing() {
    _outgoingSubscription = _outgoingController.stream.listen((message) async {
      if (!_started || paused) return;

      final sampleData = _createSampleFromMessage(message);

      if (useIsolates && _outletIsolate != null) {
        // Send through isolate
        await _outletIsolate!.sendData(sampleData);
      } else if (_outletResource != null) {
        // Direct send
        try {
          _outletResource!.outlet.pushSample(sampleData);
        } catch (e) {
          logger.warning('Failed to send message: $e');
        }
      }
    });
  }

  // Abstract methods to be implemented by subclasses
  M? _createMessageFromSample(LSLSample sample) => null;
  M? _createMessageFromIsolateData(IsolateDataMessage data) => null;
  List<dynamic> _createSampleFromMessage(M message) => [message.toString()];

  @override
  Future<void> sendMessage(M message) async {
    if (!_started) throw StateError('Stream not started');
    _outgoingController.add(message);
  }

  @override
  Stream<M> get inbox => _incomingController.stream;

  @override
  StreamSink<M> get outbox => _outgoingController.sink;

  @override
  Future<void> pause() async {
    if (paused) return;
    if (_outletIsolate != null) {
      await _outletIsolate!.stop();
    }
    if (_inletIsolate != null) {
      await _inletIsolate!.stop();
    }
    super.pause();
  }

  @override
  Future<void> resume() async {
    if (!paused) return;
    if (_outletIsolate != null) {
      await _outletIsolate!.start();
    }
    if (_inletIsolate != null) {
      await _inletIsolate!.start();
    }
    super.resume();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    logger.info('Disposing LSL stream ${config.name}');

    logger.finest('Disposing message controllers for stream ${config.name}');
    await _outgoingSubscription?.cancel();
    await _incomingSubscription?.cancel();
    await _incomingController.close().timeout(
      Duration(seconds: 2),
      onTimeout: () {
        logger.warning(
          'Timeout closing incoming controller for ${config.name}, forcing close',
        );
      },
    );
    await _outgoingController.close().timeout(
      Duration(seconds: 2),
      onTimeout: () {
        logger.warning(
          'Timeout closing outgoing controller for ${config.name}, forcing close',
        );
      },
    );

    logger.finer('Stopping stream ${config.name} before disposal');
    await stop();

    // Dispose isolate instances
    if (_outletIsolate != null) {
      logger.finest('Disposing outlet isolate for stream ${config.name}');
      await _outletIsolate!.dispose().timeout(
        Duration(seconds: 5),
        onTimeout: () {
          logger.warning(
            'Timeout disposing outlet isolate for ${config.name}, forcing dispose',
          );
        },
      );
    }
    if (_inletIsolate != null) {
      logger.finest('Disposing inlet isolate for stream ${config.name}');
      await _inletIsolate!.dispose().timeout(
        Duration(seconds: 5),
        onTimeout: () {
          logger.warning(
            'Timeout disposing inlet isolate for ${config.name}, forcing dispose',
          );
        },
      );
    }
    // Dispose LSL resources
    _outletResource?.dispose();
    for (final inletResource in _inletResources) {
      inletResource.dispose();
    }
    _inletResources.clear();

    // Dispose StreamInfos (main thread's responsibility)
    for (final streamInfo in _inletStreamInfos) {
      streamInfo.destroy();
    }
    _inletStreamInfos.clear();

    _disposed = true;
  }

  /// Call this if the stream configuration changes and you need to
  /// recreate the outlet with updated settings (so other nodes can see changes)
  /// Be careful, because it will cause issues if there are inlets connected
  /// to the old outlet.
  Future<void> recreateOutlet() async {
    if (_disposed) {
      throw StateError('Cannot recreate outlet of disposed stream');
    }
    if (_outletResource == null && _outletIsolate == null) {
      throw StateError('No outlet to recreate');
    }

    // Create stream info using existing configuration
    final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
      config: config,
      sessionConfig: streamSessionConfig,
      node: streamNode,
    );

    logger.fine(
      'Recreating outlet for stream ${config.name} with streamInfo: $streamInfo',
    );

    if (useIsolates && _outletIsolate != null) {
      // Recreate outlet in isolate
      return await _outletIsolate!.recreateOutlet(
        streamInfo.streamInfo.address,
      );
    } else if (_outletResource != null) {
      // Recreate outlet in main thread
      // @TODO: implement recreateOutlet in OutletResource
      // return _outletResource!.recreateOutlet();
    } else {
      throw StateError('No outlet to recreate');
    }
  }

  /// Create an outlet for this stream using the existing configuration
  /// No arguments needed - uses stream config and node metadata
  Future<void> createOutlet() async {
    if (_outletResource != null || _outletIsolate != null) {
      logger.fine('Outlet already exists for stream ${config.name}');
      return;
    }

    logger.info('Creating outlet for stream ${config.name}');

    // Create stream info using existing configuration
    final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
      config: config,
      sessionConfig: streamSessionConfig,
      node: streamNode,
    );

    logger.finer(
      'OUTLET: ${config.name} - sourceId: ${streamInfo.sourceId}, dataType: ${config.dataType}, channels: ${config.channels}, sampleRate: ${config.sampleRate}',
    );

    if (useIsolates) {
      // Create outlet isolate
      logger.finest(
        '[${streamNode.id}] Creating outlet isolate for stream ${config.name} ',
      );
      final mySourceId = LSLStreamInfoHelper.generateSourceID(
        config,
        node: streamNode,
      );
      _outletIsolate = StreamOutletIsolate(
        streamId: id,
        dataType: config.dataType,
        pollingInterval: _getPollingInterval(),
        outletAddress: streamInfo.streamInfo.address,
        channelCount: config.channels,
        sampleRate: config.sampleRate,
        useBusyWaitInlets: useBusyWaitInlets,
        useBusyWaitOutlets: useBusyWaitOutlets,
        isolateDebugName: 'outlet:$mySourceId',
      );
      await _outletIsolate!.create();
      // Connect outgoing messages to isolate
      _outgoingSubscription = _outgoingController.stream.listen((
        message,
      ) async {
        if (!_disposed && _outletIsolate != null) {
          final sampleData = _createSampleFromMessage(message);
          await _outletIsolate!.sendData(sampleData);
        }
      });
      await _outletIsolate!.start();
      logger.finest('Outlet isolate for stream ${config.hashCode} started');
    } else {
      // Create outlet resource directly
      _outletResource = await lslTransport.createOutlet(streamInfo: streamInfo);

      // Connect outgoing messages to outlet
      _outgoingSubscription = _outgoingController.stream.listen((
        message,
      ) async {
        if (!_disposed && _outletResource != null) {
          final sampleData = _createSampleFromMessage(message);
          try {
            _outletResource!.outlet.pushSample(sampleData);
          } catch (e) {
            logger.warning('Failed to send message: $e');
          }
        }
      });

      logger.finer('Created outlet for stream ${config.name}');
    }
  }
}

/// LSL-based data stream implementation
// ignore: missing_override_of_must_be_overridden
class LSLDataStream extends DataStream<DataStreamConfig, IMessage>
    with RuntimeTypeUID, LSLStreamMixin<DataStreamConfig, IMessage> {
  @override
  Node get streamNode => _streamNode;
  Node _streamNode;
  @override
  final CoordinationSessionConfig streamSessionConfig;
  @override
  final LSLTransport lslTransport;

  @override
  bool get useBusyWaitInlets => true; // Use busy-wait for data stream inlets
  @override
  bool get useBusyWaitOutlets => false; // Event-driven outlets for data streams

  // Typed data stream based on config
  final StreamController<List<dynamic>> _typedDataController =
      StreamController<List<dynamic>>();

  Stream<List<dynamic>> get dataStream => _typedDataController.stream;

  LSLDataStream({
    required DataStreamConfig config,
    required Node streamNode,
    required this.streamSessionConfig,
    required this.lslTransport,
  }) : _streamNode = streamNode,
       super(config);

  @override
  String get name => 'LSL Data Stream ${config.name}';

  @override
  String get description => 'High-precision data stream for ${config.name}';

  /// Send typed data based on stream configuration
  void sendData(List<dynamic> data) {
    if (!started) throw StateError('Stream not started');

    if (data.length != config.channels) {
      throw ArgumentError(
        'Data length ${data.length} does not match channels ${config.channels}',
      );
    }

    // Validate data types
    _validateDataType(data);

    // Send directly through outlet or isolate
    if (useIsolates && _outletIsolate != null) {
      _outletIsolate!.sendData(data);
    } else if (_outletResource != null) {
      _outletResource!.outlet.pushSample(data);
    }
  }

  @override
  void updateNode(Node newNode) {
    if (newNode.uId != streamNode.uId) {
      throw ArgumentError("newNode must have the same uId");
    }
    _streamNode = newNode;
  }

  void sendDataTyped<T>(List<T> data) {
    if (!started) throw StateError('Stream not started');

    if (data.length != config.channels) {
      throw ArgumentError(
        'Data length ${data.length} does not match channels ${config.channels}',
      );
    }

    // Validate data types
    _validateDataType(data);

    // Send directly through outlet or isolate
    if (useIsolates && _outletIsolate != null) {
      _outletIsolate!.sendData(data);
    } else if (_outletResource != null) {
      _outletResource!.outlet.pushSample(data);
    }
  }

  void _validateDataType(List<dynamic> data) {
    for (final value in data) {
      switch (config.dataType) {
        case StreamDataType.float32:
        case StreamDataType.double64:
          if (value is! num) {
            throw ArgumentError(
              'Expected numeric value, got ${value.runtimeType}',
            );
          }
          break;
        case StreamDataType.int8:
        case StreamDataType.int16:
        case StreamDataType.int32:
        case StreamDataType.int64:
          if (value is! int) {
            throw ArgumentError('Expected int value, got ${value.runtimeType}');
          }
          break;
        case StreamDataType.string:
          if (value is! String) {
            throw ArgumentError(
              'Expected String value, got ${value.runtimeType}',
            );
          }
          break;
      }
    }
  }

  @override
  IMessage? _createMessageFromIsolateData(IsolateDataMessage data) {
    // Emit typed data
    _typedDataController.add(data.data);

    // Create appropriate message based on data type
    switch (config.dataType) {
      case StreamDataType.float32:
      case StreamDataType.double64:
        if (data.data.every((v) => v is num)) {
          return MessageFactory.double64Message(
            data: data.data.map((v) => (v as num).toDouble()).toList(),
            channels: config.channels,
            timestamp: data.timestamp,
          );
        }
        break;
      case StreamDataType.int8:
      case StreamDataType.int16:
      case StreamDataType.int32:
      case StreamDataType.int64:
        if (data.data.every((v) => v is int)) {
          return MessageFactory.int32Message(
            data: data.data.cast<int>(),
            channels: config.channels,
            timestamp: data.timestamp,
          );
        }
        break;
      case StreamDataType.string:
        if (data.data.every((v) => v is String)) {
          return MessageFactory.stringMessage(
            data: data.data.cast<String>(),
            channels: config.channels,
            timestamp: data.timestamp,
          );
        }
        break;
    }
    return null;
  }

  @override
  IMessage? _createMessageFromSample(LSLSample sample) {
    // Emit raw data
    _typedDataController.add(sample.data);
    return _createMessageFromIsolateData(
      IsolateDataMessage(
        streamId: id,
        messageId: generateUid(),
        timestamp: DateTime.now(),
        data: sample.data,
        lslTimestamp: sample.timestamp,
      ),
    );
  }

  @override
  List<dynamic> _createSampleFromMessage(IMessage message) {
    return message.data;
  }

  @override
  Future<void> dispose() async {
    logger.info('Disposing typed data controller for stream ${config.name}');
    await _typedDataController.close().timeout(
      Duration(seconds: 2),
      onTimeout: () {
        logger.warning(
          'Timeout closing typed data controller for ${config.name}, did you forget to cancel the inbox/outbox subscriptions?',
        );
      },
    );
    logger.info('Disposing LSL data stream ${config.name}');
    await super.dispose();
  }
}

/// Factory for creating LSL-based network streams.
class LSLNetworkStreamFactory
    extends NetworkStreamFactory<LSLCoordinationSession> {
  @override
  Future<LSLDataStream> createDataStream(
    DataStreamConfig config,
    CoordinationSession session,
  ) async {
    if (session.transport is! LSLTransport) {
      throw ArgumentError(
        'Session transport must be LSLTransport, got ${session.transport.runtimeType}',
      );
    }
    return LSLDataStream(
      config: config,
      streamNode: session.thisNode,
      streamSessionConfig: session.config,
      lslTransport: session.transport as LSLTransport,
    );
  }

  @override
  Future<LSLCoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config,
    CoordinationSession session,
  ) async {
    if (session.transport is! LSLTransport) {
      throw ArgumentError(
        'Session transport must be LSLTransport, got ${session.transport.runtimeType}',
      );
    }
    return LSLCoordinationStream(
      config: config,
      streamNode: session.thisNode,
      streamSessionConfig: session.config,
      lslTransport: session.transport as LSLTransport,
    );
  }
}

/// LSL-based coordination stream with internal message polling
// ignore: missing_override_of_must_be_overridden
class LSLCoordinationStream
    extends CoordinationStream<CoordinationStreamConfig, StringMessage>
    with
        RuntimeTypeUID,
        LSLStreamMixin<CoordinationStreamConfig, StringMessage> {
  @override
  Node get streamNode => _streamNode;
  Node _streamNode;

  @override
  final CoordinationSessionConfig streamSessionConfig;
  @override
  final LSLTransport lslTransport;

  @override
  bool get useBusyWaitInlets => false; // Event-driven coordination inlets
  @override
  bool get useBusyWaitOutlets => false; // Event-driven coordination outlets

  LSLCoordinationStream({
    required CoordinationStreamConfig config,
    required Node streamNode,
    required this.streamSessionConfig,
    required this.lslTransport,
  }) : _streamNode = streamNode,
       super(config);

  @override
  String get description => 'Coordination stream for ${config.name}';

  @override
  StringMessage? _createMessageFromIsolateData(IsolateDataMessage data) {
    if (data.data.isNotEmpty && data.data[0] is String) {
      return MessageFactory.stringMessage(
        data: [data.data[0] as String],
        timestamp: data.timestamp,
        channels: 1,
      );
    }
    return null;
  }

  @override
  void updateNode(Node newNode) {
    if (streamNode.uId != newNode.uId) {
      throw ArgumentError("newNode must have the same uID");
    }
    _streamNode = newNode;
  }

  @override
  StringMessage? _createMessageFromSample(LSLSample sample) {
    if (sample.data.isNotEmpty) {
      return MessageFactory.stringMessage(
        data: [sample.data[0] as String],
        timestamp: DateTime.now(),
        channels: 1,
      );
    }
    return null;
  }

  @override
  List<dynamic> _createSampleFromMessage(StringMessage message) {
    return message.data;
  }
}
