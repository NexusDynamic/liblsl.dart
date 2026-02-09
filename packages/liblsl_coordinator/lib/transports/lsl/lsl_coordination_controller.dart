import 'dart:async';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

/// Controls the coordination flow with clear phases and event-driven logic.
///
/// Emits all coordination events through a single [events] stream.
/// Use the [ControllerEventStreamExtensions] for convenient filtering.
class CoordinationController {
  final CoordinationConfig coordinationConfig;
  final LSLTransport transport;
  Node get thisNode => _thisNode;
  Node _thisNode;
  final CoordinationSession session;

  late final CoordinationState _state;
  late final LSLCoordinationStream _coordinationStream;
  late final LslDiscovery _discovery;

  bool _stopping = false;

  CoordinatorMessageHandler? _coordinatorHandler;
  ParticipantMessageHandler? _participantHandler;

  Timer? _heartbeatTimer;
  Timer? _nodeTimeoutTimer;
  StreamSubscription? _coordinationSubscription;
  StreamSubscription? _handlerSubscription;
  StreamSubscription? _handlerEventSubscription;
  StreamSubscription? _discoverySubscription;
  StreamSubscription? _stateEventSubscription;

  /// Single event stream for all coordination events.
  final StreamController<ControllerEvent> _eventController =
      StreamController<ControllerEvent>.broadcast();

  /// Single public stream for all coordination events.
  ///
  /// Use the extension methods for convenient filtering:
  /// ```dart
  /// controller.events.phaseChanges.listen((e) => ...);
  /// controller.events.streamCreate.listen((e) => ...);
  /// controller.events.nodeJoined.listen((e) => ...);
  /// ```
  Stream<ControllerEvent> get events => _eventController.stream;

  CoordinationPhase get currentPhase => _state.phase;
  bool get isCoordinator => _state.isCoordinator;
  String? get coordinatorUId => _state.coordinatorUId;
  List<Node> get connectedNodes => _state.connectedNodes;
  List<Node> get connectedParticipantNodes => _state.connectedParticipantNodes;

  CoordinationController({
    required this.coordinationConfig,
    required this.transport,
    required Node thisNode,
    required this.session,
  }) : _thisNode = thisNode {
    _state = CoordinationState();
    _setupStateListeners();
  }

  void _setupStateListeners() {
    // Forward state events to the unified event stream
    _stateEventSubscription = _state.events.listen(_eventController.add);
  }

  /// Initialize the controller - creates streams and discovery
  Future<void> initialize() async {
    logger.info('Initializing coordination controller');

    // Create coordination stream
    final factory = LSLNetworkStreamFactory();
    _coordinationStream = await factory.createCoordinationStream(
      coordinationConfig.streamConfig,
      session, // We'll manage this ourselves
    );

    await _coordinationStream.create();
    await _coordinationStream.createOutlet();
    await _coordinationStream.start();

    // Create discovery
    _discovery = await transport.createDiscovery(
      streamConfig: coordinationConfig.streamConfig,
      coordinationConfig: coordinationConfig,
      id: 'coordination-discovery',
    );

    logger.info('Coordination controller initialized');
  }

  /// Start the coordination process - begins election
  Future<void> start() async {
    if (_state.phase != CoordinationPhase.idle) {
      throw StateError('Coordination already started');
    }

    logger.info('Starting coordination process...');
    _state.transitionTo(CoordinationPhase.discovering);

    await _startElection();
  }

  /// Election process - discover coordinators or become one
  Future<void> _startElection() async {
    logger.info('Starting coordinator election');
    _state.transitionTo(CoordinationPhase.electing);

    final topologyConfig =
        coordinationConfig.topologyConfig as HierarchicalTopologyConfig;
    final strategy = topologyConfig.promotionStrategy;
    final isRandomStrategy = strategy is PromotionStrategyRandom;

    // Build election predicate
    final myRandomRoll = isRandomStrategy
        ? double.parse(thisNode.metadata['randomRoll'] ?? '1.0')
        : null;
    final myStartTime = !isRandomStrategy
        ? thisNode.metadata['nodeStartedAt']
        : null;

    final electionPredicate = LSLStreamInfoHelper.generateElectionPredicate(
      streamName: coordinationConfig.streamConfig.name,
      sessionName: coordinationConfig.sessionConfig.name,
      excludeSourceIdPrefix: thisNode.id,
      isRandomStrategy: isRandomStrategy,
      myRandomRoll: myRandomRoll,
      myStartTime: myStartTime,
    );

    logger.finest('Election predicate: $electionPredicate');

    try {
      final streamInfos = await LslDiscovery.discoverOnceByPredicate(
        electionPredicate,
        timeout:
            coordinationConfig.sessionConfig.discoveryInterval *
            2, // Shorter timeout
        minStreams: 1,
        maxStreams: 1,
      );

      if (streamInfos.isNotEmpty) {
        // Found better candidate or coordinator - become participant
        logger.info(
          'Election: Found existing coordinator or better candidate, becoming participant',
        );
        await _becomeParticipant(streamInfos.first);
      } else {
        // No better candidates - become coordinator
        logger.info(
          'Election: No existing coordinator or better candidate found, becoming coordinator',
        );
        await _becomeCoordinator();
      }
    } catch (e) {
      logger.warning('Election discovery failed, becoming coordinator: $e');
      await _becomeCoordinator();
    }
  }

  /// Become the coordinator
  Future<void> _becomeCoordinator() async {
    logger.finer('Becoming coordinator');

    // Update node role and recreate outlet
    final coordinatorNode = thisNode.asCoordinator;
    _thisNode = coordinatorNode;
    _coordinationStream.updateNode(coordinatorNode);
    await _coordinationStream.recreateOutlet();
    // add self to state
    _state.addNode(_thisNode);
    // Update state
    _state.becomeCoordinator(thisNode.uId);

    // Create coordinator handler
    _coordinatorHandler = CoordinatorMessageHandler(
      state: _state,
      thisNode: coordinatorNode,
      sessionConfig: coordinationConfig.sessionConfig,
    );

    // Start coordinator services
    await _startCoordinatorServices();

    // Transition to accepting phase immediately
    _state.transitionTo(CoordinationPhase.accepting);

    logger.fine('Coordinator ready, accepting nodes');
    if (coordinationConfig
        .sessionConfig
        .consumeCoordinationStreamAsCoordinator) {
      // Connect to own coordinator stream as participant
      await _connectToCoordinator(thisNode.uId);
    } else {
      logger.info('Not consuming own coordinator stream as per configuration');
    }
  }

  /// Become a participant
  Future<void> _becomeParticipant(LSLStreamInfo coordinatorStream) async {
    logger.finer('Becoming participant');

    // Update node role and recreate outlet
    final participantNode = thisNode.asParticipant;
    _thisNode = participantNode;
    _coordinationStream.updateNode(participantNode);
    await _coordinationStream.recreateOutlet();

    // Update state
    _state.becomeParticipant();

    // Create participant handler
    _participantHandler = ParticipantMessageHandler(
      state: _state,
      thisNode: participantNode,
      sessionConfig: coordinationConfig.sessionConfig,
    );

    // Connect to coordinator
    await _connectToCoordinator();

    // Start participant services
    await _startParticipantServices();

    logger.fine('Participant connected to coordinator');
  }

  /// Connect to coordinator stream
  Future<void> _connectToCoordinator([String? coordinatorUId]) async {
    logger.finest(
      '[CONTROLLER-${thisNode.uId}] Connecting to coordinator: (maybe:? $coordinatorUId)',
    );
    final predicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: coordinationConfig.streamConfig.name,
      sessionName: coordinationConfig.sessionConfig.name,
      nodeUId:
          coordinatorUId, // if null, will match any coordinator - usually OK
      nodeRole: NodeCapability.coordinator.shortString,
    );

    logger.finest(
      'attempting to find the coordinator stream using predicate: $predicate',
    );
    // TODO: Timeouts all round...
    final streamInfos = await LslDiscovery.discoverOnceByPredicate(
      predicate,
      timeout: coordinationConfig.sessionConfig.discoveryInterval * 10,
      minStreams: 1,
      maxStreams: 1,
    );

    if (streamInfos.isEmpty) {
      logger.severe(
        '[CONTROLLER-${thisNode.uId}] Failed to find coordinator stream',
      );
      throw StateError('Failed to find coordinator stream');
    }

    logger.finer(
      '[CONTROLLER-${thisNode.uId}] Found coordinator stream, adding inlet...',
    );
    if (thisNode.uId != coordinatorUId) {
      // parse streaminfo
      final info = LSLStreamInfoHelper.parseSourceId(
        streamInfos.first.sourceId,
      );
      final nodeUId = info[LSLStreamInfoHelper.nodeUIdKey]!;
      logger.fine(
        '[CONTROLLER-${thisNode.uId}] Connecting to coordinator stream of node $nodeUId as participant',
      );
      // set coordinator UId in state
      _state.becomeParticipant(nodeUId);
    } else {
      logger.fine(
        '[CONTROLLER-${thisNode.uId}] Connected to own coordinator stream (self-coordination)',
      );
    }

    await _coordinationStream.addInlet(streamInfos.first);
    final streamInfoXml = streamInfos.first.toXml();
    // ip related info: `<hostname>`,`<v4address>`, `<v4data_port>`, `<v4service_port>`, `<v6address>`, `<v6data_port>`, `<v6service_port>`
    // match with regex -> that way no need for XML libraries, this is just a one-off (once per coordination session)
    final ipInfo = RegExp(r'<(hostname|v[46]address|v[46]data_port|v[46]service_port)>(.*?)<\/\1>')
        .allMatches(streamInfoXml)
        .map((m) => '${m.group(1)}: ${m.group(2)}')
        .join(', ');
    logger.info(
      '[CONTROLLER-${thisNode.uId}] Connected to coordinator stream successfully ($ipInfo)',
    );
  }

  /// Start coordinator-specific services
  Future<void> _startCoordinatorServices() async {
    // Listen to coordination messages
    _coordinationSubscription = _coordinationStream.inbox.listen(
      (message) async => await _handleIncomingMessage(message),
      onError: (error) => logger.severe(
        '[CONTROLLER-${thisNode.uId}] Error in coordination message stream: $error',
      ),
    );

    // Listen to outgoing messages from handler
    _handlerSubscription = _coordinatorHandler!.outgoingMessages.listen(
      _sendMessage,
    );

    // Forward handler events to the unified event stream
    _handlerEventSubscription = _coordinatorHandler!.events.listen(
      _eventController.add,
    );

    // Start heartbeat
    _startHeartbeat();

    // Start node discovery
    _startNodeDiscovery();

    // Start node timeout checking
    _startNodeTimeoutCheck();
  }

  /// Start participant-specific services
  Future<void> _startParticipantServices() async {
    // Listen to coordination messages
    _coordinationSubscription = _coordinationStream.inbox.listen(
      (message) async => await _handleIncomingMessage(message),
      onError: (error) => logger.severe(
        '[CONTROLLER-${thisNode.uId}] Error in coordination message stream: $error',
      ),
    );

    // Listen to outgoing messages from handler
    _handlerSubscription = _participantHandler!.outgoingMessages.listen(
      _sendMessage,
    );

    // Forward handler events to the unified event stream
    _handlerEventSubscription = _participantHandler!.events.listen(
      _eventController.add,
    );

    // Send join request
    logger.info('Sending join request to coordinator');
    await _participantHandler!.sendJoinRequest();

    // Start heartbeat
    _startHeartbeat();
  }

  Future<void> _handleIncomingMessage(StringMessage message) async {
    try {
      final CoordinationMessage coordMessage;
      try {
        coordMessage = CoordinationMessage.fromJson(message.data.first);
      } catch (e) {
        logger.severe(
          '[CONTROLLER-${thisNode.uId}] Invalid coordination message JSON: $e\nRaw message data: ${message.data}',
        );
        return;
      }

      // Route to appropriate handler
      if (_coordinatorHandler?.canHandle(coordMessage.type) == true) {
        try {
          await _coordinatorHandler!.handleMessage(coordMessage);
        } catch (e) {
          logger.severe(
            '[CONTROLLER-${thisNode.uId}] Error in coordinator handler for ${coordMessage.type}: $e',
          );
        }
      } else if (_participantHandler?.canHandle(coordMessage.type) == true) {
        try {
          await _participantHandler!.handleMessage(coordMessage);
        } catch (e) {
          logger.severe(
            '[CONTROLLER-${thisNode.uId}] Error in participant handler for ${coordMessage.type}: $e',
          );
        }
      } else {
        logger.warning(
          '[CONTROLLER-${thisNode.uId}] No handler for message type: ${coordMessage.type}',
        );
      }
    } catch (e) {
      logger.severe(
        '[CONTROLLER-${thisNode.uId}] Failed to parse coordination message: $e\nRaw message data: ${message.data}',
      );
    }
  }

  Future<void> _sendMessage(CoordinationMessage message) async {
    logger.finest('[CONTROLLER-${thisNode.uId}] Sending ${message.type}');
    final stringMessage = MessageFactory.stringMessage(
      data: IList([message.toJson()]),
      channels: 1,
    );
    await _coordinationStream.sendMessage(stringMessage);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      coordinationConfig.sessionConfig.heartbeatInterval,
      (_) async {
        if (_stopping) return;

        logger.finest('[${thisNode.uId}] Sending heartbeat');
        if (_state.isCoordinator) {
          // Coordinator sends heartbeat through normal message flow
          final heartbeat = HeartbeatMessage(
            fromNodeUId: thisNode.uId,
            nodeRole: thisNode.role,
            isCoordinator: true,
          );
          await _coordinatorHandler!.sendMessage(heartbeat);
        } else {
          // Participant sends heartbeat
          await _participantHandler!.sendHeartbeat();
        }
      },
    );
  }

  Future<void> _startNodeDiscovery() async {
    if (!_state.isCoordinator) return;

    await _discoverySubscription?.cancel();
    _discoverySubscription = _discovery.events.listen((discoveryEvent) {
      if (_stopping) return;
      if (discoveryEvent is StreamDiscoveredEvent) {
        for (StreamInfoResource infoResource in discoveryEvent.streams) {
          final info = LSLStreamInfoHelper.parseSourceId(
            infoResource.streamInfo.sourceId,
          );
          final nodeUId = info[LSLStreamInfoHelper.nodeUIdKey]!;
          final nodeId = info[LSLStreamInfoHelper.nodeIdKey]!;
          final nodeRole = info[LSLStreamInfoHelper.nodeRoleKey]!;
          if (nodeUId == thisNode.uId) {
            // Ignore our own stream
            continue;
          }
          if (_state.connectedNodes.any((n) => n.uId == nodeUId)) {
            // Already connected
            continue;
          }

          logger.info(
            'Discovered new node: $nodeId ($nodeUId), role: $nodeRole',
          );

          final nodeConfig = NodeConfig(
            id: nodeId,
            name: 'participant-$nodeId',
            uId: nodeUId,
            capabilities: {NodeCapability.participant},
            metadata: {'discoveredAt': DateTime.now().toIso8601String()},
          );
          final newNode = ParticipantNode(nodeConfig);

          // Don't add node to state yet - wait for successful join request
          // TODO: reimplement management.
          infoResource.updateManager(null);
          _coordinationStream.addInlet(infoResource.streamInfo).then((_) {
            logger.finest(
              'Added inlet for discovered node $nodeId ($nodeUId), sending join offer',
            );
            // TODO: ensure state is correct and we can accept nodes
            if (!_state.canAcceptNodes) {
              logger.warning(
                'Not accepting new nodes, skipping join offer to $nodeId ($nodeUId)',
              );
              return;
            }
            _coordinatorHandler!.sendJoinOffer(newNode);
          });
        }
      } else if (discoveryEvent is DiscoveryTimeoutEvent) {
        logger.severe('Unexpected discovery timeout event received');
      }
    });
    final predicate = LSLStreamInfoHelper.generatePredicate(
      streamNamePrefix: coordinationConfig.streamConfig.name,
      sessionName: coordinationConfig.sessionConfig.name,
      nodeRole: NodeCapability.participant.shortString,
    );

    _discovery.startDiscovery(predicate: predicate);
  }

  void _startNodeTimeoutCheck() {
    if (!_state.isCoordinator) return;

    _nodeTimeoutTimer?.cancel();
    _nodeTimeoutTimer = Timer.periodic(
      Duration(
        seconds: coordinationConfig.sessionConfig.nodeTimeout.inSeconds ~/ 2,
      ),
      (_) {
        final staleNodes = _state.getStaleNodes(
          coordinationConfig.sessionConfig.nodeTimeout,
        );
        for (final nodeUId in staleNodes) {
          if (nodeUId == thisNode.uId) continue;
          logger.warning('Node $nodeUId timed out');
          _state.removeNode(nodeUId);
          // Broadcast topology update will happen automatically via state listener
          _coordinatorHandler!.broadcastTopologyUpdate();
        }
      },
    );
  }

  // Public coordinator methods
  Future<void> pauseAcceptingNodes() async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can pause accepting nodes');
    }
    _coordinatorHandler!.pauseAcceptingNodes();
  }

  Future<void> resumeAcceptingNodes() async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can resume accepting nodes');
    }
    _coordinatorHandler!.resumeAcceptingNodes();
  }

  bool get isAcceptingNodes => _coordinatorHandler?.isAcceptingNodes ?? false;

  Future<void> createStream(String streamName, DataStreamConfig config) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can create streams');
    }
    await _coordinatorHandler!.broadcastCreateStream(streamName, config);
  }

  Future<void> startStream(
    String streamName,
    DataStreamConfig config, {
    DateTime? startAt,
  }) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can start streams');
    }
    await _coordinatorHandler!.broadcastStartStream(
      streamName,
      config,
      startAt: startAt,
    );
  }

  Future<void> markStreamReady(String streamName) async {
    if (_state.isCoordinator) {
      await _coordinatorHandler!.broadcastStreamReady(streamName);
    } else {
      await _participantHandler!.broadcastStreamReady(streamName);
    }
  }

  Future<void> stopStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can stop streams');
    }
    await _coordinatorHandler!.broadcastStopStream(streamName);
  }

  Future<void> pauseStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can pause streams');
    }
    await _coordinatorHandler!.broadcastPauseStream(streamName);
  }

  Future<void> resumeStream(
    String streamName, {
    bool flushBeforeResume = true,
  }) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can resume streams');
    }
    await _coordinatorHandler!.broadcastResumeStream(
      streamName,
      flushBeforeResume: flushBeforeResume,
    );
  }

  Future<void> flushStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can flush streams');
    }
    await _coordinatorHandler!.broadcastFlushStream(streamName);
  }

  Future<void> destroyStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can destroy streams');
    }
    await _coordinatorHandler!.broadcastDestroyStream(streamName);
  }

  Future<void> sendUserMessage(
    String messageId,
    String description,
    Map<String, dynamic> payload,
  ) async {
    if (!_state.isCoordinator) {
      // @TODO: Implement properly
      await _participantHandler!.sendMessage(
        UserParticipantMessage(
          fromNodeUId: thisNode.uId,
          messageId: messageId,
          description: description,
          payload: payload,
        ),
      );
      return;
    }
    await _coordinatorHandler!.broadcastUserMessage(
      messageId,
      description,
      payload,
    );
  }

  Future<void> updateConfig(Map<String, dynamic> config) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can update config');
    }
    await _coordinatorHandler!.broadcastConfig(config);
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    _state.transitionTo(CoordinationPhase.disposing);
    _stopping = true;
    logger.info('Disposing coordination controller');
    _heartbeatTimer?.cancel();
    _nodeTimeoutTimer?.cancel();
    _discovery.stopDiscovery();
    await _discoverySubscription?.cancel();
    await _stateEventSubscription?.cancel();
    await _handlerEventSubscription?.cancel();
    if (!_state.isCoordinator && _participantHandler != null) {
      try {
        logger.info('Announcing leaving to coordinator');
        await _participantHandler!.announceLeaving();
      } catch (e) {
        logger.warning('Failed to announce leaving: $e');
      }
    }
    await _coordinationStream.dispose();
    _coordinatorHandler?.dispose();
    _participantHandler?.dispose();

    await _discovery.dispose();

    await _coordinationSubscription?.cancel();
    await _handlerSubscription?.cancel();

    _state.dispose();
    await _eventController.close();
    logger.info('Coordination controller disposed');
  }
}
