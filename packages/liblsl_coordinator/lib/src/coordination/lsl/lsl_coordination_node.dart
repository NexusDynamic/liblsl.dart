import 'dart:async';
import 'dart:math';
import 'package:liblsl/lsl.dart';

import '../core/coordination_config.dart';
import '../core/coordination_node.dart';
import '../core/coordination_message.dart';
import '../core/leader_election.dart';
import 'lsl_transport.dart';

/// LSL-based implementation of CoordinationNode
class LSLCoordinationNode implements CoordinationNode {
  final String _nodeId;
  final String _nodeName;
  final CoordinationConfig _config;
  final LeaderElectionStrategy _leaderElection;
  final LSLNetworkTransport _transport;
  final LSLApiConfig _lslApiConfig;

  NodeRole _role = NodeRole.discovering;
  final Map<String, NetworkNode> _knownNodes = {};
  String? _coordinatorId;

  final StreamController<CoordinationEvent> _eventController =
      StreamController<CoordinationEvent>.broadcast();

  Timer? _discoveryTimer;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  bool _isActive = false;

  LSLCoordinationNode({
    required String nodeId,
    required String nodeName,
    required String streamName,
    CoordinationConfig? config,
    LSLApiConfig? lslApiConfig,
    LeaderElectionStrategy? leaderElection,
  }) : _nodeId = nodeId,
       _nodeName = nodeName,
       _config = config ?? const CoordinationConfig(),
       _leaderElection = leaderElection ?? FirstNodeLeaderElection(),
       _transport = LSLNetworkTransport(streamName: streamName, nodeId: nodeId),
       _lslApiConfig = lslApiConfig ?? LSLApiConfig();

  @override
  String get nodeId => _nodeId;

  @override
  String get nodeName => _nodeName;

  @override
  NodeRole get role => _role;

  @override
  bool get isActive => _isActive;

  @override
  Stream<CoordinationEvent> get eventStream => _eventController.stream;

  /// Current coordinator ID
  String? get coordinatorId => _coordinatorId;

  /// List of known nodes
  List<NetworkNode> get knownNodes => _knownNodes.values.toList();

  /// Wait for this node to reach a specific role
  Future<void> waitForRole(NodeRole targetRole, {Duration? timeout}) async {
    if (_role == targetRole) return;

    final completer = Completer<void>();
    late StreamSubscription subscription;

    subscription = eventStream.listen((event) {
      if (event is RoleChangedEvent && event.newRole == targetRole) {
        subscription.cancel();
        completer.complete();
      }
    });

    try {
      if (timeout != null) {
        await completer.future.timeout(timeout);
      } else {
        await completer.future;
      }
    } catch (e) {
      subscription.cancel();
      rethrow;
    }
  }

  /// Wait for a specific number of nodes to be present in the network
  Future<List<NetworkNode>> waitForNodes(
    int minNodes, {
    Duration? timeout,
  }) async {
    if (_knownNodes.length >= minNodes) {
      return _knownNodes.values.toList();
    }

    final completer = Completer<List<NetworkNode>>();
    late StreamSubscription subscription;

    subscription = eventStream.listen((event) {
      if (event is TopologyChangedEvent && event.nodes.length >= minNodes) {
        subscription.cancel();
        completer.complete(event.nodes);
      }
    });

    try {
      if (timeout != null) {
        return await completer.future.timeout(timeout);
      } else {
        return await completer.future;
      }
    } catch (e) {
      subscription.cancel();
      rethrow;
    }
  }

  @override
  Future<void> initialize() async {
    LSL.setConfigContent(_lslApiConfig);
    await _transport.initialize();

    // Listen for incoming messages
    _transport.messageStream.listen(_handleMessage);

    _isActive = true;
  }

  @override
  Future<void> join() async {
    if (!_isActive) {
      throw StateError('Node not initialized');
    }

    _role = NodeRole.discovering;
    _emitEvent(RoleChangedEvent(NodeRole.disconnected, _role));

    // Start discovery process
    _startDiscovery();

    // Start cleanup timer
    _startCleanupTimer();
  }

  @override
  Future<void> leave() async {
    _stopAllTimers();

    if (_role == NodeRole.coordinator) {
      // TODO: Handle coordinator handoff
    }

    _role = NodeRole.disconnected;
    _knownNodes.clear();
    _coordinatorId = null;

    _emitEvent(RoleChangedEvent(_role, NodeRole.disconnected));
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    await _transport.sendMessage(message);
  }

  /// Send an application-specific message
  Future<void> sendApplicationMessage(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final message = ApplicationMessage(
      messageId: _generateMessageId(),
      senderId: _nodeId,
      timestamp: DateTime.now(),
      applicationType: type,
      payload: payload,
    );

    await sendMessage(message);
  }

  void _handleMessage(CoordinationMessage message) {
    // Ignore our own messages unless configured to receive them
    if (!_config.receiveOwnMessages && message.senderId == _nodeId) {
      return;
    }

    switch (message) {
      case DiscoveryMessage():
        _handleDiscoveryMessage(message);
        break;
      case JoinRequestMessage():
        _handleJoinRequestMessage(message);
        break;
      case JoinResponseMessage():
        _handleJoinResponseMessage(message);
        break;
      case HeartbeatMessage():
        _handleHeartbeatMessage(message);
        break;
      case TopologyUpdateMessage():
        _handleTopologyUpdateMessage(message);
        break;
      case ApplicationMessage():
        _handleApplicationMessage(message);
        break;
    }
  }

  void _handleDiscoveryMessage(DiscoveryMessage message) {
    _updateKnownNode(message.senderId, message.nodeName, message.role);

    if (message.role == NodeRole.coordinator) {
      _coordinatorId = message.senderId;

      if (_role == NodeRole.discovering) {
        // Send join request
        _sendJoinRequest();
      }
    }
  }

  void _handleJoinRequestMessage(JoinRequestMessage message) {
    if (_role == NodeRole.coordinator) {
      _updateKnownNode(
        message.senderId,
        message.nodeName,
        NodeRole.participant,
      );

      // Send join response
      final response = JoinResponseMessage(
        messageId: _generateMessageId(),
        senderId: _nodeId,
        timestamp: DateTime.now(),
        accepted: _knownNodes.length < _config.maxNodes,
        currentNodes: _knownNodes.values.toList(),
      );

      _transport.sendMessage(response);

      // Broadcast topology update
      _broadcastTopologyUpdate();

      _emitEvent(
        NodeJoinedEvent(message.senderId, message.nodeName, DateTime.now()),
      );
    }
  }

  void _handleJoinResponseMessage(JoinResponseMessage message) {
    if (message.accepted && _role == NodeRole.discovering) {
      _role = NodeRole.participant;
      _coordinatorId = message.senderId;

      // Update known nodes
      for (final node in message.currentNodes) {
        _knownNodes[node.nodeId] = node;
      }

      _stopDiscovery();
      _startHeartbeat();

      _emitEvent(RoleChangedEvent(NodeRole.discovering, _role));
      _emitEvent(
        TopologyChangedEvent(_knownNodes.values.toList(), _coordinatorId),
      );
    }
  }

  void _handleHeartbeatMessage(HeartbeatMessage message) {
    _updateKnownNode(message.senderId, null, null);
  }

  void _handleTopologyUpdateMessage(TopologyUpdateMessage message) {
    if (message.senderId == _coordinatorId) {
      _knownNodes.clear();
      for (final node in message.nodes) {
        _knownNodes[node.nodeId] = node;
      }

      _emitEvent(
        TopologyChangedEvent(_knownNodes.values.toList(), _coordinatorId),
      );
    }
  }

  void _handleApplicationMessage(ApplicationMessage message) {
    _emitEvent(ApplicationEvent(message.applicationType, message.payload));
  }

  void _updateKnownNode(String nodeId, String? nodeName, NodeRole? role) {
    final existing = _knownNodes[nodeId];
    final updated = NetworkNode(
      nodeId: nodeId,
      nodeName: nodeName ?? existing?.nodeName ?? 'Unknown',
      role: role ?? existing?.role ?? NodeRole.participant,
      lastSeen: DateTime.now(),
      metadata: existing?.metadata ?? {},
    );

    _knownNodes[nodeId] = updated;
  }

  void _startDiscovery() {
    _discoveryTimer = Timer.periodic(
      Duration(milliseconds: (_config.discoveryInterval * 1000).round()),
      (_) => _sendDiscoveryMessage(),
    );

    // Send initial discovery immediately
    _sendDiscoveryMessage();

    // Check if we should become coordinator
    Future.delayed(Duration(seconds: _config.joinTimeout.round()), () {
      if (_role == NodeRole.discovering && _config.autoPromote) {
        _becomeCoordinator();
      }
    });
  }

  void _stopDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: (_config.heartbeatInterval * 1000).round()),
      (_) => _sendHeartbeat(),
    );
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _cleanupStaleNodes();
    });
  }

  void _stopAllTimers() {
    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _discoveryTimer = null;
    _heartbeatTimer = null;
    _cleanupTimer = null;
  }

  void _sendDiscoveryMessage() {
    final message = DiscoveryMessage(
      messageId: _generateMessageId(),
      senderId: _nodeId,
      timestamp: DateTime.now(),
      nodeName: _nodeName,
      role: _role,
      capabilities: _config.capabilities,
    );

    _transport.sendMessage(message);
  }

  void _sendJoinRequest() {
    final message = JoinRequestMessage(
      messageId: _generateMessageId(),
      senderId: _nodeId,
      timestamp: DateTime.now(),
      nodeName: _nodeName,
      capabilities: _config.capabilities,
    );

    _transport.sendMessage(message);
  }

  void _sendHeartbeat() {
    final message = HeartbeatMessage(
      messageId: _generateMessageId(),
      senderId: _nodeId,
      timestamp: DateTime.now(),
      status: {'role': _role.index},
    );

    _transport.sendMessage(message);
  }

  void _becomeCoordinator() {
    final oldRole = _role;
    _role = NodeRole.coordinator;
    _coordinatorId = _nodeId;

    // Add self to known nodes
    _knownNodes[_nodeId] = NetworkNode(
      nodeId: _nodeId,
      nodeName: _nodeName,
      role: _role,
      lastSeen: DateTime.now(),
      metadata: _config.capabilities,
    );

    _stopDiscovery();
    _startHeartbeat();

    _emitEvent(RoleChangedEvent(oldRole, _role));
    _emitEvent(
      TopologyChangedEvent(_knownNodes.values.toList(), _coordinatorId),
    );
  }

  void _broadcastTopologyUpdate() {
    final message = TopologyUpdateMessage(
      messageId: _generateMessageId(),
      senderId: _nodeId,
      timestamp: DateTime.now(),
      nodes: _knownNodes.values.toList(),
    );

    _transport.sendMessage(message);
  }

  void _cleanupStaleNodes() {
    final now = DateTime.now();
    final timeout = Duration(seconds: _config.nodeTimeout.round());

    final staleNodes =
        _knownNodes.values
            .where(
              (node) =>
                  node.nodeId != _nodeId && // Exclude self-node from cleanup
                  now.difference(node.lastSeen) > timeout,
            )
            .toList();

    for (final staleNode in staleNodes) {
      _knownNodes.remove(staleNode.nodeId);
      _emitEvent(NodeLeftEvent(staleNode.nodeId, now));

      // Handle coordinator failure
      if (staleNode.nodeId == _coordinatorId) {
        _handleCoordinatorFailure();
      }
    }

    if (staleNodes.isNotEmpty && _role == NodeRole.coordinator) {
      _broadcastTopologyUpdate();
    }
  }

  void _handleCoordinatorFailure() {
    _coordinatorId = null;

    // Check if we should become the new coordinator
    final candidates =
        _knownNodes.values.toList()..add(
          NetworkNode(
            nodeId: _nodeId,
            nodeName: _nodeName,
            role: _role,
            lastSeen: DateTime.now(),
            metadata: _config.capabilities,
          ),
        );

    if (_leaderElection.shouldBecomeLeader(_nodeId, candidates, {})) {
      _becomeCoordinator();
    } else {
      // Go back to discovering
      _role = NodeRole.discovering;
      _startDiscovery();
      _emitEvent(RoleChangedEvent(NodeRole.participant, _role));
    }
  }

  void _emitEvent(CoordinationEvent event) {
    _eventController.add(event);
  }

  String _generateMessageId() {
    return '${_nodeId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
  }

  @override
  Future<void> dispose() async {
    _stopAllTimers();
    await _transport.dispose();
    await _eventController.close();
    _isActive = false;
  }
}
