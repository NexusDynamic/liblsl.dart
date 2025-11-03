import 'dart:async';
import 'package:liblsl_coordinator/framework.dart';

/// Base class for handling coordination messages
abstract class CoordinationMessageHandler {
  final CoordinationState state;
  final Node thisNode;
  final CoordinationSessionConfig sessionConfig;

  CoordinationMessageHandler({
    required this.state,
    required this.thisNode,
    required this.sessionConfig,
  });

  /// Handle incoming coordination message
  Future<void> handleMessage(CoordinationMessage message);

  /// Send outgoing coordination message
  Future<void> sendMessage(CoordinationMessage message);

  /// Check if this handler should process the given message type
  bool canHandle(CoordinationMessageType type);
}

/// Handles coordination when this node is the coordinator
class CoordinatorMessageHandler extends CoordinationMessageHandler {
  final StreamController<CoordinationMessage> _outgoingController =
      StreamController<CoordinationMessage>();

  Stream<CoordinationMessage> get outgoingMessages =>
      _outgoingController.stream;

  final StreamController<UserParticipantMessage>
  _userParticipantMessageController =
      StreamController<UserParticipantMessage>.broadcast();

  Stream<UserParticipantMessage> get userParticipantMessages =>
      _userParticipantMessageController.stream;

  final StreamController<StreamReadyMessage> _streamReadyController =
      StreamController<StreamReadyMessage>.broadcast();
  Stream<StreamReadyMessage> get streamReadyNotifications =>
      _streamReadyController.stream;

  // Control flags
  bool _acceptingNewNodes = true;

  CoordinatorMessageHandler({
    required super.state,
    required super.thisNode,
    required super.sessionConfig,
  });

  @override
  bool canHandle(CoordinationMessageType type) {
    return state.isCoordinator &&
        {
          CoordinationMessageType.heartbeat,
          CoordinationMessageType.connectionTest,
          CoordinationMessageType.joinRequest,
          CoordinationMessageType.nodeLeaving,
          CoordinationMessageType.streamReady,
          CoordinationMessageType.userParticipantMessage,
        }.contains(type);
  }

  @override
  Future<void> handleMessage(CoordinationMessage message) async {
    switch (message.type) {
      case CoordinationMessageType.heartbeat:
        await _handleHeartbeat(message as HeartbeatMessage);
        break;
      case CoordinationMessageType.connectionTest:
        await _handleConnectionTest(message as ConnectionTestMessage);
        break;
      case CoordinationMessageType.joinRequest:
        await _handleJoinRequest(message as JoinRequestMessage);
        break;
      case CoordinationMessageType.nodeLeaving:
        await _handleNodeLeaving(message as NodeLeavingMessage);
        break;
      case CoordinationMessageType.streamReady:
        await _handleStreamReady(message as StreamReadyMessage);
      default:
        logger.warning(
          'Coordinator cannot handle message type: ${message.type}',
        );
    }
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    logger.finest('[COORDINATOR-${thisNode.uId}] Queuing ${message.type}');
    _outgoingController.add(message);
  }

  Future<void> _handleHeartbeat(HeartbeatMessage message) async {
    state.updateNodeHeartbeat(message.fromNodeUId);
    logger.finest(
      'Received heartbeat from ${message.fromNodeUId} (role: ${message.nodeRole})',
    );

    // If this is from a node we don't know about, it might be a rejoin
    final knownNode = state.connectedNodes.any(
      (n) => n.uId == message.fromNodeUId,
    );
    if (!knownNode && _acceptingNewNodes) {
      logger.warning(
        'Received heartbeat from unknown node, treating as implicit join request',
      );
      // We could auto-accept or request explicit join
    }
  }

  Future<void> _handleStreamReady(StreamReadyMessage message) async {
    logger.info(
      'Node ${message.fromNodeUId} is ready for stream ${message.streamName}',
    );
    _streamReadyController.add(message);
  }

  Future<void> _handleJoinRequest(JoinRequestMessage message) async {
    final nodeUId = message.fromNodeUId;

    // Check current state
    final isAlreadyConnected = state.connectedNodes.any(
      (n) => n.uId == nodeUId,
    );
    logger.info(
      'Join request from $nodeUId (already connected: $isAlreadyConnected, nodes: ${state.connectedNodes.length}/${sessionConfig.maxNodes})',
    );

    if (!isAlreadyConnected) {
      if (!_acceptingNewNodes) {
        logger.warning('Rejecting $nodeUId: not accepting new nodes');
        await _rejectJoin(nodeUId, 'Not accepting new nodes');
        return;
      }

      if (state.connectedNodes.length >= sessionConfig.maxNodes) {
        logger.warning(
          'Rejecting $nodeUId: max nodes reached (${state.connectedNodes.length}/${sessionConfig.maxNodes})',
        );
        await _rejectJoin(nodeUId, 'Maximum nodes reached');
        return;
      }
    }
    // If the node is already connected, it is fine, maybe a rejoin
    // if (state.connectedNodes.any((n) => n.uId == nodeUId)) {
    //   await _rejectJoin(nodeUId, 'Node already connected');
    //   return;
    // }

    // Accept the join
    await _acceptJoin(message);
  }

  Future<void> _handleConnectionTest(ConnectionTestMessage message) async {
    logger.info(
      'Received connection test ${message.testId} from ${message.fromNodeUId}',
    );

    // Send response immediately to confirm bidirectional communication
    final response = ConnectionTestResponseMessage(
      fromNodeUId: thisNode.uId,
      testId: message.testId,
      confirmed: true,
    );

    await sendMessage(response);
    logger.info('Sent connection test response for ${message.testId}');
  }

  Future<void> _acceptJoin(JoinRequestMessage request) async {
    final node = request.requestingNode;
    state.addNode(node);

    // Send acceptance with current topology
    final acceptMessage = JoinAcceptMessage(
      fromNodeUId: thisNode.uId,
      acceptedNodeUId: request.fromNodeUId,
      currentTopology: state.connectedNodes,
    );

    await sendMessage(acceptMessage);

    // Broadcast topology update to all other nodes
    await broadcastTopologyUpdate();

    logger.info('Accepted join from node ${node.id}');
  }

  Future<void> _rejectJoin(String nodeUId, String reason) async {
    final rejectMessage = JoinRejectMessage(
      fromNodeUId: thisNode.uId,
      rejectedNodeUId: nodeUId,
      reason: reason,
    );

    await sendMessage(rejectMessage);
    logger.info('Rejected join from node $nodeUId: $reason');
  }

  Future<void> _handleNodeLeaving(NodeLeavingMessage message) async {
    state.removeNode(message.leavingNodeUId);
    await broadcastTopologyUpdate();
    logger.info('Node ${message.leavingNodeUId} left the session');
  }

  Future<void> broadcastTopologyUpdate() async {
    final updateMessage = TopologyUpdateMessage(
      fromNodeUId: thisNode.uId,
      topology: state.connectedNodes,
    );

    await sendMessage(updateMessage);
  }

  Future<void> broadcastStreamReady(String streamName) async {
    final message = StreamReadyMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
    );
    await sendMessage(message);
  }

  // Coordinator control methods
  void pauseAcceptingNodes() => _acceptingNewNodes = false;
  void resumeAcceptingNodes() => _acceptingNewNodes = true;
  bool get isAcceptingNodes => _acceptingNewNodes;

  Future<void> broadcastCreateStream(
    String streamName,
    DataStreamConfig config,
  ) async {
    final message = CreateStreamMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
      streamConfig: config,
    );
    await sendMessage(message);
  }

  Future<void> broadcastStartStream(
    String streamName,
    DataStreamConfig config, {
    DateTime? startAt,
  }) async {
    final message = StartStreamMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
      streamConfig: config,
      startAt: startAt,
    );
    await sendMessage(message);
  }

  Future<void> sendJoinOffer(Node node) async {
    final message = JoinOfferMessage(
      fromNodeUId: thisNode.uId,
      targetNode: node,
      sessionId: sessionConfig.name,
    );
    await sendMessage(message);
  }

  Future<void> broadcastStopStream(String streamName) async {
    final message = StopStreamMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
    );
    await sendMessage(message);
  }

  Future<void> broadcastPauseStream(String streamName) async {
    final message = PauseStreamMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
    );
    await sendMessage(message);
  }

  Future<void> broadcastResumeStream(
    String streamName, {
    bool flushBeforeResume = true,
  }) async {
    final message = ResumeStreamMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
      flushBeforeResume: flushBeforeResume,
    );
    await sendMessage(message);
  }

  Future<void> broadcastFlushStream(String streamName) async {
    final message = FlushStreamMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
    );
    await sendMessage(message);
  }

  Future<void> broadcastDestroyStream(String streamName) async {
    final message = DestroyStreamMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
    );
    await sendMessage(message);
  }

  Future<void> broadcastUserMessage(
    String messageId,
    String description,
    Map<String, dynamic> payload,
  ) async {
    final message = UserCoordinationMessage(
      fromNodeUId: thisNode.uId,
      messageId: messageId,
      description: description,
      payload: payload,
    );
    await sendMessage(message);
  }

  Future<void> broadcastConfig(Map<String, dynamic> config) async {
    final message = ConfigUpdateMessage(
      fromNodeUId: thisNode.uId,
      config: config,
    );
    await sendMessage(message);
  }

  void dispose() {
    _outgoingController.close();
    _streamReadyController.close();
  }
}

/// Handles coordination when this node is a participant
class ParticipantMessageHandler extends CoordinationMessageHandler {
  final StreamController<CoordinationMessage> _outgoingController =
      StreamController<CoordinationMessage>();
  final StreamController<CreateStreamMessage> _streamCreateController =
      StreamController<CreateStreamMessage>.broadcast();
  final StreamController<StartStreamMessage> _streamStartController =
      StreamController<StartStreamMessage>.broadcast();
  final StreamController<StreamReadyMessage> _streamReadyController =
      StreamController<StreamReadyMessage>.broadcast();
  final StreamController<StopStreamMessage> _streamStopController =
      StreamController<StopStreamMessage>.broadcast();
  final StreamController<PauseStreamMessage> _streamPauseController =
      StreamController<PauseStreamMessage>.broadcast();
  final StreamController<ResumeStreamMessage> _streamResumeController =
      StreamController<ResumeStreamMessage>.broadcast();
  final StreamController<FlushStreamMessage> _streamFlushController =
      StreamController<FlushStreamMessage>.broadcast();
  final StreamController<DestroyStreamMessage> _streamDestroyController =
      StreamController<DestroyStreamMessage>.broadcast();
  final StreamController<UserCoordinationMessage> _userMessageController =
      StreamController<UserCoordinationMessage>.broadcast();
  final StreamController<ConfigUpdateMessage> _configUpdateController =
      StreamController<ConfigUpdateMessage>.broadcast();

  // Connection test tracking
  final Map<String, Completer<bool>> _pendingConnectionTests = {};
  Timer? _connectionTestTimer;

  Stream<CoordinationMessage> get outgoingMessages =>
      _outgoingController.stream;
  Stream<CreateStreamMessage> get streamCreateCommands =>
      _streamCreateController.stream;
  Stream<StartStreamMessage> get streamStartCommands =>
      _streamStartController.stream;
  Stream<StreamReadyMessage> get streamReadyNotifications =>
      _streamReadyController.stream;
  Stream<StopStreamMessage> get streamStopCommands =>
      _streamStopController.stream;
  Stream<PauseStreamMessage> get streamPauseCommands =>
      _streamPauseController.stream;
  Stream<ResumeStreamMessage> get streamResumeCommands =>
      _streamResumeController.stream;
  Stream<FlushStreamMessage> get streamFlushCommands =>
      _streamFlushController.stream;
  Stream<DestroyStreamMessage> get streamDestroyCommands =>
      _streamDestroyController.stream;
  Stream<UserCoordinationMessage> get userMessages =>
      _userMessageController.stream;
  Stream<ConfigUpdateMessage> get configUpdates =>
      _configUpdateController.stream;

  ParticipantMessageHandler({
    required super.state,
    required super.thisNode,
    required super.sessionConfig,
  });

  @override
  bool canHandle(CoordinationMessageType type) {
    return !state.isCoordinator &&
        {
          CoordinationMessageType.joinAccept,
          CoordinationMessageType.joinReject,
          CoordinationMessageType.topologyUpdate,
          CoordinationMessageType.createStream,
          CoordinationMessageType.startStream,
          CoordinationMessageType.stopStream,
          CoordinationMessageType.userMessage,
          CoordinationMessageType.configUpdate,
          CoordinationMessageType.heartbeat,
          CoordinationMessageType.joinOffer,
          CoordinationMessageType.connectionTestResponse,
          CoordinationMessageType.streamReady,
          CoordinationMessageType.pauseStream,
          CoordinationMessageType.resumeStream,
          CoordinationMessageType.flushStream,
          CoordinationMessageType.destroyStream,
        }.contains(type);
  }

  @override
  Future<void> handleMessage(CoordinationMessage message) async {
    // Always handle coordination-related messages regardless of state
    final isCoordinationMessage = {
      CoordinationMessageType.joinAccept,
      CoordinationMessageType.joinReject,
      CoordinationMessageType.joinOffer,
      CoordinationMessageType.connectionTestResponse,
      CoordinationMessageType.heartbeat,
      CoordinationMessageType.topologyUpdate,
    }.contains(message.type);

    // Only handle non-coordination messages if we're in ready state
    if (!isCoordinationMessage && state.phase != CoordinationPhase.ready) {
      logger.fine(
        'Ignoring ${message.type} message - participant not yet ready (phase: ${state.phase})',
      );
      return;
    }

    switch (message.type) {
      case CoordinationMessageType.joinAccept:
        await _handleJoinAccept(message as JoinAcceptMessage);
        break;
      case CoordinationMessageType.joinReject:
        await _handleJoinReject(message as JoinRejectMessage);
        break;
      case CoordinationMessageType.topologyUpdate:
        await _handleTopologyUpdate(message as TopologyUpdateMessage);
        break;
      case CoordinationMessageType.createStream:
        await _handleCreateStream(message as CreateStreamMessage);
        break;
      case CoordinationMessageType.startStream:
        await _handleStartStream(message as StartStreamMessage);
        break;
      case CoordinationMessageType.streamReady:
        await _handleStreamReady(message as StreamReadyMessage);
        break;
      case CoordinationMessageType.stopStream:
        await _handleStopStream(message as StopStreamMessage);
        break;
      case CoordinationMessageType.pauseStream:
        await _handlePauseStream(message as PauseStreamMessage);
        break;
      case CoordinationMessageType.resumeStream:
        await _handleResumeStream(message as ResumeStreamMessage);
        break;
      case CoordinationMessageType.flushStream:
        await _handleFlushStream(message as FlushStreamMessage);
        break;
      case CoordinationMessageType.destroyStream:
        await _handleDestroyStream(message as DestroyStreamMessage);
        break;
      case CoordinationMessageType.userMessage:
        await _handleUserMessage(message as UserCoordinationMessage);
        break;
      case CoordinationMessageType.configUpdate:
        await _handleConfigUpdate(message as ConfigUpdateMessage);
        break;
      case CoordinationMessageType.heartbeat:
        // We can keep track of the last seen heartbeat from the coordinator
        state.updateNodeHeartbeat(message.fromNodeUId);
        break;
      case CoordinationMessageType.joinOffer:
        await _handleJoinOffer(message as JoinOfferMessage);
        break;
      case CoordinationMessageType.connectionTestResponse:
        await _handleConnectionTestResponse(
          message as ConnectionTestResponseMessage,
        );
        break;
      default:
        logger.warning(
          'Participant cannot handle message type: ${message.type}',
        );
    }
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    logger.finest('[PARTICIPANT] Queuing ${message.type}');
    _outgoingController.add(message);
  }

  Future<void> broadcastStreamReady(String streamName) async {
    final message = StreamReadyMessage(
      fromNodeUId: thisNode.uId,
      streamName: streamName,
    );
    _streamReadyController.add(message);
    await sendMessage(message);
  }

  Future<void> _handleJoinAccept(JoinAcceptMessage message) async {
    logger.info(
      '[PARTICIPANT-${thisNode.uId}] Received join acceptance from coordinator: ${message.fromNodeUId}, target: ${message.acceptedNodeUId}, me: ${thisNode.uId}',
    );
    if (message.acceptedNodeUId == thisNode.uId) {
      // We've been accepted!
      logger.info('Join accepted by coordinator');
      state.transitionTo(CoordinationPhase.ready);

      // Update our topology with the provided info
      for (final node in message.currentTopology) {
        logger.info(
          '[PARTICIPANT-${thisNode.uId}] Adding node to topology: ${node.id} (${node.uId})',
        );
        state.addNode(node);
      }
    } else {
      logger.warning(
        '[PARTICIPANT-${thisNode.uId}] Join accept message not for me: target=${message.acceptedNodeUId}, me=${thisNode.uId}',
      );
    }
  }

  Future<void> _handleJoinOffer(JoinOfferMessage message) async {
    if (message.targetNode.uId == thisNode.uId) {
      // We've been offered to join
      logger.info('Received join offer from coordinator');

      // Send join request with connection confirmation
      await sendJoinRequestWithConfirmation();
    }
  }

  Future<void> _handleJoinReject(JoinRejectMessage message) async {
    if (message.rejectedNodeUId == thisNode.uId) {
      // We've been rejected
      throw StateError('Join rejected: ${message.reason}');
    }
  }

  Future<void> _handleTopologyUpdate(TopologyUpdateMessage message) async {
    // Update our view of the topology
    // For now, just replace everything (could be more sophisticated)
    final currentUIds = state.connectedNodes.map((n) => n.uId).toSet();
    final newUIds = message.topology.map((n) => n.uId).toSet();

    // Remove nodes that are no longer in the topology
    for (final removedUId in currentUIds.difference(newUIds)) {
      state.removeNode(removedUId);
    }

    // Add new nodes
    for (final node in message.topology) {
      if (!currentUIds.contains(node.uId)) {
        state.addNode(node);
      }
    }

    logger.info('Topology updated: ${state.connectedNodes.length} nodes');
  }

  Future<void> _handleCreateStream(CreateStreamMessage message) async {
    logger.info('Received create stream command: ${message.streamName}');
    _streamCreateController.add(message);
  }

  Future<void> _handleStartStream(StartStreamMessage message) async {
    logger.info('Received start stream command: ${message.streamName}');
    _streamStartController.add(message);
  }

  Future<void> _handleStreamReady(StreamReadyMessage message) async {
    logger.info(
      'Node ${message.fromNodeUId} is ready for stream ${message.streamName}',
    );
    _streamReadyController.add(message);
  }

  Future<void> _handleStopStream(StopStreamMessage message) async {
    logger.info('Received stop stream command: ${message.streamName}');
    _streamStopController.add(message);
  }

  Future<void> _handleUserMessage(UserCoordinationMessage message) async {
    logger.info(
      'Received user message: ${message.messageId} - ${message.description}',
    );
    _userMessageController.add(message);
  }

  Future<void> _handleConfigUpdate(ConfigUpdateMessage message) async {
    logger.info('Received config update from coordinator');
    _configUpdateController.add(message);
  }

  // Participant methods
  Future<void> sendJoinRequest() async {
    logger.info('Sending join request to coordinator');
    final message = JoinRequestMessage(
      fromNodeUId: thisNode.uId,
      requestingNode: thisNode,
      sessionId: sessionConfig.name,
    );
    await sendMessage(message);
  }

  Future<void> sendHeartbeat() async {
    final message = HeartbeatMessage(
      fromNodeUId: thisNode.uId,
      nodeRole: thisNode.role,
      isCoordinator: false,
    );
    await sendMessage(message);
  }

  Future<void> announceLeaving() async {
    final message = NodeLeavingMessage(
      fromNodeUId: thisNode.uId,
      leavingNodeUId: thisNode.uId,
    );
    await sendMessage(message);
  }

  Future<void> _handleConnectionTestResponse(
    ConnectionTestResponseMessage message,
  ) async {
    logger.info(
      'Received connection test response for ${message.testId}: ${message.confirmed}',
    );

    final completer = _pendingConnectionTests.remove(message.testId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message.confirmed);
    } else if (completer == null) {
      logger.warning(
        'Received unexpected connection test response: ${message.testId}',
      );
    }
  }

  /// Performs bidirectional connection confirmation before sending critical messages
  Future<bool> confirmConnection({
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final testId =
          '${thisNode.uId}_test_${DateTime.now().millisecondsSinceEpoch}_$attempt';
      logger.info(
        'Starting connection test $testId (attempt $attempt/$maxRetries)',
      );

      final completer = Completer<bool>();
      _pendingConnectionTests[testId] = completer;

      // Send connection test
      final testMessage = ConnectionTestMessage(
        fromNodeUId: thisNode.uId,
        testId: testId,
      );
      await sendMessage(testMessage);

      // Wait for response with timeout
      try {
        final confirmed = await completer.future.timeout(timeout);
        if (confirmed) {
          logger.info('Connection confirmed with test $testId');
          return true;
        } else {
          logger.warning('Connection test $testId failed: not confirmed');
        }
      } on TimeoutException catch (e) {
        logger.warning('Connection test $testId timed out: $e');
        _pendingConnectionTests.remove(testId);
      } catch (e) {
        logger.warning('Connection test $testId failed: $e');
        _pendingConnectionTests.remove(testId);
      }

      if (attempt < maxRetries) {
        logger.info('Retrying connection test in 1 second...');
        await Future.delayed(Duration(seconds: 1));
      }
    }

    logger.severe(
      'All connection test attempts failed after $maxRetries tries',
    );
    return false;
  }

  /// join request with connection confirmation
  Future<void> sendJoinRequestWithConfirmation() async {
    logger.info('Performing connection confirmation before join request');

    final connectionConfirmed = await confirmConnection(
      timeout: Duration(seconds: 20),
    );
    if (!connectionConfirmed) {
      throw StateError(
        'Unable to confirm bidirectional connection before join request',
      );
    }

    logger.info('Connection confirmed, sending join request to coordinator');
    await sendJoinRequest();
  }

  /// Handle pause stream message by forwarding to stream
  Future<void> _handlePauseStream(PauseStreamMessage message) async {
    _streamPauseController.add(message);
  }

  /// Handle resume stream message by forwarding to stream
  Future<void> _handleResumeStream(ResumeStreamMessage message) async {
    _streamResumeController.add(message);
  }

  /// Handle flush stream message by forwarding to stream
  Future<void> _handleFlushStream(FlushStreamMessage message) async {
    _streamFlushController.add(message);
  }

  /// Handle destroy stream message by forwarding to stream
  Future<void> _handleDestroyStream(DestroyStreamMessage message) async {
    _streamDestroyController.add(message);
  }

  void dispose() {
    _connectionTestTimer?.cancel();
    for (final completer in _pendingConnectionTests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Handler disposed'));
      }
    }
    _pendingConnectionTests.clear();

    _outgoingController.close();
    _streamCreateController.close();
    _streamStartController.close();
    _streamReadyController.close();
    _streamStopController.close();
    _streamPauseController.close();
    _streamResumeController.close();
    _streamFlushController.close();
    _streamDestroyController.close();
    _userMessageController.close();
    _configUpdateController.close();
  }
}
