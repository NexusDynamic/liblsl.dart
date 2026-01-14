import 'dart:async';
import 'package:liblsl_coordinator/framework.dart';

/// Represents the current state of coordination
enum CoordinationPhase {
  /// Initial state, not yet started
  idle,

  /// Discovering existing coordinators
  discovering,

  /// Running coordinator election
  electing,

  /// Established as coordinator or participant
  established,

  /// Accepting new nodes (coordinator only)
  accepting,

  /// Ready for data operations
  ready,

  /// Actively coordinating data streams
  active,

  /// Paused/suspended
  paused,

  /// Shutting down
  disposing,
}

/// Internal coordination state with clear phase management.
///
/// Emits [ControllerEvent]s for state changes through a single event stream.
class CoordinationState {
  CoordinationPhase _phase = CoordinationPhase.idle;
  bool _isCoordinator = false;
  String? _coordinatorUId;
  final List<Node> _connectedNodes = [];
  final Map<String, DateTime> _lastHeartbeats = {};

  /// Single event stream for all state changes.
  final StreamController<ControllerEvent> _eventController =
      StreamController<ControllerEvent>.broadcast();

  CoordinationPhase get phase => _phase;
  bool get isCoordinator => _isCoordinator;
  String? get coordinatorUId => _coordinatorUId;
  List<Node> get connectedNodes => List.unmodifiable(_connectedNodes);
  List<Node> get connectedParticipantNodes => _connectedNodes
      .where((n) => n.role == NodeCapability.participant.toString())
      .toList();

  /// Single event stream for all state-related events.
  Stream<ControllerEvent> get events => _eventController.stream;

  bool get isEstablished =>
      _phase == CoordinationPhase.established ||
      _phase == CoordinationPhase.accepting ||
      _phase == CoordinationPhase.ready ||
      _phase == CoordinationPhase.active;

  bool get canAcceptNodes =>
      _isCoordinator &&
      (_phase == CoordinationPhase.accepting ||
          _phase == CoordinationPhase.ready);

  void transitionTo(CoordinationPhase newPhase) {
    if (_phase != newPhase) {
      final oldPhase = _phase;
      _phase = newPhase;
      logger.info('Coordination phase: $oldPhase -> $newPhase');
      _eventController.add(PhaseChangedEvent(
        phase: newPhase,
        fromNodeUId: _coordinatorUId ?? '',
      ));
    }
  }

  void becomeCoordinator(String coordinatorUId) {
    _isCoordinator = true;
    _coordinatorUId = coordinatorUId;
    transitionTo(CoordinationPhase.established);
  }

  void becomeParticipant([String? coordinatorUId]) {
    _isCoordinator = false;
    _coordinatorUId = coordinatorUId;
    transitionTo(CoordinationPhase.established);
  }

  void addNode(Node node) {
    if (!_connectedNodes.any((n) => n.uId == node.uId)) {
      _connectedNodes.add(node);
      _lastHeartbeats[node.uId] = DateTime.now();
      _eventController.add(NodeJoinedEvent(
        node: node,
        fromNodeUId: node.uId,
      ));
    } else {
      // Update existing node info
      final index = _connectedNodes.indexWhere((n) => n.uId == node.uId);
      _connectedNodes[index] = node;
    }
  }

  void removeNode(String nodeUId) {
    final node = _connectedNodes.where((n) => n.uId == nodeUId).firstOrNull;
    if (node != null) {
      _connectedNodes.removeWhere((n) => n.uId == nodeUId);
      _lastHeartbeats.remove(nodeUId);
      _eventController.add(NodeLeftEvent(
        node: node,
        fromNodeUId: nodeUId,
      ));
    }
  }

  void updateNodeHeartbeat(String nodeUId) {
    logger.finest('Heartbeat received from $nodeUId');
    _lastHeartbeats[nodeUId] = DateTime.now();
  }

  List<String> getStaleNodes(Duration timeout) {
    logger.finest(
      'Checking for stale nodes with timeout: ${timeout.inSeconds}s, nodes: $_lastHeartbeats',
    );
    final cutoff = DateTime.now().subtract(timeout);
    return _lastHeartbeats.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList();
  }

  void dispose() {
    _eventController.close();
  }
}
