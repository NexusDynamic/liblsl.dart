import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../../liblsl_coordinator.dart';
import '../../../session/coordination_session.dart';
import '../../../session/data_stream.dart';
import '../../../session/stream_config.dart';
import '../../../management/network_state.dart';
import '../../../management/network_event_bus.dart';
import '../../../protocol/network_protocol.dart';
import '../../../protocol/coordination_protocol.dart';
import '../../../protocol/election_protocol.dart';
import '../../../utils/logging.dart';
import '../../../utils/stream_controller_extensions.dart';
import '../../../management/resource_manager.dart';
import 'lsl_api_manager.dart';
import '../connection/lsl_connection_manager.dart';
import '../config/lsl_stream_config.dart';
import 'lsl_data_stream.dart';

/// LSL-specific implementation of CoordinationSession
class LSLCoordinationSession implements CoordinationSession, ManagedResource {
  @override
  final String sessionId;

  final String _nodeId;
  final String _nodeName;
  final NetworkTopology _expectedTopology;
  final Map<String, dynamic> _sessionMetadata;
  final ConnectionConfig _connectionConfig;

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

  // ManagedResource fields
  ResourceState _resourceState = ResourceState.created;
  final StreamController<ResourceStateEvent> _resourceStateController =
      StreamController<ResourceStateEvent>.broadcast();

  late final ConfiguredLSL _lsl;
  LSLStreamResolverContinuous? _networkResolver;
  LSLStreamResolverContinuous? _nodeResolver;
  LSLStreamResolverContinuousByPredicate? _peerResolver;
  LSLStreamResolverContinuousByPredicate? _coordinatorResolver;
  LSLStreamResolverContinuousByPredicate? _clientResolver;

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
    ConnectionConfig? connectionConfig,
  }) : _nodeId = nodeId,
       _nodeName = nodeName,
       _expectedTopology = expectedTopology,
       _sessionMetadata = sessionMetadata,
       _connectionConfig = connectionConfig ?? const ConnectionConfig(),
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
      _eventController.addEvent(SessionStarted(sessionId));
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
      _peerResolver?.destroy();
      _coordinatorResolver?.destroy();
      _clientResolver?.destroy();

      // Cleanup protocols
      await _coordinationProtocol.dispose();

      // Stop connection manager
      await _connectionManager.stop();
      await _connectionManager.dispose();

      _updateState(SessionState.disconnected);
      _eventController.addEvent(SessionStopped(sessionId));
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

      _eventController.addEvent(
        StreamAdded(sessionId, config.id, config.toMap()),
      );

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

      _eventController.addEvent(
        StreamRemoved(sessionId, streamId, 'Stream destroyed'),
      );
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
    try {
      logger.info('Setting up peer connections for P2P topology');

      // Create continuous resolver for peer streams if not already created
      if (_peerResolver == null) {
        final peerPredicate =
            "name='${sessionId}_coordination' and contains(desc/node_role, 'peer') and not(contains(source_id, '_${_nodeId}_'))";

        _peerResolver = _lsl.createContinuousStreamResolverByPredicate(
          predicate: peerPredicate,
          forgetAfter: _connectionConfig.forgetAfter,
          maxStreams: _connectionConfig.maxPeerConnections + 1,
        );

        logger.fine('Created continuous peer resolver');
      }

      // Get current peer streams
      final peerStreams = await _peerResolver!.resolve();
      logger.info('Found ${peerStreams.length} peer streams to connect to');

      // Create inlets for each peer's coordination stream
      for (final stream in peerStreams) {
        try {
          final sourceIdParts = stream.sourceId.split('_');
          if (sourceIdParts.length < 2) continue;

          final peerId = sourceIdParts[1]; // Extract node ID
          final inletId = 'peer_${peerId}_coordination';

          // Check if we already have this inlet
          if (!_connectionManager.hasInlet(inletId)) {
            await _connectionManager.createInlet(
              inletId: inletId,
              streamInfo: stream,
              pollingConfig: LSLPollingConfig.standard(),
            );

            logger.fine('Connected to peer: $peerId');
          }
        } catch (e) {
          logger.warning(
            'Failed to connect to peer stream ${stream.sourceId}: $e',
          );
        } finally {
          stream.destroy();
        }
      }
    } catch (e) {
      logger.severe('Error setting up peer connections: $e');
      throw CoordinationSessionException(
        'Failed to setup peer connections: $e',
      );
    }
  }

  Future<void> _setupHierarchicalConnections() async {
    try {
      if (role == NodeRole.server) {
        logger.info('Setting up server connections (coordinator role)');

        // Create continuous resolver for client monitoring if not already created
        if (_clientResolver == null) {
          final clientPredicate =
              "name='${sessionId}_coordination' and contains(desc/node_role, 'client') and not(contains(source_id, '_${_nodeId}_'))";

          _clientResolver = _lsl.createContinuousStreamResolverByPredicate(
            predicate: clientPredicate,
            forgetAfter: _connectionConfig.forgetAfter,
            maxStreams: _connectionConfig.maxClientConnections + 1,
          );

          logger.fine('Created continuous client resolver');
        }

        // Get current client streams for monitoring
        final clientStreams = await _clientResolver!.resolve();
        logger.info('Found ${clientStreams.length} client streams to monitor');

        for (final stream in clientStreams) {
          try {
            final sourceIdParts = stream.sourceId.split('_');
            if (sourceIdParts.length < 2) continue;

            final clientId = sourceIdParts[1];
            final inletId = 'client_${clientId}_monitor';

            // Check if we already have this inlet
            if (!_connectionManager.hasInlet(inletId)) {
              await _connectionManager.createInlet(
                inletId: inletId,
                streamInfo: stream,
                pollingConfig: LSLPollingConfig.standard(),
              );

              logger.fine('Monitoring client: $clientId');
            }
          } catch (e) {
            logger.warning(
              'Failed to monitor client stream ${stream.sourceId}: $e',
            );
          } finally {
            stream.destroy();
          }
        }
      } else if (role == NodeRole.client) {
        logger.info(
          'Setting up client connections (connecting to coordinator)',
        );

        // Create continuous resolver for coordinator if not already created
        if (_coordinatorResolver == null) {
          final coordinatorPredicate =
              "name='${sessionId}_coordination' and (contains(desc/node_role, 'server') or contains(desc/node_role, 'leader'))";

          _coordinatorResolver = _lsl.createContinuousStreamResolverByPredicate(
            predicate: coordinatorPredicate,
            forgetAfter: _connectionConfig.forgetAfter,
            maxStreams: _connectionConfig.maxLeaderConnections + 1,
          );

          logger.fine('Created continuous coordinator resolver');
        }

        // Get current coordinator streams
        final coordinatorStreams = await _coordinatorResolver!.resolve();

        if (coordinatorStreams.isEmpty) {
          throw CoordinationSessionException(
            'No coordinator found for hierarchical connection',
          );
        }

        // Connect to all available coordinators for redundancy if enabled
        final streamsToConnect =
            _connectionConfig.enableRedundantConnections
                ? coordinatorStreams
                : coordinatorStreams.take(1);

        for (final coordinatorStream in streamsToConnect) {
          try {
            final sourceIdParts = coordinatorStream.sourceId.split('_');
            if (sourceIdParts.length < 2) continue;

            final coordinatorId = sourceIdParts[1];
            final inletId = 'coordinator_${coordinatorId}_connection';

            // Check if we already have this inlet
            if (!_connectionManager.hasInlet(inletId)) {
              await _connectionManager.createInlet(
                inletId: inletId,
                streamInfo: coordinatorStream,
                pollingConfig: LSLPollingConfig.standard(),
              );

              logger.info('Connected to coordinator: $coordinatorId');
            }
          } catch (e) {
            logger.warning(
              'Failed to connect to coordinator ${coordinatorStream.sourceId}: $e',
            );
          } finally {
            coordinatorStream.destroy();
          }
        }
      }
    } catch (e) {
      logger.severe('Error setting up hierarchical connections: $e');
      throw CoordinationSessionException(
        'Failed to setup hierarchical connections: $e',
      );
    }
  }

  Future<void> _setupHybridConnections() async {
    try {
      logger.info('Setting up hybrid connections');

      if (role == NodeRole.leader) {
        logger.info('Setting up leader connections in hybrid topology');

        // Create continuous resolver for other leaders if not already created
        if (_peerResolver == null) {
          final leaderPredicate =
              "name='${sessionId}_coordination' and contains(desc/node_role, 'leader') and not(contains(source_id, '_${_nodeId}_'))";

          _peerResolver = _lsl.createContinuousStreamResolverByPredicate(
            predicate: leaderPredicate,
            forgetAfter: _connectionConfig.forgetAfter,
            maxStreams: _connectionConfig.maxLeaderConnections + 1,
          );

          logger.fine('Created continuous leader resolver');
        }

        // Get current leader streams
        final leaderStreams = await _peerResolver!.resolve();
        logger.info(
          'Found ${leaderStreams.length} other leaders to connect to',
        );

        for (final stream in leaderStreams) {
          try {
            final sourceIdParts = stream.sourceId.split('_');
            if (sourceIdParts.length < 2) continue;

            final leaderId = sourceIdParts[1];
            final inletId = 'leader_${leaderId}_connection';

            if (!_connectionManager.hasInlet(inletId)) {
              await _connectionManager.createInlet(
                inletId: inletId,
                streamInfo: stream,
                pollingConfig: LSLPollingConfig.standard(),
              );

              logger.fine('Connected to leader: $leaderId');
            }
          } catch (e) {
            logger.warning(
              'Failed to connect to leader ${stream.sourceId}: $e',
            );
          } finally {
            stream.destroy();
          }
        }

        // Also setup client monitoring using hierarchical approach
        await _setupHierarchicalConnections();
      } else if (role == NodeRole.client) {
        logger.info('Setting up client connections in hybrid topology');

        // First try to connect to leaders (hierarchical-like)
        if (_coordinatorResolver == null) {
          final leaderPredicate =
              "name='${sessionId}_coordination' and contains(desc/node_role, 'leader')";

          _coordinatorResolver = _lsl.createContinuousStreamResolverByPredicate(
            predicate: leaderPredicate,
            forgetAfter: _connectionConfig.forgetAfter,
            maxStreams: _connectionConfig.maxLeaderConnections + 1,
          );

          logger.fine('Created continuous leader resolver for hybrid client');
        }

        final leaderStreams = await _coordinatorResolver!.resolve();

        if (leaderStreams.isNotEmpty) {
          // Connect to available leaders (limited by configuration)
          final streamsToConnect =
              _connectionConfig.enableRedundantConnections
                  ? leaderStreams
                  : leaderStreams.take(1);

          for (final stream in streamsToConnect) {
            try {
              final sourceIdParts = stream.sourceId.split('_');
              if (sourceIdParts.length < 2) continue;

              final leaderId = sourceIdParts[1];
              final inletId = 'leader_${leaderId}_connection';

              if (!_connectionManager.hasInlet(inletId)) {
                await _connectionManager.createInlet(
                  inletId: inletId,
                  streamInfo: stream,
                  pollingConfig: LSLPollingConfig.standard(),
                );

                logger.fine('Connected to leader: $leaderId');
              }
            } catch (e) {
              logger.warning(
                'Failed to connect to leader ${stream.sourceId}: $e',
              );
            } finally {
              stream.destroy();
            }
          }
        } else {
          logger.warning(
            'No leaders found in hybrid topology, falling back to peer connections',
          );
        }

        // Optionally setup some peer connections for mesh-like communication
        if (_peerResolver == null) {
          final peerPredicate =
              "name='${sessionId}_coordination' and contains(desc/node_role, 'client') and not(contains(source_id, '_${_nodeId}_'))";

          _peerResolver = _lsl.createContinuousStreamResolverByPredicate(
            predicate: peerPredicate,
            forgetAfter: _connectionConfig.forgetAfter,
            maxStreams: _connectionConfig.maxPeerConnections + 1,
          );

          logger.fine('Created continuous peer resolver for hybrid client');
        }

        final peerStreams = await _peerResolver!.resolve();

        // Connect to a subset of peers (limited by configuration)
        final peersToConnect = peerStreams.take(
          _connectionConfig.maxPeerConnections,
        );

        for (final stream in peersToConnect) {
          try {
            final sourceIdParts = stream.sourceId.split('_');
            if (sourceIdParts.length < 2) continue;

            final peerId = sourceIdParts[1];
            final inletId = 'peer_${peerId}_connection';

            if (!_connectionManager.hasInlet(inletId)) {
              await _connectionManager.createInlet(
                inletId: inletId,
                streamInfo: stream,
                pollingConfig: LSLPollingConfig.standard(),
              );

              logger.fine('Connected to peer: $peerId');
            }
          } catch (e) {
            logger.warning('Failed to connect to peer ${stream.sourceId}: $e');
          } finally {
            stream.destroy();
          }
        }

        // Clean up remaining peer streams we didn't connect to
        for (final stream in peerStreams.skip(
          _connectionConfig.maxPeerConnections,
        )) {
          stream.destroy();
        }
      }
    } catch (e) {
      logger.severe('Error setting up hybrid connections: $e');
      throw CoordinationSessionException(
        'Failed to setup hybrid connections: $e',
      );
    }
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
    _eventController.addEvent(
      SessionStateChanged(sessionId, oldState, newState),
    );
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
    try {
      final description = stream.description;
      final sessionIdElement = description.findChild('session_id');
      final topologyElement = description.findChild('topology');
      final nodeCountElement = description.findChild('node_count');
      final networkNameElement = description.findChild('network_name');

      final extractedSessionId =
          sessionIdElement?.value ?? stream.streamName.split('_').first;
      final topologyString = topologyElement?.value ?? 'hierarchical';
      final nodeCount = int.tryParse(nodeCountElement?.value ?? '1') ?? 1;
      final networkName = networkNameElement?.value ?? extractedSessionId;

      // Parse topology
      NetworkTopology topology;
      switch (topologyString.toLowerCase()) {
        case 'peer2peer':
          topology = NetworkTopology.peer2peer;
          break;
        case 'hybrid':
          topology = NetworkTopology.hybrid;
          break;
        default:
          topology = NetworkTopology.hierarchical;
      }

      return NetworkInfo(
        networkId: extractedSessionId,
        networkName: networkName,
        topology: topology,
        nodeCount: nodeCount,
        lastSeen: DateTime.now(),
        metadata: {
          'sourceId': stream.sourceId,
          'streamName': stream.streamName,
          'sampleRate': stream.sampleRate,
        },
      );
    } catch (e) {
      logger.warning(
        'Error parsing network info from stream ${stream.sourceId}: $e',
      );
      rethrow;
    }
  }

  Future<NetworkNode> _parseNodeInfo(LSLStreamInfoWithMetadata stream) async {
    try {
      final LSLXmlNode description = stream.description.value;
      final nodeIdElement = description.childNamed('node_id');
      final nodeNameElement = description.childNamed('node_name');
      final roleElement = description.childNamed('node_role');

      final nodeId =
          nodeIdElement?.textValue ?? stream.sourceId.split('_').last;
      final nodeName = nodeNameElement?.textValue ?? 'Node_$nodeId';
      final roleString = roleElement?.textValue ?? 'client';

      // Parse role
      NodeRole role;
      switch (roleString.toLowerCase()) {
        case 'server':
          role = NodeRole.server;
          break;
        case 'leader':
          role = NodeRole.leader;
          break;
        case 'peer':
          role = NodeRole.peer;
          break;
        case 'discovering':
          role = NodeRole.discovering;
          break;
        default:
          role = NodeRole.client;
      }

      return NetworkNode(
        nodeId: nodeId,
        nodeName: nodeName,
        role: role,
        lastSeen: DateTime.now(),
        metadata: {
          'sourceId': stream.sourceId,
          'streamName': stream.streamName,
          'sampleRate': stream.sampleRate,
          'channelCount': stream.channelCount,
        },
      );
    } catch (e) {
      logger.warning(
        'Error parsing node info from stream ${stream.sourceId}: $e',
      );
      rethrow;
    }
  }

  bool _isNetworkCompatible(NetworkInfo networkInfo) {
    // Check if discovered network matches our expectations
    return networkInfo.topology == _expectedTopology;
  }

  Future<void> _createCoordinationStream() async {
    try {
      // Create stream info for this node's coordination/heartbeat stream
      final streamInfo = await _lsl.createStreamInfo(
        streamName: '${sessionId}_coordination',
        streamType: LSLContentType.eeg,
        channelCount: 1,
        sampleRate: 2.0, // 2 Hz heartbeat
        channelFormat: LSLChannelFormat.string,
        sourceId: 'coord_${_nodeId}_heartbeat',
      );

      // Add metadata for discovery
      final description = streamInfo.description;
      final descElement = description.value;

      descElement.addChildValue('session_id', sessionId);
      descElement.addChildValue('node_id', _nodeId);
      descElement.addChildValue('node_name', _nodeName);
      descElement.addChildValue('node_role', role.name);
      descElement.addChildValue('topology', topology.name);
      descElement.addChildValue('network_name', sessionId);
      descElement.addChildValue('stream_purpose', 'coordination_heartbeat');

      // Add session metadata
      for (final entry in _sessionMetadata.entries) {
        descElement.addChildValue(
          'session_${entry.key}',
          entry.value.toString(),
        );
      }

      // Create outlet (will be managed by connection manager)
      final outlet = await _connectionManager.createOutlet(
        streamId: '${_nodeId}_coordination',
        streamInfo: streamInfo,
        useIsolates: false,
      );

      logger.info('Created coordination stream: ${streamInfo.sourceId}');
    } catch (e) {
      logger.severe('Failed to create coordination stream: $e');
      rethrow;
    }
  }

  Future<void> _checkForCoordinatorAndElect() async {
    try {
      // Look for existing coordinators (servers/leaders)
      final coordinatorPredicate =
          "name='${sessionId}_coordination' and contains(source_id, 'coord_') and (contains(desc/node_role, 'server') or contains(desc/node_role, 'leader'))";

      final coordinatorStreams = await _lsl.resolveStreamsByPredicate(
        predicate: coordinatorPredicate,
        waitTime: 2.0,
      );

      if (coordinatorStreams.isEmpty) {
        logger.info('No active coordinator found, triggering election');
        // Trigger election if we support it
        if (topology == NetworkTopology.hybrid) {
          await _electionProtocol.triggerElection(
            candidateId: _nodeId,
            reason: 'No active coordinator detected',
          );
        }
      } else {
        logger.info('Found ${coordinatorStreams.length} active coordinator(s)');
        // Update network state with coordinator info
        for (final stream in coordinatorStreams) {
          try {
            NetworkNode nodeInfo;
            if (_connectionManager.hasInlet(stream.sourceId)) {
              logger.fine(
                'Already connected to coordinator: ${stream.sourceId}',
              );
              final inlet = _connectionManager.getInlet(stream.sourceId);
              if (inlet != null) {
                // Ensure inlet is active
                final fullNodeInfo = await inlet.getFullInfo(timeout: 1.0);
                nodeInfo = await _parseNodeInfo(fullNodeInfo);
              } else {
                throw CoordinationSessionException(
                  'Expected Inlet for coordinator ${stream.sourceId} not found',
                );
              }
            } else {
              logger.fine(
                'Creating new inlet for coordinator: ${stream.sourceId}',
              );
              // Create inlet for this coordinator stream
              final inlet = await _connectionManager.createInlet(
                inletId: stream.sourceId,
                streamInfo: stream,
                pollingConfig: LSLPollingConfig.standard(),
              );
              final fullNodeInfo = await inlet.getFullInfo(timeout: 1.0);
              nodeInfo = await _parseNodeInfo(fullNodeInfo);
            }

            await _networkState.updateNode(nodeInfo);
          } catch (e) {
            logger.fine('Error processing coordinator stream: $e');
          }
        }
      }
    } catch (e) {
      logger.warning('Error checking for coordinator: $e');
    }
  }

  Future<void> _announceLeaving() async {
    try {
      final leaveMessage = CoordinationMessage(
        messageId: '${_nodeId}_leave_${DateTime.now().millisecondsSinceEpoch}',
        type: CoordinationMessageType.nodeLeft,
        payload: {
          'nodeId': _nodeId,
          'nodeName': _nodeName,
          'reason': 'Node leaving session',
          'timestamp': DateTime.now().toIso8601String(),
        },
        timestamp: DateTime.now(),
      );

      await _coordinationProtocol.sendMessage(leaveMessage);
      logger.info('Announced node departure: $_nodeId');
    } catch (e) {
      logger.warning('Failed to announce leaving: $e');
    }
  }

  Future<void> _announceStreamCreation(LSLStreamConfig config) async {
    try {
      final streamMessage = CoordinationMessage(
        messageId:
            '${_nodeId}_stream_create_${DateTime.now().millisecondsSinceEpoch}',
        type: CoordinationMessageType.custom,
        payload: {
          'action': 'stream_created',
          'nodeId': _nodeId,
          'streamId': config.id,
          'streamConfig': config.toMap(),
          'timestamp': DateTime.now().toIso8601String(),
        },
        timestamp: DateTime.now(),
      );

      await _coordinationProtocol.sendMessage(streamMessage);
      logger.info('Announced stream creation: ${config.id}');
    } catch (e) {
      logger.warning('Failed to announce stream creation: $e');
    }
  }

  Future<void> _announceStreamDestruction(String streamId) async {
    try {
      final streamMessage = CoordinationMessage(
        messageId:
            '${_nodeId}_stream_destroy_${DateTime.now().millisecondsSinceEpoch}',
        type: CoordinationMessageType.custom,
        payload: {
          'action': 'stream_destroyed',
          'nodeId': _nodeId,
          'streamId': streamId,
          'timestamp': DateTime.now().toIso8601String(),
        },
        timestamp: DateTime.now(),
      );

      await _coordinationProtocol.sendMessage(streamMessage);
      logger.info('Announced stream destruction: $streamId');
    } catch (e) {
      logger.warning('Failed to announce stream destruction: $e');
    }
  }

  void _handleNetworkStateChange(NetworkStateEvent event) {
    try {
      switch (event.runtimeType) {
        case NodeAdded:
          final nodeEvent = event as NodeAdded;
          _eventController.addEvent(NodeJoined(sessionId, nodeEvent.node));
          logger.info('Node joined: ${nodeEvent.node.nodeId}');
          break;

        case NodeRemoved:
          final nodeEvent = event as NodeRemoved;
          _eventController.addEvent(NodeLeft(sessionId, nodeEvent.node));
          logger.info('Node left: ${nodeEvent.node.nodeId}');
          break;

        case NetworkRoleChanged:
          final roleEvent = event as NetworkRoleChanged;
          if (roleEvent.nodeId == _nodeId) {
            _eventController.addEvent(
              RoleChanged(
                sessionId,
                roleEvent.oldRole,
                roleEvent.newRole,
                roleEvent.reason,
              ),
            );
            logger.info(
              'Role changed: ${roleEvent.oldRole} -> ${roleEvent.newRole} (${roleEvent.reason})',
            );
          }
          break;

        case NetworkTopologyChanged:
          final topologyEvent = event as NetworkTopologyChanged;
          _eventController.addEvent(
            TopologyChanged(
              sessionId,
              topologyEvent.oldTopology,
              topologyEvent.newTopology,
            ),
          );
          logger.info(
            'Topology changed: ${topologyEvent.oldTopology} -> ${topologyEvent.newTopology}',
          );
          break;

        default:
          logger.fine('Unhandled network state change: ${event.runtimeType}');
      }
    } catch (e) {
      logger.warning('Error handling network state change: $e');
    }
  }

  void _handleCoordinationMessage(IncomingCoordinationMessage message) {
    try {
      final msg = message.message;
      final fromNodeId = message.fromNodeId;

      logger.fine(
        'Processing coordination message: ${msg.type} from $fromNodeId',
      );

      switch (msg.type) {
        case CoordinationMessageType.heartbeat:
          _handleHeartbeatMessage(msg, fromNodeId);
          break;

        case CoordinationMessageType.nodeJoined:
          _handleNodeJoinedMessage(msg, fromNodeId);
          break;

        case CoordinationMessageType.nodeLeft:
          _handleNodeLeftMessage(msg, fromNodeId);
          break;

        case CoordinationMessageType.roleChange:
          _handleRoleChangeMessage(msg, fromNodeId);
          break;

        case CoordinationMessageType.streamRequest:
          _handleStreamRequestMessage(msg, fromNodeId);
          break;

        case CoordinationMessageType.custom:
          _handleCustomMessage(msg, fromNodeId);
          break;

        default:
          logger.fine('Unhandled coordination message type: ${msg.type}');
      }
    } catch (e) {
      logger.warning('Error handling coordination message: $e');
    }
  }

  void _handleElectionEvent(ElectionEvent event) {
    try {
      logger.info('Handling election event: ${event.runtimeType}');

      // This would be implemented based on the election protocol
      // For now, we'll log the event
      // In a full implementation, this would handle:
      // - ElectionStarted: participate in election
      // - ElectionWon: become leader/server
      // - ElectionLost: become client
      // - LeaderElected: update network state
    } catch (e) {
      logger.warning('Error handling election event: $e');
    }
  }

  // === MANAGED RESOURCE IMPLEMENTATION ===

  @override
  String get resourceId => sessionId;

  /// Resource state (implementing ManagedResource.resourceState)
  @override
  ResourceState get resourceState => _resourceState;

  @override
  Map<String, dynamic> get metadata => {
    'sessionId': sessionId,
    'nodeId': _nodeId,
    'sessionState': _state.toString(),
    'topology': topology.toString(),
    'role': role.toString(),
    'nodeCount': nodes.length,
    'streamCount': _dataStreams.length,
  };

  @override
  Stream<ResourceStateEvent> get stateChanges =>
      _resourceStateController.stream;

  @override
  Future<void> initialize() async {
    if (_resourceState != ResourceState.created) {
      throw CoordinationSessionException('Session already initialized');
    }

    _updateResourceState(ResourceState.initializing);

    // Initialize connection manager
    await _connectionManager.initialize();
    await _connectionManager.start();

    _updateResourceState(ResourceState.idle);
    logger.info('LSL coordination session initialized: $sessionId');
  }

  @override
  Future<void> activate() async {
    if (_resourceState != ResourceState.idle) {
      logger.warning('Session $sessionId not in idle state, cannot activate');
      return;
    }

    _updateResourceState(ResourceState.active);
    // Session activation is handled by join() method
    logger.info('LSL coordination session activated: $sessionId');
  }

  @override
  Future<void> deactivate() async {
    if (_resourceState != ResourceState.active) {
      logger.warning(
        'Session $sessionId not in active state, cannot deactivate',
      );
      return;
    }

    _updateResourceState(ResourceState.idle);
    // Stop heartbeat but don't leave the network
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    logger.info('LSL coordination session deactivated: $sessionId');
  }

  @override
  Future<void> dispose() async {
    if (_resourceState == ResourceState.disposed) {
      logger.warning('Session $sessionId already disposed');
      return;
    }

    _updateResourceState(ResourceState.stopping);

    try {
      // Leave the session if we haven't already
      if (_state != SessionState.disconnected) {
        await leave();
      }

      // Dispose all data streams
      final streamDisposeFutures = _dataStreams.values.map((stream) async {
        try {
          await stream.dispose();
        } catch (e) {
          logger.warning('Error disposing stream ${stream.streamId}: $e');
        }
      });
      await Future.wait(streamDisposeFutures);
      _dataStreams.clear();

      // Dispose connection manager
      await _connectionManager.dispose();

      // Clean up timers
      _heartbeatTimer?.cancel();
      _nodeDiscoveryTimer?.cancel();

      // Close resolvers
      _networkResolver?.destroy();
      _nodeResolver?.destroy();
      _peerResolver?.destroy();
      _coordinatorResolver?.destroy();
      _clientResolver?.destroy();

      // Close event controllers
      await _eventController.close();
      await _resourceStateController.close();

      _updateResourceState(ResourceState.disposed);
      logger.info('LSL coordination session disposed: $sessionId');
    } catch (e) {
      _updateResourceState(ResourceState.error);
      logger.severe('Error disposing session $sessionId: $e');
      rethrow;
    }
  }

  @override
  Future<bool> healthCheck() async {
    try {
      // Check if connection manager is healthy - just verify it responds
      _connectionManager.getUsageStats();

      // Check if we have the expected number of connections for our topology
      // (This is a basic health check - could be more sophisticated)

      // Check if data streams are healthy
      for (final stream in _dataStreams.values) {
        final isStreamHealthy = await stream.healthCheck();
        if (!isStreamHealthy) {
          logger.warning('Data stream ${stream.streamId} failed health check');
          return false;
        }
      }

      return true;
    } catch (e) {
      logger.warning('Health check failed for session $sessionId: $e');
      return false;
    }
  }

  /// Update the resource state and emit state change event
  void _updateResourceState(ResourceState newState, [String? reason]) {
    if (_resourceState == newState) return;

    final oldState = _resourceState;
    _resourceState = newState;

    final stateEvent = ResourceStateEvent(
      resourceId: sessionId,
      oldState: oldState,
      newState: newState,
      reason: reason,
      timestamp: DateTime.now(),
    );

    if (!_resourceStateController.isClosed) {
      _resourceStateController.add(stateEvent);
    }
    logger.fine(
      'Session $sessionId state changed: $oldState -> $newState ${reason != null ? '($reason)' : ''}',
    );
  }

  // === MESSAGE HANDLERS ===

  void _handleHeartbeatMessage(CoordinationMessage message, String fromNodeId) {
    try {
      // Update the node's last seen time
      final existingNode = nodes.firstWhere(
        (n) => n.nodeId == fromNodeId,
        orElse:
            () => NetworkNode(
              nodeId: fromNodeId,
              nodeName: 'Unknown_$fromNodeId',
              role: NodeRole.client,
              lastSeen: DateTime.now(),
            ),
      );

      final updatedNode = existingNode.copyWith(lastSeen: DateTime.now());
      _networkState.updateNode(updatedNode);
    } catch (e) {
      logger.fine('Error handling heartbeat from $fromNodeId: $e');
    }
  }

  void _handleNodeJoinedMessage(
    CoordinationMessage message,
    String fromNodeId,
  ) {
    try {
      final payload = message.payload;
      final nodeId = payload['nodeId'] as String;
      final nodeName = payload['nodeName'] as String? ?? 'Node_$nodeId';
      final roleString = payload['role'] as String? ?? 'client';

      NodeRole role;
      switch (roleString.toLowerCase()) {
        case 'server':
          role = NodeRole.server;
          break;
        case 'leader':
          role = NodeRole.leader;
          break;
        case 'peer':
          role = NodeRole.peer;
          break;
        default:
          role = NodeRole.client;
      }

      final newNode = NetworkNode(
        nodeId: nodeId,
        nodeName: nodeName,
        role: role,
        lastSeen: DateTime.now(),
        metadata: payload['metadata'] as Map<String, dynamic>? ?? {},
      );

      _networkState.updateNode(newNode);
    } catch (e) {
      logger.warning('Error handling node joined message: $e');
    }
  }

  void _handleNodeLeftMessage(CoordinationMessage message, String fromNodeId) {
    try {
      final payload = message.payload;
      final nodeId = payload['nodeId'] as String;

      _networkState.removeNode(nodeId);
    } catch (e) {
      logger.warning('Error handling node left message: $e');
    }
  }

  void _handleRoleChangeMessage(
    CoordinationMessage message,
    String fromNodeId,
  ) {
    try {
      final payload = message.payload;
      final nodeId = payload['nodeId'] as String;
      final newRoleString = payload['newRole'] as String;
      final reason = payload['reason'] as String? ?? 'Role change';

      NodeRole newRole;
      switch (newRoleString.toLowerCase()) {
        case 'server':
          newRole = NodeRole.server;
          break;
        case 'leader':
          newRole = NodeRole.leader;
          break;
        case 'peer':
          newRole = NodeRole.peer;
          break;
        default:
          newRole = NodeRole.client;
      }

      final existingNode = nodes.firstWhere(
        (n) => n.nodeId == nodeId,
        orElse:
            () => NetworkNode(
              nodeId: nodeId,
              nodeName: 'Node_$nodeId',
              role: NodeRole.client,
              lastSeen: DateTime.now(),
            ),
      );

      final updatedNode = existingNode.copyWith(
        role: newRole,
        lastSeen: DateTime.now(),
      );

      _networkState.updateNode(updatedNode);
    } catch (e) {
      logger.warning('Error handling role change message: $e');
    }
  }

  void _handleStreamRequestMessage(
    CoordinationMessage message,
    String fromNodeId,
  ) {
    try {
      final payload = message.payload;
      final requestingNodeId = payload['requestingNodeId'] as String;
      final streamConfigData = payload['streamConfig'] as Map<String, dynamic>;

      // Only coordinators should handle stream requests
      if (role == NodeRole.server || role == NodeRole.leader) {
        logger.info('Received stream request from $requestingNodeId');
        // In a full implementation, this would validate the request and
        // potentially create the requested stream or send a response
      }
    } catch (e) {
      logger.warning('Error handling stream request message: $e');
    }
  }

  void _handleCustomMessage(CoordinationMessage message, String fromNodeId) {
    try {
      final payload = message.payload;
      final action = payload['action'] as String?;

      switch (action) {
        case 'stream_created':
          final streamId = payload['streamId'] as String;
          logger.info('Node $fromNodeId created stream: $streamId');
          break;

        case 'stream_destroyed':
          final streamId = payload['streamId'] as String;
          logger.info('Node $fromNodeId destroyed stream: $streamId');
          break;

        default:
          logger.fine('Unhandled custom message action: $action');
      }
    } catch (e) {
      logger.warning('Error handling custom message: $e');
    }
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
