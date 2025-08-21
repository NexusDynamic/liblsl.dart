import 'dart:async';
import 'package:liblsl_coordinator/src/event.dart';

import '../session/coordination_session.dart';
import '../session/data_stream.dart';

/// Centralized state management for network topology and node information
abstract class NetworkState {
  /// Current network topology
  NetworkTopology get topology;

  /// Current role of this node
  NodeRole get role;

  /// List of all known nodes in the network
  List<NetworkNode> get nodes;

  /// This node's information
  NetworkNode get thisNode;

  /// Leader/server node (if any)
  NetworkNode? get leader;

  /// All active data streams
  List<DataStream> get activeStreams;

  /// Current session state
  SessionState get sessionState;

  /// Update the network topology
  Future<void> updateTopology(NetworkTopology newTopology);

  /// Update this node's role
  Future<void> updateRole(NodeRole newRole, String reason);

  /// Add or update a node in the network
  Future<void> updateNode(NetworkNode node);

  /// Remove a node from the network
  Future<void> removeNode(String nodeId);

  /// Add a data stream to tracking
  Future<void> addDataStream(DataStream stream);

  /// Remove a data stream from tracking
  Future<void> removeDataStream(String streamId);

  /// Update session state
  Future<void> updateSessionState(SessionState newState);

  /// Stream of state change events
  Stream<NetworkStateEvent> get stateChanges;
}

/// Generic network state events that any transport implementation would need
abstract class NetworkStateEvent extends AutoTimestampedEvent {
  NetworkStateEvent({String? eventId, super.timestamp})
    : super(
        eventId:
            eventId ??
            'network_state_event${timestamp ?? DateTime.now().microsecondsSinceEpoch}',
      );

  @override
  String toString() {
    return 'NetworkStateEvent(eventId: $eventId, timestamp: $timestamp)';
  }
}

class NetworkTopologyChanged extends NetworkStateEvent {
  final NetworkTopology oldTopology;
  final NetworkTopology newTopology;

  NetworkTopologyChanged(
    this.oldTopology,
    this.newTopology, {
    super.eventId = 'network_topology_changed',
  });
}

class NetworkRoleChanged extends NetworkStateEvent {
  final String nodeId;
  final NodeRole oldRole;
  final NodeRole newRole;
  final String reason;

  NetworkRoleChanged(this.nodeId, this.oldRole, this.newRole, this.reason);
}

class NodeAdded extends NetworkStateEvent {
  final NetworkNode node;

  NodeAdded(this.node);
}

class NodeUpdated extends NetworkStateEvent {
  final NetworkNode node;
  final NetworkNode? previousNode;

  NodeUpdated(this.node, [this.previousNode]);
}

class NodeRemoved extends NetworkStateEvent {
  final NetworkNode node;

  NodeRemoved(this.node);
}

class StreamStateChanged extends NetworkStateEvent {
  final String streamId;
  final String change;

  StreamStateChanged(this.streamId, this.change);
}

class SessionStateEvent extends NetworkStateEvent {
  final SessionState oldState;
  final SessionState newState;

  SessionStateEvent(this.oldState, this.newState);
}

/// Extension to add copyWith to NetworkNode
extension NetworkNodeExtension on NetworkNode {}

/// Immutable snapshot of network state at a point in time
class NetworkStateSnapshot {
  final NetworkTopology topology;
  final NodeRole role;
  final List<NetworkNode> nodes;
  final NetworkNode thisNode;
  final NetworkNode? leader;
  final List<DataStream> activeStreams;
  final SessionState sessionState;
  final DateTime timestamp;

  const NetworkStateSnapshot({
    required this.topology,
    required this.role,
    required this.nodes,
    required this.thisNode,
    this.leader,
    required this.activeStreams,
    required this.sessionState,
    required this.timestamp,
  });
}
