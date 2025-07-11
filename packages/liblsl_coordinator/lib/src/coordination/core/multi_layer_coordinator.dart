import 'dart:async';
import 'package:liblsl/lsl.dart';

import 'coordination_node.dart';
import 'coordination_message.dart';
import 'coordination_config.dart';
import 'stream_layer_config.dart';
import 'coordination_layer.dart';
import '../lsl/lsl_coordination_node.dart';
import '../lsl/stream_layer_manager.dart';

/// Enhanced coordination node that supports multi-layer streaming
class MultiLayerCoordinator extends CoordinationNode {
  final String _nodeId;
  final String _nodeName;
  final ProtocolConfig _protocolConfig;
  final CoordinationConfig _coordinationConfig;
  final LSLApiConfig? _lslApiConfig;

  NodeRole _role = NodeRole.discovering;
  bool _isActive = false;

  final StreamController<CoordinationEvent> _eventController =
      StreamController.broadcast();
  final Map<String, StreamLayerManager> _layerManagers = {};
  final LayerCollection _layers = LayerCollection();
  final Map<String, NetworkNode> _knownNodes = {};

  LSLCoordinationNode? _coordinationNode;
  // _discoveryTimer removed - no longer needed
  Timer? _heartbeatTimer;

  String? _coordinatorId;

  MultiLayerCoordinator({
    required String nodeId,
    required String nodeName,
    required ProtocolConfig protocolConfig,
    CoordinationConfig coordinationConfig = const CoordinationConfig(),
    LSLApiConfig? lslApiConfig,
  }) : _nodeId = nodeId,
       _nodeName = nodeName,
       _protocolConfig = protocolConfig,
       _coordinationConfig = coordinationConfig,
       _lslApiConfig = lslApiConfig;

  @override
  String get nodeId => _nodeId;

  @override
  String get nodeName => _nodeName;

  @override
  NodeRole get role => _coordinationNode?.role ?? _role;

  @override
  bool get isActive => _isActive;

  @override
  Stream<CoordinationEvent> get eventStream => _eventController.stream;

  /// Get the current protocol configuration
  ProtocolConfig get protocolConfig => _protocolConfig;

  /// Get the current coordinator ID
  String? get coordinatorId => _coordinatorId;

  /// Get all known nodes
  List<NetworkNode> get knownNodes => _knownNodes.values.toList();

  /// Get all layers
  LayerCollection get layers => _layers;

  /// Get a specific layer
  CoordinationLayer? getLayer(String layerId) => _layers[layerId];

  /// Get a specific layer manager (for advanced use)
  StreamLayerManager? getLayerManager(String layerId) =>
      _layerManagers[layerId];

  /// Get all layer managers (for advanced use)
  Map<String, StreamLayerManager> get layerManagers =>
      Map.unmodifiable(_layerManagers);

  @override
  Future<void> initialize() async {
    if (_isActive) return;

    // Create coordination node for the coordination layer
    final coordinationLayer = _protocolConfig.getLayer('coordination');
    if (coordinationLayer == null) {
      throw StateError('Protocol must have a coordination layer');
    }

    _coordinationNode = LSLCoordinationNode(
      nodeId: _nodeId,
      nodeName: _nodeName,
      streamName: coordinationLayer.streamConfig.streamName,
      config: _coordinationConfig,
      lslApiConfig: _lslApiConfig,
    );

    // Listen to coordination events
    _coordinationNode!.eventStream.listen(_handleCoordinationEvent);

    // Initialize coordination node
    await _coordinationNode!.initialize();

    // Create layer definitions immediately based on protocol config
    _createLayerDefinitions();

    _isActive = true;
    // Don't start discovery here - it should be done in join()
  }

  @override
  Future<void> join() async {
    if (!_isActive) {
      throw StateError('Node must be initialized before joining');
    }

    await _coordinationNode!.join();

    // Start heartbeat timer
    _heartbeatTimer = Timer.periodic(
      Duration(
        milliseconds: (_coordinationConfig.heartbeatInterval * 1000).round(),
      ),
      _sendHeartbeat,
    );
  }

  @override
  Future<void> leave() async {
    if (!_isActive) return;

    // _discoveryTimer?.cancel(); // No longer needed
    _heartbeatTimer?.cancel();

    // Stop all layers
    await _layers.dispose();
    _layerManagers.clear();

    await _coordinationNode?.leave();

    _role = NodeRole.disconnected;
    _isActive = false;

    _eventController.add(RoleChangedEvent(_role, NodeRole.disconnected));
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    await _coordinationNode?.sendMessage(message);
  }

  /// Send an application-level message through the coordination layer
  Future<void> sendApplicationMessage(
    String type,
    Map<String, dynamic> data,
  ) async {
    await _coordinationNode?.sendApplicationMessage(type, data);
  }

  /// Set up the protocol and create stream layers
  Future<void> setupProtocol() async {
    // Only coordinators should call this method
    if (role != NodeRole.coordinator) {
      throw StateError('Only coordinator can setup protocol');
    }

    // Send protocol configuration to all participants
    await sendApplicationMessage('protocol_config', _protocolConfig.toMap());

    // Create stream layers for coordinator
    await _createStreamLayers();

    // Notify that protocol is ready
    await sendApplicationMessage('protocol_ready', {
      'protocolId': _protocolConfig.protocolId,
      'layers': _protocolConfig.layers.map((l) => l.layerId).toList(),
    });
  }

  /// Create layer definitions based on protocol configuration (called during initialize)
  void _createLayerDefinitions() {
    for (final layerConfig in _protocolConfig.layers) {
      if (layerConfig.layerId == 'coordination') {
        // Coordination layer uses a wrapper that delegates to the coordination node
        final layer = _createCoordinationLayerWrapper(layerConfig);
        _layers.add(layer);
      } else {
        // For other layers, create placeholder layers that will be activated later
        final layer = _PlaceholderLayer(layerConfig);
        _layers.add(layer);
      }
    }
  }

  /// Activate stream layers with actual LSL connections (called when becoming coordinator)
  Future<void> _createStreamLayers() async {
    for (final layerConfig in _protocolConfig.layers) {
      // Skip coordination layer as it's already handled
      if (layerConfig.layerId == 'coordination') continue;

      final manager = StreamLayerManager(
        layerId: layerConfig.layerId,
        nodeId: _nodeId,
        layerConfig: layerConfig,
        isCoordinator: _role == NodeRole.coordinator,
        knownNodes: _knownNodes.values.toList(),
      );

      await manager.initialize();
      _layerManagers[layerConfig.layerId] = manager;

      // Replace placeholder layer with active layer
      _layers.remove(layerConfig.layerId);
      final layer = CoordinationLayerImpl(
        layerId: layerConfig.layerId,
        config: layerConfig,
        manager: manager,
      );
      _layers.add(layer);

      // Listen to layer events
      manager.eventStream.listen((event) {
        _eventController.add(event);
      });
    }
  }

  /// Create a coordination layer wrapper that delegates to the coordination node
  CoordinationLayer _createCoordinationLayerWrapper(StreamLayerConfig config) {
    return _CoordinationNodeWrapper(
      layerId: config.layerId,
      config: config,
      coordinationNode: _coordinationNode!,
    );
  }

  // Removed _startDiscovery method that was incorrectly calling join() repeatedly

  void _sendHeartbeat(Timer timer) async {
    if (!_isActive) {
      timer.cancel();
      return;
    }

    await sendApplicationMessage('heartbeat', {
      'nodeId': _nodeId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'role': _role.index,
    });
  }

  void _handleCoordinationEvent(CoordinationEvent event) {
    if (event is RoleChangedEvent) {
      _role = event.newRole;

      if (_role == NodeRole.coordinator) {
        _coordinatorId = _nodeId;
        // Set up protocol when becoming coordinator
        unawaited(setupProtocol());
      }
    } else if (event is NodeJoinedEvent) {
      final joinEvent = event;
      _knownNodes[joinEvent.nodeId] = NetworkNode(
        nodeId: joinEvent.nodeId,
        nodeName: joinEvent.nodeName,
        role: NodeRole.participant,
        lastSeen: joinEvent.timestamp,
      );

      // Update all layer managers with new node
      for (final manager in _layerManagers.values) {
        manager.updateKnownNodes(_knownNodes.values.toList());
      }
    } else if (event is NodeLeftEvent) {
      final leftEvent = event;
      _knownNodes.remove(leftEvent.nodeId);

      // Update all layer managers
      for (final manager in _layerManagers.values) {
        manager.updateKnownNodes(_knownNodes.values.toList());
      }
    } else if (event is ApplicationEvent) {
      final appEvent = event;
      _handleApplicationEvent(appEvent);
    }

    // Forward all events to our listeners
    _eventController.add(event);
  }

  void _handleApplicationEvent(ApplicationEvent event) async {
    switch (event.type) {
      case 'protocol_config':
        // Participant received protocol configuration
        if (_role == NodeRole.participant) {
          final protocolData = event.data;
          final receivedConfig = ProtocolConfig.fromMap(protocolData);

          // Validate protocol matches
          if (receivedConfig.protocolId != _protocolConfig.protocolId) {
            throw StateError(
              'Protocol mismatch: expected ${_protocolConfig.protocolId}, got ${receivedConfig.protocolId}',
            );
          }

          // Create stream layers as participant
          await _createStreamLayers();
        }
        break;

      case 'protocol_ready':
        // Protocol is ready, all nodes can start using layers
        _eventController.add(ApplicationEvent('protocol_ready', event.data));
        break;

      case 'heartbeat':
        // Update last seen time for node
        final nodeId = event.data['nodeId'] as String?;
        if (nodeId != null && _knownNodes.containsKey(nodeId)) {
          _knownNodes[nodeId] = _knownNodes[nodeId]!.copyWith(
            lastSeen: DateTime.now(),
          );
        }
        break;
    }
  }

  @override
  Future<void> dispose() async {
    // _discoveryTimer?.cancel(); // No longer needed
    _heartbeatTimer?.cancel();

    await _layers.dispose();
    _layerManagers.clear();

    await _coordinationNode?.dispose();

    if (!_eventController.isClosed) {
      await _eventController.close();
    }

    _isActive = false;
  }
}

/// Event for layer data
class LayerDataEvent extends CoordinationEvent {
  final String layerId;
  final String sourceNodeId;
  final List<dynamic> data;
  final DateTime timestamp;

  const LayerDataEvent({
    required this.layerId,
    required this.sourceNodeId,
    required this.data,
    required this.timestamp,
  });
}

/// Utility function to avoid unawaited futures
void unawaited(Future<void> future) {
  future.catchError((error) {
    // Log error but don't throw
    print('Unawaited future error: $error');
  });
}

/// Placeholder layer that provides metadata but no active LSL connections
class _PlaceholderLayer extends CoordinationLayer {
  final StreamLayerConfig _config;
  bool _isPaused = false;

  _PlaceholderLayer(this._config);

  @override
  String get layerId => _config.layerId;

  @override
  String get layerName => _config.layerName;

  @override
  StreamLayerConfig get config => _config;

  @override
  bool get isActive => false; // Placeholder is not active

  @override
  bool get isPaused => _isPaused;

  @override
  Stream<LayerDataEvent> get dataStream => const Stream.empty();

  @override
  Stream<CoordinationEvent> get eventStream => const Stream.empty();

  @override
  Future<void> initialize() async {
    // Placeholder does nothing
  }

  @override
  Future<void> start() async {
    throw StateError(
      'Placeholder layer cannot be started. Wait for coordinator promotion.',
    );
  }

  @override
  Future<void> stop() async {
    // Placeholder does nothing
  }

  @override
  Future<void> sendData(List<dynamic> data) async {
    throw StateError(
      'Placeholder layer cannot send data. Wait for coordinator promotion.',
    );
  }

  @override
  Future<void> pause() async {
    if (!_config.isPausable) {
      throw StateError('Layer ${_config.layerId} is not pausable');
    }
    _isPaused = true;
  }

  @override
  Future<void> resume() async {
    if (!_config.isPausable) {
      throw StateError('Layer ${_config.layerId} is not pausable');
    }
    _isPaused = false;
  }

  @override
  void updateKnownNodes(List<NetworkNode> nodes) {
    // Placeholder does nothing
  }

  @override
  Future<void> dispose() async {
    // Placeholder does nothing
  }
}

/// Wrapper that makes the coordination node appear as a coordination layer
class _CoordinationNodeWrapper extends CoordinationLayer {
  final String _layerId;
  final StreamLayerConfig _config;
  final LSLCoordinationNode _coordinationNode;

  _CoordinationNodeWrapper({
    required String layerId,
    required StreamLayerConfig config,
    required LSLCoordinationNode coordinationNode,
  }) : _layerId = layerId,
       _config = config,
       _coordinationNode = coordinationNode;

  @override
  String get layerId => _layerId;

  @override
  String get layerName => _config.layerName;

  @override
  StreamLayerConfig get config => _config;

  @override
  bool get isActive => _coordinationNode.isActive;

  @override
  bool get isPaused => false; // Coordination layer is never paused

  @override
  Stream<LayerDataEvent> get dataStream =>
      // Convert coordination events to layer data events if needed
      const Stream.empty();

  @override
  Stream<CoordinationEvent> get eventStream => _coordinationNode.eventStream;

  @override
  Future<void> initialize() async {
    // Coordination node is already initialized
  }

  @override
  Future<void> start() async {
    // Coordination node is already started
  }

  @override
  Future<void> stop() async {
    // Don't stop coordination node from here
  }

  @override
  Future<void> sendData(List<dynamic> data) async {
    throw StateError('Coordination layer does not support direct data sending');
  }

  @override
  Future<void> pause() async {
    throw StateError('Coordination layer cannot be paused');
  }

  @override
  Future<void> resume() async {
    throw StateError('Coordination layer cannot be resumed');
  }

  @override
  void updateKnownNodes(List<NetworkNode> nodes) {
    // Coordination node manages its own known nodes
  }

  @override
  Future<void> dispose() async {
    // Don't dispose coordination node from here
  }
}
