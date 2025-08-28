import 'dart:async';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

/// Controls the coordination flow with clear phases and event-driven logic
class CoordinationController {
  final CoordinationConfig coordinationConfig;
  final LSLTransport transport;
  final Node thisNode;
  final CoordinationSession session;

  late final CoordinationState _state;
  late final LSLCoordinationStream _coordinationStream;
  late final LslDiscovery _discovery;

  CoordinatorMessageHandler? _coordinatorHandler;
  ParticipantMessageHandler? _participantHandler;

  Timer? _heartbeatTimer;
  Timer? _discoveryTimer;
  Timer? _nodeTimeoutTimer;
  StreamSubscription? _coordinationSubscription;
  StreamSubscription? _handlerSubscription;

  // Public streams for application logic
  final StreamController<CoordinationPhase> _phaseController =
      StreamController<CoordinationPhase>.broadcast();
  final StreamController<StartStreamMessage> _streamStartController =
      StreamController<StartStreamMessage>.broadcast();
  final StreamController<StopStreamMessage> _streamStopController =
      StreamController<StopStreamMessage>.broadcast();
  final StreamController<UserCoordinationMessage> _userMessageController =
      StreamController<UserCoordinationMessage>.broadcast();
  final StreamController<ConfigUpdateMessage> _configUpdateController =
      StreamController<ConfigUpdateMessage>.broadcast();
  final StreamController<Node> _nodeJoinedController =
      StreamController<Node>.broadcast();
  final StreamController<Node> _nodeLeftController =
      StreamController<Node>.broadcast();

  // Public API
  Stream<CoordinationPhase> get phaseChanges => _phaseController.stream;
  Stream<StartStreamMessage> get streamStartCommands =>
      _streamStartController.stream;
  Stream<StopStreamMessage> get streamStopCommands =>
      _streamStopController.stream;
  Stream<UserCoordinationMessage> get userMessages =>
      _userMessageController.stream;
  Stream<ConfigUpdateMessage> get configUpdates =>
      _configUpdateController.stream;
  Stream<Node> get nodeJoined => _nodeJoinedController.stream;
  Stream<Node> get nodeLeft => _nodeLeftController.stream;

  CoordinationPhase get currentPhase => _state.phase;
  bool get isCoordinator => _state.isCoordinator;
  String? get coordinatorUId => _state.coordinatorUId;
  List<Node> get connectedNodes => _state.connectedNodes;

  CoordinationController({
    required this.coordinationConfig,
    required this.transport,
    required this.thisNode,
    required this.session,
  }) {
    _state = CoordinationState();
    _setupStateListeners();
  }

  void _setupStateListeners() {
    // Forward state events to public streams
    _state.phaseChanges.listen(_phaseController.add);
    _state.nodeJoined.listen(_nodeJoinedController.add);
    _state.nodeLeft.listen(_nodeLeftController.add);
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

    logger.info('Starting coordination process');
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
    final myRandomRoll =
        isRandomStrategy
            ? double.parse(thisNode.metadata['randomRoll'] ?? '1.0')
            : null;
    final myStartTime =
        !isRandomStrategy ? thisNode.metadata['nodeStartedAt'] : null;

    final electionPredicate = LSLStreamInfoHelper.generateElectionPredicate(
      streamName: coordinationConfig.streamConfig.name,
      sessionName: coordinationConfig.sessionConfig.name,
      excludeSourceIdPrefix: thisNode.id,
      isRandomStrategy: isRandomStrategy,
      myRandomRoll: myRandomRoll,
      myStartTime: myStartTime,
    );

    try {
      final streamInfos = await LslDiscovery.discoverOnceByPredicate(
        electionPredicate,
        timeout: coordinationConfig.sessionConfig.discoveryInterval * 3,
        maxStreams: 1,
      );

      if (streamInfos.isNotEmpty) {
        // Found better candidate or coordinator - become participant
        await _becomeParticipant(streamInfos.first);
      } else {
        // No better candidates - become coordinator
        await _becomeCoordinator();
      }
    } catch (e) {
      logger.warning('Election discovery failed, becoming coordinator: $e');
      await _becomeCoordinator();
    }
  }

  /// Become the coordinator
  Future<void> _becomeCoordinator() async {
    logger.info('Becoming coordinator');

    // Update node role and recreate outlet
    thisNode.asCoordinator;
    await _coordinationStream.recreateOutlet();

    // Update state
    _state.becomeCoordinator(thisNode.uId);

    // Create coordinator handler
    _coordinatorHandler = CoordinatorMessageHandler(
      state: _state,
      thisNode: thisNode,
      sessionConfig: coordinationConfig.sessionConfig,
    );

    // Start coordinator services
    await _startCoordinatorServices();

    // Transition to accepting new nodes
    _state.transitionTo(CoordinationPhase.accepting);

    logger.info('Coordinator ready, accepting nodes');
  }

  /// Become a participant
  Future<void> _becomeParticipant(LSLStreamInfo coordinatorStream) async {
    logger.info('Becoming participant');

    // Update node role and recreate outlet
    thisNode.asParticipant;
    await _coordinationStream.recreateOutlet();

    // Extract coordinator info
    final sourceInfo = LSLStreamInfoHelper.parseSourceId(
      coordinatorStream.sourceId,
    );
    final coordinatorUId = sourceInfo[LSLStreamInfoHelper.nodeUIdKey]!;

    // Update state
    _state.becomeParticipant(coordinatorUId);

    // Create participant handler
    _participantHandler = ParticipantMessageHandler(
      state: _state,
      thisNode: thisNode,
      sessionConfig: coordinationConfig.sessionConfig,
    );

    // Connect to coordinator
    await _connectToCoordinator(coordinatorUId);

    // Start participant services
    await _startParticipantServices();

    logger.info('Participant connected to coordinator');
  }

  /// Connect to coordinator stream
  Future<void> _connectToCoordinator(String coordinatorUId) async {
    final predicate = LSLStreamInfoHelper.generatePredicate(
      sessionName: coordinationConfig.sessionConfig.name,
      nodeUId: coordinatorUId,
      nodeRole: NodeCapability.coordinator.shortString,
    );

    final streamInfos = await LslDiscovery.discoverOnceByPredicate(
      predicate,
      timeout: coordinationConfig.sessionConfig.discoveryInterval * 3,
      maxStreams: 1,
    );

    if (streamInfos.isEmpty) {
      throw StateError('Failed to find coordinator stream');
    }

    await _coordinationStream.addInlet(streamInfos.first);
    logger.info('Connected to coordinator stream');
  }

  /// Start coordinator-specific services
  Future<void> _startCoordinatorServices() async {
    // Listen to coordination messages
    _coordinationSubscription = _coordinationStream.inbox.listen(
      _handleIncomingMessage,
    );

    // Listen to outgoing messages from handler
    _handlerSubscription = _coordinatorHandler!.outgoingMessages.listen(
      _sendMessage,
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
      _handleIncomingMessage,
    );

    // Listen to outgoing messages from handler
    _handlerSubscription = _participantHandler!.outgoingMessages.listen(
      _sendMessage,
    );

    // Forward handler events to public streams
    _participantHandler!.streamStartCommands.listen(_streamStartController.add);
    _participantHandler!.streamStopCommands.listen(_streamStopController.add);
    _participantHandler!.userMessages.listen(_userMessageController.add);
    _participantHandler!.configUpdates.listen(_configUpdateController.add);

    // Send join request
    await _participantHandler!.sendJoinRequest();

    // Start heartbeat
    _startHeartbeat();
  }

  void _handleIncomingMessage(StringMessage message) {
    try {
      final coordMessage = CoordinationMessage.fromJson(message.data.first);

      // Route to appropriate handler
      if (_coordinatorHandler?.canHandle(coordMessage.type) == true) {
        _coordinatorHandler!.handleMessage(coordMessage);
      } else if (_participantHandler?.canHandle(coordMessage.type) == true) {
        _participantHandler!.handleMessage(coordMessage);
      } else {
        logger.warning('No handler for message type: ${coordMessage.type}');
      }
    } catch (e) {
      logger.warning('Failed to parse coordination message: $e');
    }
  }

  Future<void> _sendMessage(CoordinationMessage message) async {
    final stringMessage = MessageFactory.stringMessage(
      data: [message.toJson()],
      channels: 1,
    );
    await _coordinationStream.sendMessage(stringMessage);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      coordinationConfig.sessionConfig.heartbeatInterval,
      (_) async {
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

  void _startNodeDiscovery() {
    if (!_state.isCoordinator) return;

    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(
      coordinationConfig.sessionConfig.discoveryInterval,
      (_) async {
        // Discover participant nodes
        final predicate = LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: coordinationConfig.streamConfig.name,
          sessionName: coordinationConfig.sessionConfig.name,
          nodeRole: 'participant',
        );

        _discovery.startDiscovery(
          predicate: predicate,
          timeout: Duration(seconds: 1),
        );
      },
    );
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

  Future<void> stopStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can stop streams');
    }
    await _coordinatorHandler!.broadcastStopStream(streamName);
  }

  Future<void> sendUserMessage(
    String messageId,
    String description,
    Map<String, dynamic> payload,
  ) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can send user messages');
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
    _heartbeatTimer?.cancel();
    _discoveryTimer?.cancel();
    _nodeTimeoutTimer?.cancel();

    await _coordinationSubscription?.cancel();
    await _handlerSubscription?.cancel();

    // Send leaving message if we're a participant
    if (!_state.isCoordinator && _participantHandler != null) {
      await _participantHandler!.announceLeaving();
    }

    _coordinatorHandler?.dispose();
    _participantHandler?.dispose();

    await _coordinationStream.dispose();
    await _discovery.dispose();

    _state.dispose();

    await _phaseController.close();
    await _streamStartController.close();
    await _streamStopController.close();
    await _userMessageController.close();
    await _configUpdateController.close();
    await _nodeJoinedController.close();
    await _nodeLeftController.close();
  }
}
