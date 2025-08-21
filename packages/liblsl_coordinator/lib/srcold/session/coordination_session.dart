import 'dart:async';
import 'package:liblsl_coordinator/src/event.dart';

import 'stream_config.dart';
import 'data_stream.dart';

/// Represents the overall coordination session managing network topology and data streams
abstract class CoordinationSession {
  /// Unique identifier for this session
  String get sessionId;

  /// Current state of the session
  SessionState get state;

  /// Initialize and join the coordination network
  Future<void> join();

  /// Leave the coordination network and cleanup
  Future<void> leave();

  /// Create a new data stream within this session
  Future<DataStream> createDataStream(StreamConfig config);

  /// Destroy a data stream
  Future<void> destroyDataStream(String streamId);

  /// Get all active data streams
  List<DataStream> get dataStreams;

  /// Get a specific data stream by ID
  DataStream? getDataStream(String streamId);

  /// Stream of session-level events (node joined, left, role changes, etc.)
  Stream<SessionEvent> get events;

  /// Current network topology
  NetworkTopology get topology;

  /// Current role of this node
  NodeRole get role;

  /// List of all nodes in the network
  List<NetworkNode> get nodes;
}

/// Possible states of a coordination session
enum SessionState { disconnected, discovering, joining, active, leaving, error }

/// Network topology types
enum NetworkTopology { peer2peer, hierarchical, hybrid }

/// Roles a node can have in the network
enum NodeRole { discovering, peer, client, server, leader, coordinator, custom }

/// Represents a network node
class NetworkNode {
  final String nodeId;
  final String nodeName;
  final NodeRole role;
  final Map<String, dynamic> metadata;
  final DateTime lastSeen;

  const NetworkNode({
    required this.nodeId,
    required this.nodeName,
    required this.role,
    this.metadata = const {},
    required this.lastSeen,
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
}

/// Events that can occur at the session level
sealed class SessionEvent extends TimestampedEvent {
  final String sessionId;

  const SessionEvent(this.sessionId, DateTime timestamp)
    : super(eventId: 'session_event_$sessionId', timestamp: timestamp);
}

class SessionStarted extends SessionEvent {
  SessionStarted(String sessionId) : super(sessionId, DateTime.now());
}

class SessionStopped extends SessionEvent {
  SessionStopped(String sessionId) : super(sessionId, DateTime.now());
}

class NodeJoined extends SessionEvent {
  final NetworkNode node;

  NodeJoined(String sessionId, this.node) : super(sessionId, DateTime.now());
}

class NodeLeft extends SessionEvent {
  final NetworkNode node;

  NodeLeft(String sessionId, this.node) : super(sessionId, DateTime.now());
}

class RoleChanged extends SessionEvent {
  final NodeRole oldRole;
  final NodeRole newRole;
  final String reason;

  RoleChanged(String sessionId, this.oldRole, this.newRole, this.reason)
    : super(sessionId, DateTime.now());
}

class TopologyChanged extends SessionEvent {
  final NetworkTopology oldTopology;
  final NetworkTopology newTopology;

  TopologyChanged(String sessionId, this.oldTopology, this.newTopology)
    : super(sessionId, DateTime.now());
}

class SessionStateChanged extends SessionEvent {
  final SessionState oldState;
  final SessionState newState;
  final String? reason;

  SessionStateChanged(
    String sessionId,
    this.oldState,
    this.newState, [
    this.reason,
  ]) : super(sessionId, DateTime.now());
}

class StreamAdded extends SessionEvent {
  final String streamId;
  final Map<String, dynamic> streamConfig;

  StreamAdded(String sessionId, this.streamId, this.streamConfig)
    : super(sessionId, DateTime.now());
}

class StreamRemoved extends SessionEvent {
  final String streamId;
  final String? reason;

  StreamRemoved(String sessionId, this.streamId, [this.reason])
    : super(sessionId, DateTime.now());
}
