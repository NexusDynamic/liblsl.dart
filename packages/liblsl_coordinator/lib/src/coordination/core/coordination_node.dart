import 'dart:async';
import 'package:meta/meta.dart';

import 'coordination_message.dart';

/// Core abstraction for a device participating in coordination
abstract class CoordinationNode {
  /// Unique identifier for this node
  String get nodeId;

  /// Human-readable name for this node
  String get nodeName;

  /// Current role of this node
  NodeRole get role;

  /// Whether this node is currently active
  bool get isActive;

  /// Stream of coordination events from this node
  Stream<CoordinationEvent> get eventStream;

  /// Initialize the coordination node
  Future<void> initialize();

  /// Join an existing coordination network or create a new one
  Future<void> join();

  /// Leave the coordination network
  Future<void> leave();

  /// Send a message to the network
  Future<void> sendMessage(CoordinationMessage message);

  /// Dispose resources
  Future<void> dispose();
}

/// Roles a node can have in the coordination network
enum NodeRole {
  /// Node is discovering the network
  discovering,

  /// Node is a participant (follower)
  participant,

  /// Node is the coordinator (leader)
  coordinator,

  /// Node is disconnected
  disconnected,
}

/// Base class for all coordination events
@immutable
abstract class CoordinationEvent {
  const CoordinationEvent();
}

/// Node joined the network
class NodeJoinedEvent extends CoordinationEvent {
  final String nodeId;
  final String nodeName;
  final DateTime timestamp;

  const NodeJoinedEvent(this.nodeId, this.nodeName, this.timestamp);
}

/// Node left the network
class NodeLeftEvent extends CoordinationEvent {
  final String nodeId;
  final DateTime timestamp;

  const NodeLeftEvent(this.nodeId, this.timestamp);
}

/// Network topology changed
class TopologyChangedEvent extends CoordinationEvent {
  final List<NetworkNode> nodes;
  final String? coordinatorId;

  const TopologyChangedEvent(this.nodes, this.coordinatorId);
}

/// Role of this node changed
class RoleChangedEvent extends CoordinationEvent {
  final NodeRole oldRole;
  final NodeRole newRole;

  const RoleChangedEvent(this.oldRole, this.newRole);
}

/// Custom application event
class ApplicationEvent extends CoordinationEvent {
  final String type;
  final Map<String, dynamic> data;

  const ApplicationEvent(this.type, this.data);
}

/// Represents a node in the network
@immutable
class NetworkNode {
  final String nodeId;
  final String nodeName;
  final NodeRole role;
  final DateTime lastSeen;
  final Map<String, dynamic> metadata;

  const NetworkNode({
    required this.nodeId,
    required this.nodeName,
    required this.role,
    required this.lastSeen,
    this.metadata = const {},
  });

  NetworkNode copyWith({
    String? nodeId,
    String? nodeName,
    NodeRole? role,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  }) {
    return NetworkNode(
      nodeId: nodeId ?? this.nodeId,
      nodeName: nodeName ?? this.nodeName,
      role: role ?? this.role,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nodeId': nodeId,
      'nodeName': nodeName,
      'role': role.toString(),
      'lastSeen': lastSeen.toIso8601String(),
      'metadata': metadata,
    };
  }

  NetworkNode.fromMap(Map<String, dynamic> map)
    : nodeId = map['nodeId'] as String,
      nodeName = map['nodeName'] as String,
      role = NodeRole.values.firstWhere(
        (e) => e.toString() == map['role'],
        orElse: () => NodeRole.disconnected,
      ),
      lastSeen = DateTime.parse(map['lastSeen'] as String),
      metadata = Map<String, dynamic>.from(map['metadata'] as Map);
}
