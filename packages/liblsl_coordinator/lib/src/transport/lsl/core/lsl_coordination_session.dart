import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../session/coordination_session.dart';
import '../../../session/data_stream.dart';
import '../../../session/stream_config.dart';
import '../../../management/network_state.dart';
import '../../../management/network_event_bus.dart';
import '../../../protocol/coordination_protocol.dart';
import '../../../protocol/election_protocol.dart';
import '../../../protocol/network_protocol.dart';
import '../../../utils/logging.dart';
import 'lsl_api_manager.dart';
import '../connection/lsl_connection_manager.dart';
import '../config/lsl_stream_config.dart';
import 'lsl_data_stream.dart';

/// LSL-specific implementation of CoordinationSession
class LSLCoordinationSession implements CoordinationSession {
  @override
  final String sessionId;

  final String _nodeId;
  final String _nodeName;
  final NetworkTopology _expectedTopology;
  final Map<String, dynamic> _sessionMetadata;

  final LSLConnectionManager _connectionManager;
  final NetworkState _networkState;
  final NetworkEventBus _eventBus;
  final CoordinationProtocol _coordinationProtocol;
  final ElectionProtocol _electionProtocol;

  final Map<String, LSLDataStream> _dataStreams = {};
  final StreamController<SessionEvent> _eventController =
      StreamController<SessionEvent>.broadcast();

  SessionState _state = SessionState.disconnected;
  Timer? _heartbeatTimer;
  Timer? _nodeDiscoveryTimer;
  Duration _heartbeatInterval = const Duration(seconds: 5);

  late final ConfiguredLSL _lsl;
  LSLStreamResolverContinuous? _networkResolver;
  LSLStreamResolverContinuous? _nodeResolver;

  LSLCoordinationSession({
    required this.sessionId,
    required String nodeId,
    required String nodeName,
    required NetworkTopology expectedTopology,
    Map<String, dynamic> sessionMetadata = const {},
    required LSLConnectionManager connectionManager,
    required NetworkState networkState,
    required NetworkEventBus eventBus,
    required CoordinationProtocol coordinationProtocol,
    required ElectionProtocol electionProtocol,
    Duration? heartbeatInterval,
  }) : _nodeId = nodeId,
       _nodeName = nodeName,
       _expectedTopology = expectedTopology,
       _sessionMetadata = sessionMetadata,
       _connectionManager = connectionManager,
       _networkState = networkState,
       _eventBus = eventBus,
       _coordinationProtocol = coordinationProtocol,
       _electionProtocol = electionProtocol {
    if (heartbeatInterval != null) {
      _heartbeatInterval = heartbeatInterval;
    }

    _lsl = LSLApiManager.lsl; // Will throw if LSL not initialized

    // Listen to network state changes
    _networkState.stateChanges.listen(_handleNetworkStateChange);

    // Listen to coordination messages
    _coordinationProtocol.messages.listen(_handleCoordinationMessage);

    // Listen to election events
    _electionProtocol.electionEvents.listen(_handleElectionEvent);
  }

  @override
  SessionState get state => _state;

  @override
  Stream<SessionEvent> get events => _eventController.stream;

  @override
  NetworkTopology get topology => _networkState.topology;

  @override
  NodeRole get role => _networkState.role;

  @override
  List<NetworkNode> get nodes => _networkState.nodes;

  @override
  List<DataStream> get dataStreams =>
      _dataStreams.values.cast<DataStream>().toList();

  @override
  DataStream? getDataStream(String streamId) => _dataStreams[streamId];

  @override
  Future<void> join() async {
    logger.info('DEBUG: Starting join() method');
    if (_state != SessionState.disconnected) {
      throw CoordinationSessionException(
        'Session is not in disconnected state',
      );
    }

    try {
      logger.info('DEBUG: Setting state to discovering');
      _updateState(SessionState.discovering);

      // Initialize connection manager
      logger.info('DEBUG: Initializing connection manager');
      await _connectionManager.initialize();
      logger.info('DEBUG: Starting connection manager');
      await _connectionManager.start();
      logger.info('DEBUG: Connection manager started');

      // Initialize coordination protocol
      logger.info('DEBUG: Initializing coordination protocol');
      await _coordinationProtocol.initialize();
      logger.info('DEBUG: Coordination protocol initialized');

      // 1. Network Discovery - Look for existing networks matching our expectations
      final existingNetworks = await _discoverMatchingNetworks();

      if (existingNetworks.isEmpty) {
        // 2. Create Network - No matching network found, create new one
        await _createNetwork();
      } else {
        // 3. Join Existing Network
        await _joinExistingNetwork(existingNetworks.first);
      }

      // 4. Start heartbeat so others can discover us
      _startHeartbeat();

      // 5. Setup role-based connections (peer mesh, client-server, etc.)
      await _setupRoleBasedConnections();

      // 6. Start ongoing node discovery within our network
      _startNodeDiscovery();

      _updateState(SessionState.active);
      _eventController.add(SessionStarted(sessionId));
    } catch (e) {
      _updateState(SessionState.error);
      rethrow;
    }
  }

  @override
  Future<void> leave() async {
    if (_state == SessionState.disconnected) return;

    try {
      _updateState(SessionState.leaving);

      // Stop all data streams
      for (final stream in _dataStreams.values.toList()) {
        await stream.stop();
        await destroyDataStream(stream.streamId);
      }

      // Stop periodic operations
      _heartbeatTimer?.cancel();
      _nodeDiscoveryTimer?.cancel();

      // Announce departure to other nodes
      await _announceLeaving();

      // Cleanup resolvers
      _networkResolver?.destroy();
      _nodeResolver?.destroy();

      // Cleanup protocols
      await _coordinationProtocol.dispose();

      // Stop connection manager
      await _connectionManager.stop();
      await _connectionManager.dispose();

      _updateState(SessionState.disconnected);
      _eventController.add(SessionStopped(sessionId));
    } catch (e) {
      _updateState(SessionState.error);
      rethrow;
    }
  }

  @override
  Future<DataStream> createDataStream(StreamConfig config) async {
    if (_state != SessionState.active) {
      throw CoordinationSessionException(
        'Session must be active to create data streams',
      );
    }

    if (config is! LSLStreamConfig) {
      throw CoordinationSessionException(
        'LSL coordination session requires LSLStreamConfig',
      );
    }

    if (_dataStreams.containsKey(config.id)) {
      throw CoordinationSessionException(
        'Data stream ${config.id} already exists',
      );
    }

    try {
      // Create LSL data stream
      final dataStream = LSLDataStream(
        streamId: config.id,
        config: config,
        connectionManager: _connectionManager,
        nodeId: _nodeId,
      );

      _dataStreams[config.id] = dataStream;

      // Update network state
      await _networkState.addDataStream(dataStream);

      // Announce stream creation to other nodes
      await _announceStreamCreation(config);

      // TODO: Add StreamAdded event to core SessionEvent hierarchy

      return dataStream;
    } catch (e) {
      _dataStreams.remove(config.id);
      rethrow;
    }
  }

  @override
  Future<void> destroyDataStream(String streamId) async {
    final dataStream = _dataStreams.remove(streamId);
    if (dataStream == null) return;

    try {
      await dataStream.stop();
      await dataStream.dispose();
      await _networkState.removeDataStream(streamId);
      await _announceStreamDestruction(streamId);

      // TODO: Add StreamRemoved event to core SessionEvent hierarchy
    } catch (e) {
      _dataStreams[streamId] = dataStream; // Re-add if cleanup failed
      rethrow;
    }
  }

  /// Wait for a specific number of nodes to join the session
  Future<void> waitForNodes(int targetCount, {Duration? timeout}) async {
    if (_networkState.nodes.length >= targetCount) return;

    final completer = Completer<void>();
    late StreamSubscription subscription;
    Timer? timeoutTimer;

    subscription = _networkState.stateChanges.listen((event) {
      if (event is NodeAdded && _networkState.nodes.length >= targetCount) {
        subscription.cancel();
        timeoutTimer?.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            CoordinationSessionException(
              'Timeout waiting for $targetCount nodes',
            ),
          );
        }
      });
    }

    return completer.future;
  }

  /// Request all nodes to create a specific data stream (coordinator only)
  Future<void> requestNetworkDataStream(LSLStreamConfig config) async {
    if (role != NodeRole.server && role != NodeRole.leader) {
      throw CoordinationSessionException(
        'Only coordinators can request network-wide data streams',
      );
    }

    await _coordinationProtocol.sendMessage(
      CoordinationMessage.streamRequest(_nodeId, config.toMap()),
    );
  }

  // === DISCOVERY METHODS ===

  /// 1. Network Discovery - Look for networks matching our session expectations
  Future<List<NetworkInfo>> _discoverMatchingNetworks() async {
    logger.info('DEBUG: Starting network discovery');

    // Initialize network resolver if not already started
    if (_networkResolver == null) {
      logger.info('DEBUG: Creating continuous network resolver');
      _networkResolver = _lsl.createContinuousStreamResolver(
        forgetAfter: 10.0,
        maxStreams: 50,
      );
      // Note: create() is automatically called by the LSL implementation
    }

    // Use continuous resolver to get current streams
    logger.info('DEBUG: Resolving streams with continuous resolver');
    final streams = await _networkResolver!.resolve(waitTime: 1.0);
    logger.info(
      'DEBUG: Continuous resolver found ${streams.length} total streams',
    );

    // Filter streams based on network predicate
    final networkPredicate = _buildNetworkDiscoveryPredicate();
    logger.info('DEBUG: Built network discovery predicate: $networkPredicate');

    // Convert LSL streams to NetworkInfo
    final networks = <NetworkInfo>[];
    for (final stream in streams) {
      try {
        // Check if stream matches our network criteria
        if (_matchesNetworkPredicate(stream, networkPredicate)) {
          final networkInfo = await _parseNetworkInfo(stream);
          if (_isNetworkCompatible(networkInfo)) {
            networks.add(networkInfo);
            logger.info(
              'DEBUG: Added compatible network: ${networkInfo.networkName}',
            );
          }
        }
      } catch (e) {
        logger.fine('DEBUG: Skipped incompatible network stream: $e');
      } finally {
        stream.destroy(); // Clean up stream info
      }
    }

    logger.info(
      'DEBUG: Network discovery completed, found ${networks.length} compatible networks',
    );
    return networks;
  }

  /// Helper method to check if a stream matches network predicate
  bool _matchesNetworkPredicate(LSLStreamInfo stream, String predicate) {
    // For now, do a simple check based on stream metadata
    // In a full implementation, this would evaluate XPath predicates properly
    try {
      // Check if this looks like a coordination stream
      final streamName = stream.streamName;
      final sourceId = stream.sourceId;

      // Look for coordination-related patterns
      if (streamName.contains('coordination') ||
          streamName.contains('network') ||
          sourceId.contains('coord')) {
        logger.fine('DEBUG: Stream matches network predicate: $streamName');
        return true;
      }

      return false;
    } catch (e) {
      logger.fine('DEBUG: Error matching network predicate: $e');
      return false;
    }
  }

  /// 2. Create Network - Become the coordinator if hierarchical
  Future<void> _createNetwork() async {
    _updateState(SessionState.joining);

    // Determine our role based on expected topology
    NodeRole initialRole;
    switch (_expectedTopology) {
      case NetworkTopology.hierarchical:
        initialRole = NodeRole.server; // We're the coordinator
        break;
      case NetworkTopology.peer2peer:
        initialRole = NodeRole.peer;
        break;
      case NetworkTopology.hybrid:
        initialRole = NodeRole.leader; // Hybrid coordinator
        break;
    }

    // Update network state
    await _networkState.updateTopology(_expectedTopology);
    await _networkState.updateRole(initialRole, 'Created new network');

    // Create our coordination heartbeat stream
    await _createCoordinationStream();
  }

  /// 3. Join Existing Network
  Future<void> _joinExistingNetwork(NetworkInfo networkInfo) async {
    _updateState(SessionState.joining);

    // Update network state with discovered topology
    await _networkState.updateTopology(networkInfo.topology);

    // Determine our role based on network topology
    NodeRole joinRole = NodeRole.client; // Default to client
    switch (networkInfo.topology) {
      case NetworkTopology.hierarchical:
        joinRole = NodeRole.client; // Join as client
        break;
      case NetworkTopology.peer2peer:
        joinRole = NodeRole.peer; // Join as peer
        break;
      case NetworkTopology.hybrid:
        joinRole =
            NodeRole.client; // Start as client, may become leader via election
        break;
    }

    await _networkState.updateRole(joinRole, 'Joined existing network');

    // Create our coordination heartbeat stream
    await _createCoordinationStream();

    // If no active coordinator and we support elections, trigger election
    if (networkInfo.topology != NetworkTopology.peer2peer) {
      await _checkForCoordinatorAndElect();
    }
  }

  /// 5. Setup Role-Based Connections
  Future<void> _setupRoleBasedConnections() async {
    switch (topology) {
      case NetworkTopology.peer2peer:
        await _setupPeerConnections();
        break;
      case NetworkTopology.hierarchical:
        await _setupHierarchicalConnections();
        break;
      case NetworkTopology.hybrid:
        await _setupHybridConnections();
        break;
    }
  }

  Future<void> _setupPeerConnections() async {
    // In peer networks, connect to all other peers
    // TODO: Implement peer mesh connections
    // This would involve creating inlets for all other peer coordination streams
  }

  Future<void> _setupHierarchicalConnections() async {
    if (role == NodeRole.server) {
      // As coordinator, we don't need inlets from clients (they connect to us)
      // TODO: Setup to accept client connections
    } else if (role == NodeRole.client) {
      // As client, connect to the coordinator
      // TODO: Create inlet for coordinator's stream
    }
  }

  Future<void> _setupHybridConnections() async {
    // Hybrid networks combine peer and hierarchical patterns
    // TODO: Implement hybrid connection strategy
  }

  // === PERIODIC OPERATIONS ===

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      await _coordinationProtocol.sendHeartbeat();
    });
  }

  void _startNodeDiscovery() {
    // Discover other nodes within our network periodically
    _nodeDiscoveryTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) async {
      await _discoverNetworkNodes();
    });
  }

  Future<void> _discoverNetworkNodes() async {
    // Look for other nodes in our specific session
    final nodePredicate = _buildNodeDiscoveryPredicate();

    final streams = await _lsl.resolveStreamsByPredicate(
      predicate: nodePredicate,
      waitTime: 1.0,
    );

    // Process discovered nodes
    for (final stream in streams) {
      try {
        final nodeInfo = await _parseNodeInfo(stream);
        if (nodeInfo.nodeId != _nodeId) {
          // Don't add ourselves
          await _networkState.updateNode(nodeInfo);
        }
      } catch (e) {
        // Skip malformed node info
      }
    }
  }

  // === HELPER METHODS ===

  void _updateState(SessionState newState) {
    final oldState = _state;
    _state = newState;
    _networkState.updateSessionState(newState);
    // TODO: Add SessionStateChanged event to core SessionEvent hierarchy
  }

  String _buildNetworkDiscoveryPredicate() {
    // Look for coordination streams that indicate network presence
    return "name='${sessionId}_network' and type='coordination'";
  }

  String _buildNodeDiscoveryPredicate() {
    // Look for heartbeat streams from nodes in our session
    return "name='${sessionId}_heartbeat' and type='coordination'";
  }

  Future<NetworkInfo> _parseNetworkInfo(LSLStreamInfo stream) async {
    // Parse network info from LSL stream metadata
    // TODO: Implement based on coordination stream format
    throw UnimplementedError('Network info parsing not implemented');
  }

  Future<NetworkNode> _parseNodeInfo(LSLStreamInfo stream) async {
    // Parse node info from LSL stream metadata
    // TODO: Implement based on heartbeat stream format
    throw UnimplementedError('Node info parsing not implemented');
  }

  bool _isNetworkCompatible(NetworkInfo networkInfo) {
    // Check if discovered network matches our expectations
    return networkInfo.topology == _expectedTopology;
  }

  Future<void> _createCoordinationStream() async {
    // Create our heartbeat/coordination stream
    // TODO: Implement coordination stream creation
  }

  Future<void> _checkForCoordinatorAndElect() async {
    // Check if there's an active coordinator, trigger election if needed
    // TODO: Implement coordinator detection and election triggering
  }

  Future<void> _announceLeaving() async {
    // TODO: Send leave announcement
  }

  Future<void> _announceStreamCreation(LSLStreamConfig config) async {
    // TODO: Announce stream creation
  }

  Future<void> _announceStreamDestruction(String streamId) async {
    // TODO: Announce stream destruction
  }

  void _handleNetworkStateChange(NetworkStateEvent event) {
    // TODO: React to network state changes
  }

  void _handleCoordinationMessage(IncomingCoordinationMessage message) {
    // TODO: Process coordination messages
  }

  void _handleElectionEvent(ElectionEvent event) {
    // TODO: React to election events
  }
}

/// Exception for coordination session operations
class CoordinationSessionException implements Exception {
  final String message;

  const CoordinationSessionException(this.message);

  @override
  String toString() => 'CoordinationSessionException: $message';
}

/// Session events - These would be part of the core SessionEvent hierarchy
/// For now, we'll use the existing SessionEvent types from the core module

/// Extension for LSLStreamConfig serialization
extension LSLStreamConfigSerialization on LSLStreamConfig {
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'maxSampleRate': maxSampleRate,
      'pollingFrequency': pollingFrequency,
      'channelCount': channelCount,
      'sourceId': sourceId,
      'streamType': streamType,
      'metadata': metadata,
    };
  }
}
