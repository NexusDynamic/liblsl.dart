import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../session/coordination_session.dart';
import '../../../session/data_stream.dart';
import '../../../network/network_state.dart';
import '../../../utils/logging.dart';
import '../core/lsl_api_manager.dart';
import 'lsl_connection_manager.dart';

/// LSL-specific implementation of NetworkState
///
/// This implementation uses LSL streams for network state coordination,
/// allowing nodes to discover each other and maintain network topology
/// information through LSL metadata and streams.
class LSLNetworkState implements NetworkState {
  final String nodeId;
  final String nodeName;
  final String sessionId;
  final String coordinationPrefix;
  final LSLConnectionManager _connectionManager;

  NetworkTopology _topology = NetworkTopology.peer2peer;
  NodeRole _role = NodeRole.discovering;
  final List<NetworkNode> _nodes = [];
  final List<DataStream> _activeStreams = [];
  SessionState _sessionState = SessionState.disconnected;

  final StreamController<NetworkStateEvent> _eventController =
      StreamController<NetworkStateEvent>.broadcast();

  // LSL-specific state management
  LSLOutlet? _nodeStateOutlet;
  LSLStreamResolverContinuous? _nodeResolver;
  Timer? _statePublishTimer;
  Timer? _discoveryTimer;

  late final ConfiguredLSL _lsl;

  LSLNetworkState({
    required this.nodeId,
    required this.nodeName,
    required this.sessionId,
    required this.coordinationPrefix,
    required LSLConnectionManager connectionManager,
  }) : _connectionManager = connectionManager {
    _lsl = LSLApiManager.lsl;

    // Add ourselves as the first node
    _nodes.add(
      NetworkNode(
        nodeId: nodeId,
        nodeName: nodeName,
        role: _role,
        lastSeen: DateTime.now(),
        metadata: {
          'session_id': sessionId,
          'node_type': 'coordinator',
          'capabilities': ['data_streaming', 'coordination'],
        },
      ),
    );
  }

  @override
  NetworkTopology get topology => _topology;

  @override
  NodeRole get role => _role;

  @override
  List<NetworkNode> get nodes => List.unmodifiable(_nodes);

  @override
  NetworkNode get thisNode => _nodes.firstWhere((n) => n.nodeId == nodeId);

  @override
  NetworkNode? get leader =>
      _nodes
          .where((n) => n.role == NodeRole.leader || n.role == NodeRole.server)
          .firstOrNull;

  @override
  List<DataStream> get activeStreams => List.unmodifiable(_activeStreams);

  @override
  SessionState get sessionState => _sessionState;

  @override
  Stream<NetworkStateEvent> get stateChanges => _eventController.stream;

  /// Initialize the LSL network state management
  Future<void> initialize() async {
    logger.info('Initializing LSL network state for node $nodeId');

    try {
      logger.info('LSL network state initialized successfully');
    } catch (e) {
      logger.severe('Failed to initialize LSL network state: $e');
      rethrow;
    }
  }

  /// Dispose of all LSL network state resources
  Future<void> dispose() async {
    logger.info('Disposing LSL network state');

    // Stop timers
    _statePublishTimer?.cancel();
    _discoveryTimer?.cancel();

    // Cleanup LSL resources
    try {
      _nodeResolver?.destroy();
      await _nodeStateOutlet?.destroy();
    } catch (e) {
      logger.warning('Error cleaning up LSL network state resources: $e');
    }

    await _eventController.close();
    logger.info('LSL network state disposed');
  }

  @override
  Future<void> updateTopology(NetworkTopology newTopology) async {
    if (_topology == newTopology) return;

    final oldTopology = _topology;
    _topology = newTopology;

    logger.info('Network topology changed: $oldTopology -> $newTopology');

    // Update our node state and publish
    await _publishNodeState();

    _eventController.add(NetworkTopologyChanged(oldTopology, newTopology));
  }

  @override
  Future<void> updateRole(NodeRole newRole, String reason) async {
    if (_role == newRole) return;

    final oldRole = _role;
    _role = newRole;

    logger.info('Node role changed: $oldRole -> $newRole (reason: $reason)');

    // Update our node in the list
    final nodeIndex = _nodes.indexWhere((n) => n.nodeId == nodeId);
    if (nodeIndex >= 0) {
      _nodes[nodeIndex] = _nodes[nodeIndex].copyWith(
        role: newRole,
        lastSeen: DateTime.now(),
      );
    }

    // Publish updated state to network
    await _publishNodeState();

    _eventController.add(NetworkRoleChanged(nodeId, oldRole, newRole, reason));
  }

  @override
  Future<void> updateNode(NetworkNode node) async {
    final existingIndex = _nodes.indexWhere((n) => n.nodeId == node.nodeId);

    if (existingIndex >= 0) {
      final existing = _nodes[existingIndex];
      _nodes[existingIndex] = node;

      logger.fine('Updated node: ${node.nodeId} (${node.nodeName})');
      _eventController.add(NodeUpdated(node, existing));
    } else {
      _nodes.add(node);

      logger.info(
        'Added new node: ${node.nodeId} (${node.nodeName}) as ${node.role}',
      );
      _eventController.add(NodeAdded(node));
    }
  }

  @override
  Future<void> removeNode(String nodeId) async {
    final nodeIndex = _nodes.indexWhere((n) => n.nodeId == nodeId);
    if (nodeIndex >= 0) {
      final node = _nodes.removeAt(nodeIndex);

      logger.info('Removed node: ${node.nodeId} (${node.nodeName})');
      _eventController.add(NodeRemoved(node));
    }
  }

  @override
  Future<void> addDataStream(DataStream stream) async {
    if (!_activeStreams.any((s) => s.streamId == stream.streamId)) {
      _activeStreams.add(stream);

      logger.info('Added data stream: ${stream.streamId}');

      // Publish updated state
      await _publishNodeState();

      _eventController.add(StreamStateChanged(stream.streamId, 'added'));
    }
  }

  @override
  Future<void> removeDataStream(String streamId) async {
    final streamIndex = _activeStreams.indexWhere(
      (s) => s.streamId == streamId,
    );
    if (streamIndex >= 0) {
      _activeStreams.removeAt(streamIndex);

      logger.info('Removed data stream: $streamId');

      // Publish updated state
      await _publishNodeState();

      _eventController.add(StreamStateChanged(streamId, 'removed'));
    }
  }

  @override
  Future<void> updateSessionState(SessionState newState) async {
    if (_sessionState == newState) return;

    final oldState = _sessionState;
    _sessionState = newState;

    logger.info('Session state changed: $oldState -> $newState');

    // Publish updated state
    await _publishNodeState();

    _eventController.add(SessionStateEvent(oldState, newState));
  }

  // === LSL-SPECIFIC IMPLEMENTATION ===

  /// Create LSL outlet for publishing our node state
  Future<void> _createNodeStateOutlet() async {
    try {
      // Create stream info for node state
      final streamInfo = await _lsl.createStreamInfo(
        streamName: '${sessionId}_node_state',
        streamType: LSLContentType.eeg, // Use existing content type
        channelCount: 1,
        sampleRate: 1.0, // Low frequency for state updates
        channelFormat: LSLChannelFormat.string,
        sourceId: '${coordinationPrefix}_${nodeId}_state',
      );

      // Add metadata for stream discovery using XML structure
      final description = streamInfo.description;
      final descElement = description.value;

      descElement.addChildValue('session_id', sessionId);
      descElement.addChildValue('node_id', nodeId);
      descElement.addChildValue('node_name', nodeName);
      descElement.addChildValue('stream_purpose', 'node_state_coordination');
      descElement.addChildValue('protocol_version', '1.0');

      // Create outlet
      _nodeStateOutlet = await _lsl.createOutlet(
        streamInfo: streamInfo,
        chunkSize: 1,
        maxBuffer: 10, // Small buffer for state updates
      );

      logger.fine('Created node state outlet: ${streamInfo.sourceId}');
    } catch (e) {
      logger.severe('Failed to create node state outlet: $e');
      rethrow;
    }
  }

  /// Start continuous discovery of other nodes in the network
  Future<void> _startNodeDiscovery() async {
    try {
      // Create resolver for node state streams in our session
      _nodeResolver = _lsl.createContinuousStreamResolver(
        forgetAfter: 10.0, // Forget nodes after 10 seconds of silence
        maxStreams: 50,
      );

      // Start periodic discovery
      _discoveryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        await _discoverNodes();
      });

      logger.fine('Started node discovery');
    } catch (e) {
      logger.severe('Failed to start node discovery: $e');
      rethrow;
    }
  }

  /// Discover other nodes using LSL stream resolution
  Future<void> _discoverNodes() async {
    try {
      // Build predicate for finding node state streams in our session
      final predicate =
          "name='${sessionId}_node_state' and type='coordination'";

      // Use continuous resolver for dynamic node discovery
      final resolver = _lsl.createContinuousStreamResolverByPredicate(
        predicate: predicate,
        forgetAfter: 10.0,
        maxStreams: 50,
      );

      final streams = await resolver.resolve(waitTime: 0.0);
      // Note: resolver stays active for ongoing discovery

      logger.finest('Discovered ${streams.length} node state streams');

      // Process discovered nodes
      for (final streamInfo in streams) {
        try {
          final nodeInfo = await _parseNodeFromStreamInfo(streamInfo);

          // Don't add ourselves
          if (nodeInfo.nodeId != nodeId) {
            await updateNode(nodeInfo);
          }
        } catch (e) {
          logger.warning(
            'Failed to parse node info from stream ${streamInfo.sourceId}: $e',
          );
        } finally {
          // Clean up stream info
          try {
            streamInfo.destroy();
          } catch (e) {
            logger.warning('Error destroying stream info: $e');
          }
        }
      }
    } catch (e) {
      logger.warning('Node discovery failed: $e');
    }
  }

  /// Parse NetworkNode information from LSL stream basic properties
  /// The predicate filtering already ensures this stream belongs to our session
  Future<NetworkNode> _parseNodeFromStreamInfo(LSLStreamInfo streamInfo) async {
    // Extract node info from sourceId (format: {coordinationPrefix}_{nodeId}_state)
    final sourceIdWithoutPrefix =
        streamInfo.sourceId.startsWith(coordinationPrefix)
            ? streamInfo.sourceId.substring(
              coordinationPrefix.length + 1,
            ) // +1 for underscore
            : streamInfo.sourceId;

    final nodeId = sourceIdWithoutPrefix.replaceFirst('_state', '');

    // For now, use nodeId as nodeName - actual name will be updated from state messages
    final nodeName = 'Node_$nodeId';

    // Default to peer role - actual role will be updated from state messages
    final role = NodeRole.peer;

    return NetworkNode(
      nodeId: nodeId,
      nodeName: nodeName,
      role: role,
      lastSeen: DateTime.now(),
      metadata: {
        'session_id': sessionId,
        'discovered_via': 'stream_resolution',
        'source_id': streamInfo.sourceId,
        'stream_name': streamInfo.streamName,
        'coordination_prefix': coordinationPrefix,
      },
    );
  }

  /// Publish current node state through LSL outlet
  Future<void> _publishNodeState() async {
    if (_nodeStateOutlet == null) return;

    try {
      // Create state message with current node information
      final stateData = {
        'node_id': nodeId,
        'node_name': nodeName,
        'role': _role.toString().split('.').last,
        'topology': _topology.toString().split('.').last,
        'session_state': _sessionState.toString().split('.').last,
        'active_streams': _activeStreams.length,
        'stream_ids': _activeStreams.map((s) => s.streamId).toList(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Convert to simple encoded string and send
      final stateJson = _encodeStateData(stateData);
      await _nodeStateOutlet!.pushSample([stateJson]);

      logger.finest(
        'Published node state: ${_role.toString().split('.').last}',
      );
    } catch (e) {
      logger.warning('Failed to publish node state: $e');
    }
  }

  /// Simple encoding of state data (key=value pairs separated by semicolons)
  String _encodeStateData(Map<String, dynamic> data) {
    return data.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(';');
  }

  /// Get network statistics for monitoring and debugging
  Map<String, dynamic> getNetworkStatistics() {
    return {
      'session_id': sessionId,
      'node_count': _nodes.length,
      'active_streams': _activeStreams.length,
      'topology': _topology.toString().split('.').last,
      'role': _role.toString().split('.').last,
      'session_state': _sessionState.toString().split('.').last,
      'nodes':
          _nodes
              .map(
                (n) => {
                  'id': n.nodeId,
                  'name': n.nodeName,
                  'role': n.role.toString().split('.').last,
                  'last_seen_ago':
                      DateTime.now().difference(n.lastSeen).inSeconds,
                },
              )
              .toList(),
    };
  }

  /// Remove nodes that haven't been seen recently (LSL-specific cleanup)
  Future<void> cleanupStaleNodes({Duration? threshold}) async {
    final staleThreshold = threshold ?? const Duration(seconds: 30);
    final now = DateTime.now();

    final staleNodes =
        _nodes
            .where(
              (node) =>
                  node.nodeId != nodeId && // Don't remove ourselves
                  now.difference(node.lastSeen) > staleThreshold,
            )
            .toList();

    for (final staleNode in staleNodes) {
      logger.info('Removing stale node: ${staleNode.nodeId}');
      await removeNode(staleNode.nodeId);
    }
  }
}
