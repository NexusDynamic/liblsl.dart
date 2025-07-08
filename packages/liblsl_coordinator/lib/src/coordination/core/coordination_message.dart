import 'package:meta/meta.dart';

import 'coordination_node.dart';

/// Base class for coordination messages
@immutable
abstract class CoordinationMessage {
  /// Unique message identifier
  final String messageId;

  /// ID of the sender node
  final String senderId;

  /// Timestamp when message was created
  final DateTime timestamp;

  /// Message type identifier
  String get messageType;

  const CoordinationMessage({
    required this.messageId,
    required this.senderId,
    required this.timestamp,
  });

  /// Serialize message to a map
  Map<String, dynamic> toMap();

  /// Create message from a map
  static CoordinationMessage fromMap(Map<String, dynamic> map) {
    final messageType = map['messageType'] as String;

    switch (messageType) {
      case 'discovery':
        return DiscoveryMessage.fromMap(map);
      case 'join_request':
        return JoinRequestMessage.fromMap(map);
      case 'join_response':
        return JoinResponseMessage.fromMap(map);
      case 'heartbeat':
        return HeartbeatMessage.fromMap(map);
      case 'topology_update':
        return TopologyUpdateMessage.fromMap(map);
      case 'application':
        return ApplicationMessage.fromMap(map);
      default:
        throw UnsupportedError('Unknown message type: $messageType');
    }
  }
}

/// Discovery announcement message
class DiscoveryMessage extends CoordinationMessage {
  final String nodeName;
  final NodeRole role;
  final Map<String, dynamic> capabilities;

  const DiscoveryMessage({
    required super.messageId,
    required super.senderId,
    required super.timestamp,
    required this.nodeName,
    required this.role,
    this.capabilities = const {},
  });

  @override
  String get messageType => 'discovery';

  @override
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'messageType': messageType,
      'nodeName': nodeName,
      'role': role.index,
      'capabilities': capabilities,
    };
  }

  static DiscoveryMessage fromMap(Map<String, dynamic> map) {
    return DiscoveryMessage(
      messageId: map['messageId'],
      senderId: map['senderId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      nodeName: map['nodeName'],
      role: NodeRole.values[map['role']],
      capabilities: Map<String, dynamic>.from(map['capabilities'] ?? {}),
    );
  }
}

/// Request to join the network
class JoinRequestMessage extends CoordinationMessage {
  final String nodeName;
  final Map<String, dynamic> capabilities;

  const JoinRequestMessage({
    required super.messageId,
    required super.senderId,
    required super.timestamp,
    required this.nodeName,
    this.capabilities = const {},
  });

  @override
  String get messageType => 'join_request';

  @override
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'messageType': messageType,
      'nodeName': nodeName,
      'capabilities': capabilities,
    };
  }

  static JoinRequestMessage fromMap(Map<String, dynamic> map) {
    return JoinRequestMessage(
      messageId: map['messageId'],
      senderId: map['senderId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      nodeName: map['nodeName'],
      capabilities: Map<String, dynamic>.from(map['capabilities'] ?? {}),
    );
  }
}

/// Response to join request
class JoinResponseMessage extends CoordinationMessage {
  final bool accepted;
  final String? reason;
  final List<NetworkNode> currentNodes;

  const JoinResponseMessage({
    required super.messageId,
    required super.senderId,
    required super.timestamp,
    required this.accepted,
    this.reason,
    this.currentNodes = const [],
  });

  @override
  String get messageType => 'join_response';

  @override
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'messageType': messageType,
      'accepted': accepted,
      'reason': reason,
      'currentNodes':
          currentNodes
              .map(
                (n) => {
                  'nodeId': n.nodeId,
                  'nodeName': n.nodeName,
                  'role': n.role.index,
                  'lastSeen': n.lastSeen.millisecondsSinceEpoch,
                  'metadata': n.metadata,
                },
              )
              .toList(),
    };
  }

  static JoinResponseMessage fromMap(Map<String, dynamic> map) {
    final nodesList = map['currentNodes'] as List? ?? [];
    final nodes =
        nodesList
            .map(
              (nodeMap) => NetworkNode(
                nodeId: nodeMap['nodeId'],
                nodeName: nodeMap['nodeName'],
                role: NodeRole.values[nodeMap['role']],
                lastSeen: DateTime.fromMillisecondsSinceEpoch(
                  nodeMap['lastSeen'],
                ),
                metadata: Map<String, dynamic>.from(nodeMap['metadata'] ?? {}),
              ),
            )
            .toList();

    return JoinResponseMessage(
      messageId: map['messageId'],
      senderId: map['senderId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      accepted: map['accepted'],
      reason: map['reason'],
      currentNodes: nodes,
    );
  }
}

/// Periodic heartbeat message
class HeartbeatMessage extends CoordinationMessage {
  final Map<String, dynamic> status;

  const HeartbeatMessage({
    required super.messageId,
    required super.senderId,
    required super.timestamp,
    this.status = const {},
  });

  @override
  String get messageType => 'heartbeat';

  @override
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'messageType': messageType,
      'status': status,
    };
  }

  static HeartbeatMessage fromMap(Map<String, dynamic> map) {
    return HeartbeatMessage(
      messageId: map['messageId'],
      senderId: map['senderId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      status: Map<String, dynamic>.from(map['status'] ?? {}),
    );
  }
}

/// Network topology update
class TopologyUpdateMessage extends CoordinationMessage {
  final List<NetworkNode> nodes;

  const TopologyUpdateMessage({
    required super.messageId,
    required super.senderId,
    required super.timestamp,
    required this.nodes,
  });

  @override
  String get messageType => 'topology_update';

  @override
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'messageType': messageType,
      'nodes':
          nodes
              .map(
                (n) => {
                  'nodeId': n.nodeId,
                  'nodeName': n.nodeName,
                  'role': n.role.index,
                  'lastSeen': n.lastSeen.millisecondsSinceEpoch,
                  'metadata': n.metadata,
                },
              )
              .toList(),
    };
  }

  static TopologyUpdateMessage fromMap(Map<String, dynamic> map) {
    final nodesList = map['nodes'] as List? ?? [];
    final nodes =
        nodesList
            .map(
              (nodeMap) => NetworkNode(
                nodeId: nodeMap['nodeId'],
                nodeName: nodeMap['nodeName'],
                role: NodeRole.values[nodeMap['role']],
                lastSeen: DateTime.fromMillisecondsSinceEpoch(
                  nodeMap['lastSeen'],
                ),
                metadata: Map<String, dynamic>.from(nodeMap['metadata'] ?? {}),
              ),
            )
            .toList();

    return TopologyUpdateMessage(
      messageId: map['messageId'],
      senderId: map['senderId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      nodes: nodes,
    );
  }
}

/// Application-specific message
class ApplicationMessage extends CoordinationMessage {
  final String applicationType;
  final Map<String, dynamic> payload;

  const ApplicationMessage({
    required super.messageId,
    required super.senderId,
    required super.timestamp,
    required this.applicationType,
    required this.payload,
  });

  @override
  String get messageType => 'application';

  @override
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'messageType': messageType,
      'applicationType': applicationType,
      'payload': payload,
    };
  }

  static ApplicationMessage fromMap(Map<String, dynamic> map) {
    return ApplicationMessage(
      messageId: map['messageId'],
      senderId: map['senderId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      applicationType: map['applicationType'],
      payload: Map<String, dynamic>.from(map['payload'] ?? {}),
    );
  }
}
