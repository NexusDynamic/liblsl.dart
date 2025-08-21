import 'dart:async';
import 'protocol.dart';
import '../session/coordination_session.dart';

/// Protocol for node-to-node coordination messages
abstract class CoordinationProtocol extends Protocol {
  /// Send a heartbeat to indicate this node is alive
  Future<void> sendHeartbeat();
  
  /// Send a coordination message to specific nodes or broadcast
  Future<void> sendMessage(CoordinationMessage message, {List<String>? targetNodes});
  
  /// Handle incoming coordination messages
  Future<void> handleMessage(CoordinationMessage message, String fromNodeId);
  
  /// Stream of incoming coordination messages
  Stream<IncomingCoordinationMessage> get messages;
}

/// Types of coordination messages
enum CoordinationMessageType {
  heartbeat,
  roleChange,
  topologyUpdate,
  nodeJoined,
  nodeLeft,
  streamRequest,
  streamResponse,
  error,
  custom,
}

/// Coordination message between nodes
class CoordinationMessage {
  final String messageId;
  final CoordinationMessageType type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? replyToMessageId;
  
  const CoordinationMessage({
    required this.messageId,
    required this.type,
    required this.payload,
    required this.timestamp,
    this.replyToMessageId,
  });
  
  factory CoordinationMessage.heartbeat(String nodeId) => CoordinationMessage(
    messageId: '${nodeId}_heartbeat_${DateTime.now().millisecondsSinceEpoch}',
    type: CoordinationMessageType.heartbeat,
    payload: {'nodeId': nodeId, 'timestamp': DateTime.now().toIso8601String()},
    timestamp: DateTime.now(),
  );
  
  factory CoordinationMessage.roleChange(String nodeId, NodeRole newRole, String reason) => CoordinationMessage(
    messageId: '${nodeId}_role_${DateTime.now().millisecondsSinceEpoch}',
    type: CoordinationMessageType.roleChange,
    payload: {
      'nodeId': nodeId,
      'newRole': newRole.name,
      'reason': reason,
    },
    timestamp: DateTime.now(),
  );
  
  factory CoordinationMessage.streamRequest(String requestingNodeId, Map<String, dynamic> streamConfig) => CoordinationMessage(
    messageId: '${requestingNodeId}_stream_req_${DateTime.now().millisecondsSinceEpoch}',
    type: CoordinationMessageType.streamRequest,
    payload: {
      'requestingNodeId': requestingNodeId,
      'streamConfig': streamConfig,
    },
    timestamp: DateTime.now(),
  );
}

/// Incoming coordination message with sender information
class IncomingCoordinationMessage {
  final CoordinationMessage message;
  final String fromNodeId;
  final DateTime receivedAt;
  
  const IncomingCoordinationMessage({
    required this.message,
    required this.fromNodeId,
    required this.receivedAt,
  });
}