import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:liblsl_coordinator/src/events.dart';
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
    if (!_created) {
      throw StateError('Resource has not been created');
    }
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
    super.create();
    await _transport.createStream(
      coordinationConfig.streamConfig,
      coordinationSession: this,
    );
  }

  @override
  Future<void> dispose() async {
    final List<Future> releaseFutures = [];
    for (var resource in _resources.values) {
      final r = await resource.manager?.releaseResource(resource.uId);
      if (r != null) {
        final d = r.dispose();
        if (d is Future) {
          releaseFutures.add(d);
        }
      }
    }
    await Future.wait(releaseFutures);
    _resources.clear();
    super.dispose();
    throw UnimplementedError();
  }

  // Coordination state
  bool _isCoordinator = false;
  final List<Node> _connectedNodes = [];
  String? _coordinatorId;
  Timer? _heartbeatTimer;

  // LSL resources for coordination
  LSLOutlet? _coordinationOutlet;
  LSLInlet? _coordinationInlet;
  LslDiscovery? _discovery;

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

  @override
  Future<void> initialize() async {
    // Initialize and create transport BEFORE calling super.initialize()
    // because super.initialize() calls create() which needs the transport
    await _transport.initialize();
    await _transport.create();

    await super.initialize();

    // Set metadata for promotion strategy
    thisNode.setMetadata('randomRoll', Random().nextDouble().toString());
    thisNode.setMetadata('nodeStartedAt', DateTime.now().toIso8601String());

    // Create discovery service for coordination streams
    _discovery = LslDiscovery(
      streamConfig: coordinationConfig.streamConfig,
      coordinationConfig: coordinationConfig,
      id: 'coordination-discovery-${thisNode.id}',
    );
    await _discovery!.create();
    await manageResource(_discovery!);
  }

  @override
  Future<void> join() async {
    await super.join();

    // Start event-driven coordinator discovery
    _startCoordinatorDiscovery();
  }

  /// Starts event-driven coordinator discovery
  void _startCoordinatorDiscovery() {
    if (_discovery == null) return;

    // Listen to discovery events
    _discovery!.events.listen((event) {
      if (event is StreamDiscoveredEvent) {
        _handleStreamsDiscovered(event);
      } else if (event is DiscoveryTimeoutEvent) {
        _handleDiscoveryTimeout(event);
      }
    });

    // Start discovering coordinator streams
    final coordinatorPredicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: 'coordination',
      sessionName: config.name,
      nodeRole: 'coordinator',
    );

    _discovery!.startDiscovery(
      predicate: coordinatorPredicate,
      timeout: Duration(seconds: 5), // 5 second timeout to find coordinator
    );
  }

  /// Handles discovered streams (coordinator found)
  Future<void> _handleStreamsDiscovered(StreamDiscoveredEvent event) async {
    final coordinatorStreams = event.streams;

    if (coordinatorStreams.isNotEmpty) {
      // For simplicity, join the first discovered coordinator
      final resource = coordinatorStreams.first;
      // Take ownership of the resource
      _discovery!.releaseResource(resource.uId);
      await manageResource<StreamInfoResource>(resource);

      await _joinAsNode(resource.streamInfo);

      _finishJoining();
    }
  }

  /// Handles discovery timeout (no coordinator found)
  Future<void> _handleDiscoveryTimeout(DiscoveryTimeoutEvent event) async {
    // No coordinator found, check if we should become coordinator
    final shouldBecomeCoordinator = await _shouldBecomeCoordinator();

    if (shouldBecomeCoordinator) {
      await _becomeCoordinator();
      _finishJoining();
    } else {
      // Start waiting for a coordinator to appear
      _waitForCoordinatorToAppear();
    }
  }

  /// Wait for another node to become coordinator
  void _waitForCoordinatorToAppear() {
    final waitPredicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: 'coordination',
      sessionName: config.name,
      nodeRole: 'coordinator',
    );

    _discovery!.startDiscovery(
      predicate: waitPredicate,
      timeout: Duration(seconds: 30), // Longer timeout for waiting
    );
  }

  /// Finishes the joining process
  void _finishJoining() {
    _startHeartbeat();

    _coordinationEventsController.add(
      CoordinationEvent(
        id: 'joined_session',
        description: 'Successfully joined coordination session',
        metadata: {'isCoordinator': _isCoordinator.toString()},
      ),
    );
  }

  /// Determines if this node should become coordinator based on promotion strategy
  Future<bool> _shouldBecomeCoordinator() async {
    if (_discovery == null) return true;

    final myRandomRoll = double.parse(
      thisNode.getMetadata('randomRoll') ?? '1.0',
    );
    final myStartedAt =
        thisNode.getMetadata('nodeStartedAt') ??
        DateTime.now().toIso8601String();

    // @TODO: Support other topology types
    final topologyConfig =
        coordinationConfig.topologyConfig as HierarchicalTopologyConfig;
    // Use promotion strategy to determine coordinator
    final strategy = topologyConfig.promotionStrategy;

    if (strategy is PromotionStrategyRandom) {
      // Find nodes with better random roll using predicate
      final predicate = LSLStreamInfoHelper.generatePredicate(
        streamNamePrefix: 'coordination',
        sessionName: config.name,
        randomRollLessThan: myRandomRoll,
      );

      final betterNodes = await LslDiscovery.discoverOnceByPredicate(predicate);

      // Clean up unused stream infos
      for (final stream in betterNodes) {
        stream.destroy();
      }

      return betterNodes.isEmpty;
    } else if (strategy is PromotionStrategyFirst) {
      // Find nodes that started earlier using predicate
      final predicate = LSLStreamInfoHelper.generatePredicate(
        streamNamePrefix: 'coordination',
        sessionName: config.name,
        nodeStartedBefore: myStartedAt,
      );

      final earlierNodes = await LslDiscovery.discoverOnceByPredicate(
        predicate,
      );

      // Clean up unused stream infos
      for (final stream in earlierNodes) {
        stream.destroy();
      }

      return earlierNodes.isEmpty;
    }

    // Default: become coordinator if no strategy specified
    return true;
  }

  Future<void> _becomeCoordinator() async {
    _isCoordinator = true;
    _coordinatorId = thisNode.id;

    // Create coordination outlet using LSLStreamInfoHelper
    final nodeWithRole = Node(
      thisNode.config.copyWith(
        metadata: {...thisNode.config.metadata, 'role': 'coordinator'},
      ),
    );

    final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
      config: coordinationConfig.streamConfig,
      sessionConfig: config,
      node: nodeWithRole,
    );

    _coordinationOutlet = await LSL.createOutlet(streamInfo: streamInfo);

    _coordinationEventsController.add(
      CoordinationEvent(
        id: 'promoted_to_coordinator',
        description: 'Node promoted to coordinator',
      ),
    );
  }

  Future<void> _joinAsNode(LSLStreamInfo coordinatorStream) async {
    // Create inlet to receive from coordinator (with metadata)
    _coordinationInlet = await LSL.createInlet(
      streamInfo: coordinatorStream,
      includeMetadata: true,
    );

    // Create our own outlet for sending to coordinator
    updateThisNode(thisNode.asParticipant);

    final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
      config: coordinationConfig.streamConfig,
      sessionConfig: config,
      node: thisNode,
    );

    _coordinationOutlet = await LSL.createOutlet(streamInfo: streamInfo);

    // Start listening to coordinator messages
    _startListeningToCoordinator();
  }

  void _startListeningToCoordinator() {
    if (_coordinationInlet == null) return;

    Timer.periodic(Duration(milliseconds: 50), (timer) async {
      if (_coordinationInlet == null) {
        timer.cancel();
        return;
      }

      try {
        final sample = await _coordinationInlet!.pullSample(timeout: 0.0);
        if (sample.isNotEmpty) {
          final messageJson = sample.data[0] as String;
          final messageData = jsonDecode(messageJson) as Map<String, dynamic>;
          _handleCoordinationMessage(messageData);
        }
      } catch (e) {
        // Handle parsing errors gracefully
      }
    });
  }

  void _handleCoordinationMessage(Map<String, dynamic> messageData) {
    final messageType = messageData['type'] as String?;

    switch (messageType) {
      case 'user_event':
        _handleUserEventMessage(messageData);
        break;
      case 'heartbeat':
        _handleHeartbeat(messageData);
        break;
      default:
        break;
    }
  }

  void _handleUserEventMessage(Map<String, dynamic> messageData) {
    final userEvent = UserEvent(
      id: messageData['event_id'] as String? ?? 'unknown',
      description: messageData['description'] as String? ?? '',
      metadata: Map<String, dynamic>.from(messageData['metadata'] ?? {}),
    );

    _userEventsController.add(userEvent);
  }

  void _handleHeartbeat(Map<String, dynamic> messageData) {
    // Update last seen time for the node that sent the heartbeat
    final nodeId = messageData['node_id'] as String?;
    if (nodeId != null && nodeId != thisNode.id) {
      // Update node metadata with last heartbeat time
      final existingNode = _connectedNodes.firstWhere(
        (n) => n.id == nodeId,
        orElse: () => NullNode(),
      );

      if (existingNode is! NullNode) {
        existingNode.setMetadata(
          'lastHeartbeat',
          DateTime.now().toIso8601String(),
        );
      } else {
        // Add new node
        final newNode = Node(NodeConfig(id: nodeId, name: 'Node $nodeId'));
        newNode.setMetadata('lastHeartbeat', DateTime.now().toIso8601String());
        _connectedNodes.add(newNode);
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (timer) {
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    if (_coordinationOutlet != null) {
      final heartbeatMessage = {
        'type': 'heartbeat',
        'node_id': thisNode.id,
        'timestamp': DateTime.now().toIso8601String(),
        'is_coordinator': _isCoordinator.toString(),
      };

      _coordinationOutlet!.pushSample([jsonEncode(heartbeatMessage)]);
    }
  }

  /// Creates a data stream for sending/receiving experiment data
  Future<LSLDataStream> createDataStream(DataStreamConfig config) async {
    if (!created || !initialized) {
      throw StateError(
        'Session must be initialized before creating data streams',
      );
    }

    final dataStream = await LSLNetworkStreamFactory().createDataStream(
      config,
      this,
    );

    await dataStream.create();
    await manageResource(dataStream);

    // If we're the coordinator, set up inlets from other nodes
    if (_isCoordinator) {
      await _setupDataStreamCoordination(dataStream);
    }

    // Send coordination message about stream creation
    await sendUserEvent(
      UserEvent(
        id: 'data_stream_created',
        description: 'Data stream ${config.name} created',
        metadata: {
          'stream_name': config.name,
          'stream_id': config.id,
          'channels': config.channels.toString(),
          'sample_rate': config.sampleRate.toString(),
          'node_id': thisNode.id,
        },
      ),
    );

    return dataStream;
  }

  /// Sets up data stream coordination for hierarchical topology
  Future<void> _setupDataStreamCoordination(LSLDataStream dataStream) async {
    if (!_isCoordinator || _discovery == null) return;

    // Start discovering data streams from other nodes immediately
    final predicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: dataStream.config.name,
      sessionName: config.name,
    );
    // Create a separate discovery instance for data streams
    final dataStreamDiscovery = LslDiscovery(
      streamConfig: coordinationConfig.streamConfig,
      coordinationConfig: coordinationConfig,
      id: 'data-stream-discovery-${dataStream.config.name}',
      predicate: predicate,
    );

    await dataStreamDiscovery.create();
    await manageResource(dataStreamDiscovery);

    // Listen for data stream discoveries
    dataStreamDiscovery.events.listen((event) {
      if (event is StreamDiscoveredEvent) {
        _handleDataStreamDiscovered(event, dataStream, dataStreamDiscovery);
      }
    });

    // dataStreamDiscovery.startDiscovery(predicate: predicate);
  }

  /// Handles discovered data streams from other nodes
  Future<void> _handleDataStreamDiscovered(
    StreamDiscoveredEvent event,
    LSLDataStream dataStream,
    LslDiscovery discovery,
  ) async {
    // Create inlets for each discovered data stream
    for (final streamInfoResource in event.streams) {
      try {
        // Try to release from discovery - it might already be released
        streamInfoResource.manager?.releaseResource(streamInfoResource.uId);
      } catch (e) {
        // Resource might already be released or moved - that's okay
        logger.fine('Resource ${streamInfoResource.uId} already released: $e');
      }

      // Only manage the resource if it hasn't been disposed
      if (!streamInfoResource.disposed) {
        await manageResource<StreamInfoResource>(streamInfoResource);
        await dataStream.addInlet(streamInfoResource.streamInfo);
      } else {
        logger.fine('Skipping disposed resource ${streamInfoResource.uId}');
      }
    }
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
    _heartbeatTimer?.cancel();

    // Clean up LSL resources
    _coordinationOutlet?.destroy();
    _coordinationInlet?.destroy();
    _discovery?.dispose();

    _coordinationEventsController.add(
      CoordinationEvent(
        id: 'left_session',
        description: 'Left coordination session',
      ),
    );
  }

  @override
  Future<void> pause() async {
    await super.pause();
    _heartbeatTimer?.cancel();
    _discovery?.pause();
  }

  @override
  Future<void> resume() async {
    await super.resume();
    _startHeartbeat();
    _discovery?.resume();
  }
}
