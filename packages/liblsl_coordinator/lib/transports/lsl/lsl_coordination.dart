import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:meta/meta.dart';

/// LSL Resource implementation using [InstanceUID] mixin to provide a unique ID
/// for each instance of the class.
class LSLResource with InstanceUID implements IResource {
  @override
  final String id;

  @override
  String get name => 'lsl-resource-$id';

  @override
  String? get description => 'A LSL Resource with id $id';

  @override
  IResourceManager? get manager => _manager;
  IResourceManager? _manager;

  @override
  bool get created => _created;
  @override
  bool get disposed => _disposed;

  bool _created = false;
  bool _disposed = false;

  /// Creates a new LSL resource with the given ID and optional manager.
  LSLResource({required this.id, IResourceManager? manager})
    : _manager = manager;

  @override
  @mustCallSuper
  @mustBeOverridden
  FutureOr<void> create() {
    if (_disposed) {
      throw StateError('Resource has been disposed');
    }
    if (_created) {
      throw StateError('Resource has already been created');
    }
    _created = true;
  }

  @override
  @mustCallSuper
  @mustBeOverridden
  FutureOr<void> dispose() {
    if (_disposed) {
      throw StateError('Resource has already been disposed');
    }

    _disposed = true;
    _created = false;
  }

  @override
  FutureOr<void> updateManager(IResourceManager? newManager) async {
    if (_disposed) {
      throw StateError('Resource has been disposed');
    }
    if (_manager == newManager) {
      logger.finest(
        'Resource manager is already set to ${newManager?.name} (${newManager?.uId})',
      );
      return;
    }
    if (_manager != null) {
      throw StateError(
        'Resource is already managed by ${_manager!.name} (${_manager!.uId}) '
        'please release it before assigning a new manager',
      );
    }
    _manager = newManager;
  }
}

/// Coordination session implementation using LSL transport.
/// This uses the [RuntimeTypeUID] mixin to provide a unique ID
/// based on the runtime type of the class ([LSLCoordinationSession]).
/// This is because there shouldn't be multiple [LSLCoordinationSession]
/// instances. Other transports may allow multiple instances, and should instead
/// use the [InstanceUID] mixin.
class LSLCoordinationSession extends CoordinationSession with RuntimeTypeUID {
  @override
  String get id => 'lsl-coordination-session';
  @override
  String get name => 'LSL Coordination Session';
  @override
  String get description =>
      'A coordination session using LSL transport for communication';

  /// Managed resources
  /// @TODO: properly implement
  final Map<String, IResource> _resources = {};

  /// Creates a new LSL coordination session with the given configuration.
  /// If no configuration is provided, anthe default configuration is used.
  LSLCoordinationSession(super.config)
    : _transport =
          (config.transportConfig is LSLTransportConfig)
              ? LSLTransport(
                config: config.transportConfig as LSLTransportConfig,
              )
              : LSLTransport(),
      super();

  /// The LSL transport used for communication.
  final LSLTransport _transport;

  @override
  LSLTransport get transport => _transport;

  Map<String, StreamSubscription> _dataDiscoverySubscriptions = {};
  Map<String, Timer> _dataDiscoveryTimers = {};

  @override
  Future<void> manageResource<R extends IResource>(R resource) async {
    resource.updateManager(this);
    _resources[resource.uId] = resource;
  }

  @override
  Future<R> releaseResource<R extends IResource>(String resourceUID) async {
    // for now, remove from the map, but we should proxy
    final resource = _resources.remove(resourceUID);
    if (resource == null) {
      throw StateError('Resource with UID $resourceUID not found');
    }
    return resource as R;
  }

  @override
  String toString() {
    return 'LSLCoordinationSession(name: ${config.name}, maxNodes: ${config.maxNodes}, minNodes: ${config.minNodes})';
  }

  @override
  Future<void> create() async {
    logger.info('Creating LSL coordination session ${config.name}');
    super.create();
    await _transport.createStream(
      coordinationConfig.streamConfig,
      coordinationSession: this,
    );
  }

  @override
  Future<void> dispose() async {
    if (joined) {
      logger.warning(
        'Session is still joined, automatically leaving before disposing',
      );
      await leave();
    }
    logger.info('Disposing LSL coordination session ${config.name}');
    final List<Future> releaseFutures = [];
    for (var resource in _resources.values.toList()) {
      final r = await resource.manager?.releaseResource(resource.uId);
      if (r != null) {
        if (r is LslDiscovery) {
          r.stopDiscovery();
        }
        final d = r.dispose();
        if (d is Future) {
          releaseFutures.add(d);
        }
      }
    }
    await Future.wait(releaseFutures);
    _resources.clear();
    super.dispose();
    logger.info('Disposed LSL coordination session ${config.name}');
  }

  // Coordination state
  bool _isCoordinator = false;
  final List<Node> _connectedNodes = [];
  String? _coordinatorId;
  Timer? _coordinatorHeartbeatTimer;
  Timer? _heartbeatTimer;

  // LSL resources for coordination
  LSLOutlet? _coordinationOutlet;
  LSLInlet? _coordinationInlet;
  LslDiscovery? _discovery;
  Timer? _discoveryTimer;
  Timer? _coordinationPollTimer;

  // Stream controllers for events
  final StreamController<CoordinationEvent> _coordinationEventsController =
      StreamController<CoordinationEvent>.broadcast();
  final StreamController<UserEvent> _userEventsController =
      StreamController<UserEvent>.broadcast();

  Stream<CoordinationEvent> get coordinationEvents =>
      _coordinationEventsController.stream;
  Stream<UserEvent> get userEvents => _userEventsController.stream;

  bool get isCoordinator => _isCoordinator;
  List<Node> get connectedNodes => List.unmodifiable(_connectedNodes);
  String? get coordinatorId => _coordinatorId;

  /// Initialize with enhanced multi-app discovery
  @override
  Future<void> initialize() async {
    logger.info('Initializing LSL coordination session ${config.name}');
    // Set up transport
    await _transport.initialize();
    await _transport.create();
    await super.initialize();

    // Add unique session identifier to node metadata
    thisNode.setMetadata('sessionId', config.name);
    thisNode.setMetadata('appId', coordinationConfig.name);
    thisNode.setMetadata('randomRoll', Random().nextDouble().toString());
    thisNode.setMetadata('nodeStartedAt', DateTime.now().toIso8601String());

    // Create enhanced discovery with session-specific predicates
    await _setupDiscovery();
    logger.info('Initialized LSL coordination session ${config.name}');
  }

  /// Set up enhanced discovery for multi-app coordination
  Future<void> _setupDiscovery() async {
    logger.info('Setting up discovery for session ${config.name}');
    // Create discovery service with session-specific filtering
    final discovery = LslDiscovery(
      streamConfig: coordinationConfig.streamConfig,
      coordinationConfig: coordinationConfig,
      id: 'enhanced-discovery-${thisNode.id}',
    );

    await discovery.create();
    await manageResource(discovery);

    // Store discovery for later use
    _discovery = discovery;
    logger.info('Discovery set up for session ${config.name}');
  }

  Timer? _coordinatorCheckTimer;
  bool _coordinationEstablished = false;

  /// join with robust coordinator election
  @override
  Future<void> join() async {
    logger.info('Joining LSL coordination session ${config.name}');
    await super.join();

    // Start coordinator election process
    await _startCoordinatorElection();

    // Start periodic coordinator health check
    _startCoordinatorHealthCheck();
    logger.info('Joined LSL coordination session ${config.name}');
  }

  Future<void> _startCoordinatorElection() async {
    logger.info('Starting coordinator election for session ${config.name}');
    if (_discovery == null) return;

    // Build predicate for finding coordinators in the same session
    // Use clean stream name and metadata filtering
    final sessionPredicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: 'coordination', // Clean stream name prefix
      sessionName: config.name,         // Filter by session in metadata
      nodeRole: 'coordinator',          // Filter by role in metadata
    );

    // Listen for discovery events
    final completer = Completer<void>();
    StreamSubscription<DiscoveryEvent>? subscription;

    subscription = _discovery!.events.listen((event) {
      if (event is StreamDiscoveredEvent) {
        _handleStreamDiscovery(event, completer);
      } else if (event is DiscoveryTimeoutEvent) {
        _handleDiscoveryTimeout(event, completer);
      }
    });

    // Start discovery with reasonable timeout
    _discovery!.startDiscovery(
      predicate: sessionPredicate,
      timeout: Duration(seconds: 3), // Quick initial check
    );

    // Wait for coordination to be established
    await completer.future;
    subscription.cancel();

    _coordinationEstablished = true;

    // Emit coordination established event
    _coordinationEventsController.add(
      CoordinationEvent(
        id: 'coordination_established',
        description: 'Multi-app coordination established',
        metadata: {
          'isCoordinator': _isCoordinator.toString(),
          'sessionId': config.name,
          'appId': coordinationConfig.name,
        },
      ),
    );
    logger.info('Coordinator election completed for session ${config.name}');
  }

  void _handleStreamDiscovery(
    StreamDiscoveredEvent event,
    Completer<void> completer,
  ) {
    if (event.streams.isEmpty) return;

    // Found existing coordinator(s)
    final coordinatorStreams =
        event.streams
            .where((s) => s.streamInfo.sourceId.contains('Coordinator'))
            .toList();

    if (coordinatorStreams.isNotEmpty) {
      // Join the first valid coordinator
      final coordinator = coordinatorStreams.first;

      // Verify it's for our session
      _joinAsNode(coordinator.streamInfo).then((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
    }
  }

  void _handleDiscoveryTimeout(
    DiscoveryTimeoutEvent event,
    Completer<void> completer,
  ) async {
    // No coordinator found - check if we should become one
    final shouldBecome = await _shouldBecomeCoordinator();

    if (shouldBecome) {
      await _becomeCoordinator();
      if (!completer.isCompleted) {
        completer.complete();
      }
    } else {
      // Keep waiting for a coordinator
      _discovery!.startDiscovery(
        predicate: event.predicate,
        timeout: Duration(seconds: 10), // Longer wait
      );
    }
  }

  /// coordinator eligibility check
  Future<bool> _shouldBecomeCoordinator() async {
    // Check for other potential coordinators in the session
    // Use clean stream name and session metadata filtering
    final predicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: 'coordination', // Clean stream name
      sessionName: config.name,         // Filter by session in metadata
    );

    final streams = await LslDiscovery.discoverOnceByPredicate(predicate);

    // Filter for nodes that could become coordinator
    final candidates =
        streams.where((s) {
          // Parse metadata if available
          try {
            return s.sourceId != thisNode.id;
          } catch (_) {
            return false;
          }
        }).toList();

    // Clean up stream infos
    for (final stream in streams) {
      stream.destroy();
    }

    if (candidates.isEmpty) {
      // No other candidates - we should become coordinator
      return true;
    }

    // Use promotion strategy to determine if we should become coordinator
    final topologyConfig =
        coordinationConfig.topologyConfig as HierarchicalTopologyConfig;
    final strategy = topologyConfig.promotionStrategy;

    if (strategy is PromotionStrategyRandom) {
      // Check our random roll against others
      final myRoll = double.parse(thisNode.getMetadata('randomRoll') ?? '1.0');
      // In a real implementation, we'd parse the rolls from candidate metadata
      // For now, use a simple heuristic
      return myRoll < 0.3; // 30% chance
    } else if (strategy is PromotionStrategyFirst) {
      // Check start times
      final myStart = thisNode.getMetadata('nodeStartedAt') ?? '';
      // Would need to parse from candidates
      return true; // Simplified - be coordinator if no clear earlier node
    }

    return true; // Default to becoming coordinator
  }

  Future<void> _becomeCoordinator() async {
    logger.info('Becoming coordinator for session ${config.name}');
    _isCoordinator = true;
    _coordinatorId = thisNode.id;
    updateThisNode(thisNode.asCoordinator);

    // Create enhanced coordination outlet
    final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
      config: coordinationConfig.streamConfig,
      sessionConfig: config,
      node: thisNode,
    );

    _coordinationOutlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      useIsolates: false, // Coordination doesn't need isolates
    );

    // Start coordinator services
    _startCoordinatorServices();

    logger.info('Became coordinator for session ${config.name}');
  }

  Future<void> _joinAsNode(LSLStreamInfo coordinatorStream) async {
    logger.info('Joining as node to coordinator for session ${config.name}');
    _isCoordinator = false;
    updateThisNode(thisNode.asParticipant);

    // Create inlet to coordinator with metadata support
    _coordinationInlet = await LSL.createInlet<String>(
      streamInfo: coordinatorStream,
      includeMetadata: true,
      useIsolates: false, // Coordination doesn't need isolates
    );

    // Create our outlet for responses
    final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
      config: coordinationConfig.streamConfig,
      sessionConfig: config,
      node: thisNode,
    );

    _coordinationOutlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      useIsolates: false,
    );

    // Start listening to coordinator
    _startNodeServices();

    logger.info('Joined coordinator for session ${config.name}');
  }

  void _startCoordinatorServices() {
    logger.info('Starting coordinator services for session ${config.name}');
    // Start heartbeat broadcasting
    _startHeartbeat();

    // Start node discovery
    _startDiscovery();
    logger.info('Started coordinator services for session ${config.name}');
  }

  void _startDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(config.discoveryInterval, (_) {
      _discoverNodes();
    });
  }

  void _startNodeServices() {
    logger.info('Starting node services for session ${config.name}');
    // Start heartbeat to coordinator
    _startHeartbeat();

    // Listen to coordinator messages
    _coordinationPollTimer?.cancel();
    _coordinationPollTimer = Timer.periodic(
      Duration(
        milliseconds:
            (1 / _transport.config.coordinationFrequency * 1000).round(),
      ),
      (_) async {
        if (_coordinationInlet == null) return;

        try {
          final sample = await _coordinationInlet!.pullSample(timeout: 0.0);
          if (sample.isNotEmpty) {
            _handleCoordinationMessage(sample.data[0] as String);
          }
        } catch (e) {
          logger.warning('Error receiving coordination message: $e');
        }
      },
    );
    logger.info('Started node services for session ${config.name}');
  }

  void _broadcastCoordinatorHeartbeat() {
    if (_coordinationOutlet == null) return;

    final heartbeat = {
      'type': 'coordinator_heartbeat',
      'coordinatorId': thisNode.id,
      'sessionId': config.name,
      'timestamp': DateTime.now().toIso8601String(),
      'connectedNodes': _connectedNodes.length,
    };

    _coordinationOutlet!.pushSample([jsonEncode(heartbeat)]);
  }

  void _sendNodeHeartbeat() {
    if (_coordinationOutlet == null) return;

    final heartbeat = {
      'type': 'node_heartbeat',
      'nodeId': thisNode.id,
      'sessionId': config.name,
      'timestamp': DateTime.now().toIso8601String(),
      'capabilities': thisNode.capabilities.map((c) => c.toString()).toList(),
    };

    _coordinationOutlet!.pushSample([jsonEncode(heartbeat)]);
  }

  void _discoverNodes() async {
    if (_discovery == null) return;

    // Discover participant nodes in our session using metadata filtering
    final predicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: 'coordination', // Clean stream name
      sessionName: config.name,         // Filter by session in metadata
      nodeRole: 'participant',          // Filter by role in metadata
    );

    _discovery!.startDiscovery(
      predicate: predicate,
      timeout: Duration(seconds: 1),
    );
  }

  void _handleCoordinationMessage(String messageJson) {
    try {
      final message = jsonDecode(messageJson) as Map<String, dynamic>;
      final type = message['type'] as String?;

      switch (type) {
        case 'coordinator_heartbeat':
          _updateCoordinatorStatus(message);
          break;
        case 'node_heartbeat':
          _updateNodeStatus(message);
          break;
        case 'user_event':
          _handleUserEventMessage(message);
          break;
        case 'config_update':
          _handleConfigUpdate(message);
          break;
        default:
          // Handle other message types
          break;
      }
    } catch (e) {
      logger.warning('Error parsing coordination message: $e');
    }
  }

  void _updateCoordinatorStatus(Map<String, dynamic> message) {
    _coordinatorId = message['coordinatorId'] as String?;
    // Reset coordinator check timer
    _coordinatorCheckTimer?.cancel();
    _coordinatorCheckTimer = Timer(
      config.nodeTimeout,
      _handleCoordinatorTimeout,
    );
  }

  void _handleUserEventMessage(Map<String, dynamic> messageData) {
    final userEvent = UserEvent(
      id: messageData['event_id'] as String? ?? 'unknown',
      description: messageData['description'] as String? ?? '',
      metadata: Map<String, dynamic>.from(messageData['metadata'] ?? {}),
    );

    _userEventsController.add(userEvent);
  }

  void _updateNodeStatus(Map<String, dynamic> message) {
    if (!_isCoordinator) return;

    final nodeId = message['nodeId'] as String?;
    if (nodeId == null) return;

    // Update or add node to connected list
    final existingNode = _connectedNodes.firstWhere(
      (n) => n.id == nodeId,
      orElse: () => Node(NodeConfig(name: 'Unknown', id: nodeId)),
    );

    existingNode.setMetadata('lastHeartbeat', DateTime.now().toIso8601String());

    if (!_connectedNodes.contains(existingNode)) {
      _connectedNodes.add(existingNode);

      _coordinationEventsController.add(
        CoordinationEvent(
          id: 'node_joined',
          description: 'Node $nodeId joined session',
          metadata: {'nodeId': nodeId},
        ),
      );
    }
  }

  void _handleCoordinatorTimeout() {
    logger.warning('Coordinator timeout - starting new election');
    _coordinationEstablished = false;
    _startCoordinatorElection();
  }

  void _handleConfigUpdate(Map<String, dynamic> message) {
    // Handle experiment configuration updates
    final configData = message['config'] as Map<String, dynamic>?;
    if (configData != null) {
      _coordinationEventsController.add(
        CoordinationEvent(
          id: 'config_updated',
          description: 'Experiment configuration updated',
          metadata: configData,
        ),
      );
    }
  }

  void _startCoordinatorHealthCheck() {
    Timer.periodic(config.nodeTimeout, (_) {
      if (!_isCoordinator && _coordinatorCheckTimer == null) {
        // No heartbeat received - coordinator might be down
        _handleCoordinatorTimeout();
      }
    });
  }

  /// Create enhanced data stream with isolate support
  Future<LSLDataStream> createDataStream(DataStreamConfig config) async {
    if (!created || !initialized) {
      throw StateError('Session must be initialized before creating streams');
    }
    logger.info(
      'Creating data stream ${config.name} in session ${this.config.name}',
    );

    final factory = LSLNetworkStreamFactory();
    final dataStream = await factory.createDataStream(config, this);

    await dataStream.create();
    await manageResource(dataStream);

    // Set up hierarchical data routing if coordinator
    if (_isCoordinator) {
      await _setupDataRouting(dataStream);
    }

    // Announce stream creation
    await sendUserEvent(
      UserEvent(
        id: 'data_stream_created',
        description: 'data stream ${config.name} created',
        metadata: {
          'streamName': config.name,
          'streamId': config.id,
          'channels': config.channels.toString(),
          'sampleRate': config.sampleRate.toString(),
          'dataType': config.dataType.toString(),
          'nodeId': thisNode.id,
          'useIsolates': 'true',
          'useBusyWait': 'true',
        },
      ),
    );
    logger.info(
      'Created data stream ${config.name} in session ${this.config.name}',
    );
    return dataStream;
  }

  /// Determines if this node should receive data based on stream participation mode
  bool _shouldReceiveData(DataStreamConfig config) {
    switch (config.participationMode) {
      case StreamParticipationMode.coordinatorOnly:
        return _isCoordinator;
      case StreamParticipationMode.allNodes:
        return true; // Everyone receives data
      case StreamParticipationMode.sendAll_receiveCoordinator:
        return _isCoordinator;
      case StreamParticipationMode.custom:
        // TODO: Implement custom logic based on node configuration
        return _isCoordinator;
    }
  }

  /// Determines if this node should exclude its own streams from discovery
  bool _shouldExcludeOwnStreams(DataStreamConfig config) {
    switch (config.participationMode) {
      case StreamParticipationMode.coordinatorOnly:
        // Only coordinator receives - if I'm coordinator, exclude own streams
        // to avoid self-connection issues, but receive from others
        return _isCoordinator;
      case StreamParticipationMode.allNodes:
        // Fully connected - everyone should receive from everyone INCLUDING themselves
        return false;
      case StreamParticipationMode.sendAll_receiveCoordinator:
        // Default hierarchical - only coordinator receives, including own streams
        return !_isCoordinator;
      case StreamParticipationMode.custom:
        // TODO: Implement custom logic based on node configuration
        return _isCoordinator;
    }
  }

  Future<void> _setupDataRouting(LSLDataStream dataStream) async {
    // Check if this node should receive data based on participation mode
    bool shouldReceiveData = _shouldReceiveData(dataStream.config);
    if (!shouldReceiveData) return;

    // Create discovery for data streams from all nodes
    final dataDiscovery = LslDiscovery(
      streamConfig: dataStream.config,
      coordinationConfig: coordinationConfig,
      id: 'data-discovery-${dataStream.id}',
    );

    await dataDiscovery.create();
    await manageResource(dataDiscovery);

    // Listen for data stream discoveries
    final discoverySub = dataDiscovery.events.listen((event) async {
      if (disposed || !joined) return;
      if (event is StreamDiscoveredEvent) {
        // Deduplicate by source ID since each outlet now has a unique source ID
        final Map<String, StreamInfoResource> uniqueStreams = {};
        final List<StreamInfoResource> duplicatesToDispose = [];
        
        logger.finest('Discovery ${dataDiscovery.id}: Processing ${event.streams.length} streams for ${dataStream.config.name}');
        for (final stream in event.streams) {
          final sourceId = stream.streamInfo.sourceId;
          logger.finest('Discovery ${dataDiscovery.id}: Stream ${stream.streamInfo.streamName} sourceId=$sourceId (resource: ${stream.uId})');
          
          if (uniqueStreams.containsKey(sourceId)) {
            logger.fine('Discovery: Duplicate stream detected for sourceId $sourceId, marking resource ${stream.uId} for disposal');
            // Don't dispose immediately - collect them for later disposal
            duplicatesToDispose.add(stream);
          } else {
            uniqueStreams[sourceId] = stream;
          }
        }
        
        // Dispose duplicates after we've processed all unique streams
        for (final duplicate in duplicatesToDispose) {
          await duplicate.dispose();
        }
        
        logger.info('Discovery for ${dataStream.config.name}: found ${event.streams.length} streams (${uniqueStreams.length} unique by source ID)');
        for (final streamResource in uniqueStreams.values) {
          if (disposed || !joined) return;
          
          // Check if we already have an inlet for this source
          final sourceId = streamResource.streamInfo.sourceId;
          final streamName = streamResource.streamInfo.streamName;
          final alreadyConnected = dataStream.hasInletForSource(sourceId);
          
          if (alreadyConnected) {
            logger.finest('Skipping already connected stream: $streamName from $sourceId');
            continue;
          }
          
          try {
            logger.fine('Processing new stream: $streamName from $sourceId (resource: ${streamResource.uId})');
            
            // Instead of transferring resource, just extract the StreamInfo
            // The discovery will manage its own resource lifecycle
            final streamInfo = streamResource.streamInfo;
            
            // Add inlet directly using the StreamInfo
            // When using isolates, the main thread doesn't need to manage the resource
            await dataStream.addInlet(streamInfo);

            logger.info(
              'Added data inlet from $sourceId for stream $streamName',
            );
          } catch (e) {
            logger.warning('Failed to add data inlet for $streamName: $e');
          }
        }
      }
    });

    _dataDiscoverySubscriptions[dataStream.uId] = discoverySub;

    // Start discovery - conditionally exclude own streams based on participation mode
    final shouldExcludeOwnStreams = _shouldExcludeOwnStreams(dataStream.config);
    
    // Generate our own source ID pattern to exclude if needed
    String? excludeSourceIdPrefix;
    if (shouldExcludeOwnStreams) {
      // Exclude streams with our source ID pattern: nodeId_streamName_*
      excludeSourceIdPrefix = '${thisNode.id}_${dataStream.config.name}_';
    }
    
    final predicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: dataStream.config.name, // Clean stream name
      sessionName: config.name,                  // Filter by session in metadata
      excludeSourceIdPrefix: excludeSourceIdPrefix, // Exclude our own streams by source ID pattern
    );

    dataDiscovery.startDiscovery(predicate: predicate);
  }

  /// Send experiment configuration to all nodes
  Future<void> broadcastExperimentConfig(Map<String, dynamic> config) async {
    if (_coordinationOutlet == null) return;

    final message = {
      'type': 'config_update',
      'config': config,
      'timestamp': DateTime.now().toIso8601String(),
      'fromNode': thisNode.id,
    };

    _coordinationOutlet!.pushSample([jsonEncode(message)]);

    logger.info('Broadcast experiment configuration');
  }

  Future<void> sendUserEvent(UserEvent event) async {
    if (_coordinationOutlet != null) {
      final eventMessage = {
        'type': 'user_event',
        'event_id': event.id,
        'description': event.description,
        'metadata': event.metadata,
        'timestamp': event.timestamp.toIso8601String(),
        'from_node_id': thisNode.id,
      };

      _coordinationOutlet!.pushSample([jsonEncode(eventMessage)]);
    }

    // Also emit locally
    _userEventsController.add(event);
  }

  @override
  Future<void> leave() async {
    await super.leave();
    logger.info('Leaving coordination session ${config.name}');

    // Send goodbye message
    if (_coordinationOutlet != null) {
      final goodbyeMessage = {
        'type': 'node_leaving',
        'node_id': thisNode.id,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _coordinationOutlet!.pushSample([jsonEncode(goodbyeMessage)]);
    }

    // Stop heartbeat
    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _coordinatorHeartbeatTimer?.cancel();
    _coordinatorCheckTimer?.cancel();
    _coordinationPollTimer?.cancel();

    // Stop all data discovery subscriptions and timers
    _dataDiscoverySubscriptions.forEach((_, sub) => sub.cancel());
    _dataDiscoverySubscriptions.clear();
    _dataDiscoveryTimers.forEach((_, timer) => timer.cancel());
    _dataDiscoveryTimers.clear();

    // Clean up LSL resources
    _coordinationOutlet?.destroy();
    _coordinationInlet?.destroy();
    _discovery?.dispose();

    // Stop all discovery resources explicitly
    final discoveries = _resources.values.whereType<LslDiscovery>().toList();
    for (final discovery in discoveries) {
      discovery.stopDiscovery();
    }

    // Stop all stream isolates explicitly
    final streams =
        _resources.values
            .where((r) => r is LSLDataStream || r is LSLCoordinationStream)
            .toList();
    for (final stream in streams) {
      if (stream is LSLStreamMixin) {
        await stream.stop();
      }
    }

    _coordinationEventsController.add(
      CoordinationEvent(
        id: 'left_session',
        description: 'Left coordination session',
      ),
    );
    logger.info('Left coordination session ${config.name}');
  }

  void _startHeartbeat() {
    if (_isCoordinator) {
      _heartbeatTimer?.cancel();
      _coordinatorHeartbeatTimer?.cancel();
      _coordinatorHeartbeatTimer = Timer.periodic(config.heartbeatInterval, (
        _,
      ) {
        _broadcastCoordinatorHeartbeat();
      });
    } else {
      _heartbeatTimer?.cancel();
      _coordinatorHeartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (_) {
        _sendNodeHeartbeat();
      });
    }
  }

  @override
  Future<void> pause() async {
    logger.info('Pausing LSL coordination session ${config.name}');
    await super.pause();
    // _heartbeatTimer?.cancel();
    // _coordinatorHeartbeatTimer?.cancel();
    _discoveryTimer?.cancel();
    _discovery?.pause();
    logger.info('Paused LSL coordination session ${config.name}');
  }

  @override
  Future<void> resume() async {
    logger.info('Resuming LSL coordination session ${config.name}');
    await super.resume();
    // _startHeartbeat();
    _startDiscovery();
    _discovery?.resume();
    logger.info('Resumed LSL coordination session ${config.name}');
  }
}
