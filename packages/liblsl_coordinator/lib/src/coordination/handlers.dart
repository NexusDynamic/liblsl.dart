import 'dart:async';
import 'package:liblsl_coordinator/framework.dart';
import 'coordinator_state.dart';
import 'messages.dart';

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
          CoordinationMessageType.joinRequest,
          CoordinationMessageType.nodeLeaving,
        }.contains(type);
  }

  @override
  Future<void> handleMessage(CoordinationMessage message) async {
    switch (message.type) {
      case CoordinationMessageType.heartbeat:
        await _handleHeartbeat(message as HeartbeatMessage);
        break;
      case CoordinationMessageType.joinRequest:
        await _handleJoinRequest(message as JoinRequestMessage);
        break;
      case CoordinationMessageType.nodeLeaving:
        await _handleNodeLeaving(message as NodeLeavingMessage);
        break;
      default:
        logger.warning(
          'Coordinator cannot handle message type: ${message.type}',
        );
    }
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    _outgoingController.add(message);
  }

  Future<void> _handleHeartbeat(HeartbeatMessage message) async {
    state.updateNodeHeartbeat(message.fromNodeUId);

    // If this is from a node we don't know about, it might be a rejoin
    final knownNode = state.connectedNodes.any(
      (n) => n.uId == message.fromNodeUId,
    );
    if (!knownNode && _acceptingNewNodes) {
      logger.info(
        'Received heartbeat from unknown node, treating as implicit join request',
      );
      // We could auto-accept or request explicit join
    }
  }

  Future<void> _handleJoinRequest(JoinRequestMessage message) async {
    final nodeUId = message.fromNodeUId;

    if (!_acceptingNewNodes) {
      await _rejectJoin(nodeUId, 'Not accepting new nodes');
      return;
    }

    if (state.connectedNodes.length >= sessionConfig.maxNodes) {
      await _rejectJoin(nodeUId, 'Maximum nodes reached');
      return;
    }

    if (state.connectedNodes.any((n) => n.uId == nodeUId)) {
      await _rejectJoin(nodeUId, 'Node already connected');
      return;
    }

    // Accept the join
    await _acceptJoin(message);
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

  // Coordinator control methods
  void pauseAcceptingNodes() => _acceptingNewNodes = false;
  void resumeAcceptingNodes() => _acceptingNewNodes = true;
  bool get isAcceptingNodes => _acceptingNewNodes;

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

  Future<void> broadcastStopStream(String streamName) async {
    final message = StopStreamMessage(
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
  }
}

/// Handles coordination when this node is a participant
class ParticipantMessageHandler extends CoordinationMessageHandler {
  final StreamController<CoordinationMessage> _outgoingController =
      StreamController<CoordinationMessage>();
  final StreamController<StartStreamMessage> _streamStartController =
      StreamController<StartStreamMessage>.broadcast();
  final StreamController<StopStreamMessage> _streamStopController =
      StreamController<StopStreamMessage>.broadcast();
  final StreamController<UserCoordinationMessage> _userMessageController =
      StreamController<UserCoordinationMessage>.broadcast();
  final StreamController<ConfigUpdateMessage> _configUpdateController =
      StreamController<ConfigUpdateMessage>.broadcast();

  Stream<CoordinationMessage> get outgoingMessages =>
      _outgoingController.stream;
  Stream<StartStreamMessage> get streamStartCommands =>
      _streamStartController.stream;
  Stream<StopStreamMessage> get streamStopCommands =>
      _streamStopController.stream;
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
          CoordinationMessageType.startStream,
          CoordinationMessageType.stopStream,
          CoordinationMessageType.userMessage,
          CoordinationMessageType.configUpdate,
        }.contains(type);
  }

  @override
  Future<void> handleMessage(CoordinationMessage message) async {
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
      case CoordinationMessageType.startStream:
        await _handleStartStream(message as StartStreamMessage);
        break;
      case CoordinationMessageType.stopStream:
        await _handleStopStream(message as StopStreamMessage);
        break;
      case CoordinationMessageType.userMessage:
        await _handleUserMessage(message as UserCoordinationMessage);
        break;
      case CoordinationMessageType.configUpdate:
        await _handleConfigUpdate(message as ConfigUpdateMessage);
        break;
      default:
        logger.warning(
          'Participant cannot handle message type: ${message.type}',
        );
    }
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    _outgoingController.add(message);
  }

  Future<void> _handleJoinAccept(JoinAcceptMessage message) async {
    if (message.acceptedNodeUId == thisNode.uId) {
      // We've been accepted!
      state.transitionTo(CoordinationPhase.ready);
      logger.info('Join accepted by coordinator');

      // Update our topology with the provided info
      for (final node in message.currentTopology) {
        state.addNode(node);
      }
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

  Future<void> _handleStartStream(StartStreamMessage message) async {
    logger.info('Received start stream command: ${message.streamName}');
    _streamStartController.add(message);
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

  void dispose() {
    _outgoingController.close();
    _streamStartController.close();
    _streamStopController.close();
    _userMessageController.close();
    _configUpdateController.close();
  }
}
