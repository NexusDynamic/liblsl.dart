import 'dart:async';

import '../core/coordination_config.dart';
import '../core/coordination_node.dart';
import '../core/coordination_message.dart';
import '../core/leader_election.dart';
import 'lsl_coordination_node.dart';
import 'high_frequency_transport.dart';

/// Enhanced coordination node designed for multiplayer gaming scenarios
/// Combines regular coordination with high-performance data streaming
class GamingCoordinationNode implements CoordinationNode {
  final LSLCoordinationNode _coordinationNode;
  final HighFrequencyLSLTransport _gameDataTransport;

  final StreamController<GameEvent> _gameEventController =
      StreamController<GameEvent>.broadcast();

  GamingCoordinationNode({
    required String nodeId,
    required String nodeName,
    required String coordinationStreamName,
    required String gameDataStreamName,
    CoordinationConfig? coordinationConfig,
    HighFrequencyConfig? gameDataConfig,
    LeaderElectionStrategy? leaderElection,
  }) : _coordinationNode = LSLCoordinationNode(
         nodeId: nodeId,
         nodeName: nodeName,
         streamName: coordinationStreamName,
         config: coordinationConfig,
         leaderElection: leaderElection,
       ),
       _gameDataTransport = HighFrequencyLSLTransport(
         streamName: gameDataStreamName,
         nodeId: nodeId,
         performanceConfig: gameDataConfig,
         receiveOwnMessages:
             coordinationConfig != null
                 ? coordinationConfig.receiveOwnMessages
                 : true,
       ) {
    // Forward coordination events as game events
    _coordinationNode.eventStream.listen((event) {
      _gameEventController.add(GameEvent.fromCoordinationEvent(event));
    });

    // Forward high-performance messages as game events
    _gameDataTransport.highPerformanceMessageStream.listen((message) {
      if (message is ApplicationMessage) {
        _gameEventController.add(
          GameEvent.gameData(
            type: message.applicationType,
            data: message.payload,
            timestamp: message.timestamp,
            senderId: message.senderId,
          ),
        );
      }
    });
  }

  @override
  String get nodeId => _coordinationNode.nodeId;

  @override
  String get nodeName => _coordinationNode.nodeName;

  @override
  NodeRole get role => _coordinationNode.role;

  @override
  bool get isActive => _coordinationNode.isActive;

  @override
  Stream<CoordinationEvent> get eventStream => _coordinationNode.eventStream;

  /// Stream of game-specific events
  Stream<GameEvent> get gameEventStream => _gameEventController.stream;

  /// Get current game performance metrics
  HighFrequencyMetrics get gamePerformanceMetrics =>
      _gameDataTransport.performanceMetrics;

  /// Get list of nodes participating in the game
  List<NetworkNode> get gameParticipants => _coordinationNode.knownNodes;

  /// Check if this node is the game coordinator
  bool get isGameCoordinator => role == NodeRole.coordinator;

  /// Get the game coordinator's ID
  String? get gameCoordinatorId => _coordinationNode.coordinatorId;

  @override
  Future<void> initialize() async {
    await _coordinationNode.initialize();
    await _gameDataTransport.initialize();
  }

  @override
  Future<void> join() async {
    await _coordinationNode.join();
  }

  @override
  Future<void> leave() async {
    await _coordinationNode.leave();
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    await _coordinationNode.sendMessage(message);
  }

  /// Send a game data message with high-performance transport
  Future<void> sendGameData(List<dynamic> channelData) async {
    await _gameDataTransport.sendGameData(channelData);
  }

  /// Send a game data message (legacy format for backward compatibility)
  Future<void> sendGameDataMessage(
    String type,
    Map<String, dynamic> data, {
    bool highPriority = false,
  }) async {
    // Convert legacy format to coordination message
    await sendCoordinationMessage(type, data);
  }

  /// Send coordination message (lower priority, standard transport)
  Future<void> sendCoordinationMessage(
    String type,
    Map<String, dynamic> data,
  ) async {
    await _coordinationNode.sendApplicationMessage(type, data);
  }

  /// Wait for this node to reach a specific role
  Future<void> waitForRole(NodeRole targetRole, {Duration? timeout}) async {
    await _coordinationNode.waitForRole(targetRole, timeout: timeout);
  }

  /// Wait for a specific number of nodes to join the game
  Future<List<NetworkNode>> waitForPlayers(
    int minPlayers, {
    Duration? timeout,
  }) async {
    return await _coordinationNode.waitForNodes(minPlayers, timeout: timeout);
  }

  /// Configure game data polling for optimal performance
  Future<void> configureGamePerformance({
    double? targetFPS,
    bool? useBusyWait,
    int? maxLatencyMs,
  }) async {
    double? frequency;

    if (targetFPS != null) {
      frequency = targetFPS;
    }

    await _gameDataTransport.configureRealTimePolling(
      frequency: frequency,
      useBusyWait: useBusyWait,
    );
  }

  /// Start a multiplayer game session
  Future<void> startGameSession(GameSessionConfig config) async {
    if (!isGameCoordinator) {
      throw StateError('Only the game coordinator can start a session');
    }

    await sendCoordinationMessage('game_session_start', {
      'session_id': config.sessionId,
      'game_type': config.gameType,
      'max_players': config.maxPlayers,
      'settings': config.gameSettings,
      'start_time':
          DateTime.now().add(config.startDelay).millisecondsSinceEpoch,
    });
  }

  /// Join an existing game session
  Future<void> joinGameSession(String sessionId) async {
    await sendCoordinationMessage('game_session_join', {
      'session_id': sessionId,
      'player_id': nodeId,
      'player_name': nodeName,
      'capabilities': {'supports_high_frequency': true},
    });
  }

  /// Send player input/action to other players
  Future<void> sendPlayerAction(PlayerAction action) async {
    await sendGameDataMessage(
      'player_action',
      action.toMap(),
      highPriority: action.isTimeCritical,
    );
  }

  /// Send game state update (typically from coordinator)
  Future<void> sendGameStateUpdate(GameState state) async {
    await sendGameDataMessage(
      'game_state_update',
      state.toMap(),
      highPriority: true,
    );
  }

  /// Send synchronization pulse for timing coordination
  Future<void> sendSyncPulse() async {
    await sendGameDataMessage('sync_pulse', {
      'timestamp': DateTime.now().microsecondsSinceEpoch,
      'sequence': DateTime.now().millisecondsSinceEpoch % 1000000,
    }, highPriority: true);
  }

  /// Send simple single-channel int event
  Future<void> sendEvent(int eventCode) async {
    await _gameDataTransport.sendEvent(eventCode);
  }

  /// Send two-channel int data (e.g., event + response value)
  Future<void> sendEventWithValue(int eventCode, int value) async {
    await _gameDataTransport.sendEventWithValue(eventCode, value);
  }

  /// Send multi-channel double data (e.g., position coordinates)
  Future<void> sendPositionData(List<double> coordinates) async {
    await _gameDataTransport.sendPositionData(coordinates);
  }

  @override
  Future<void> dispose() async {
    await _gameEventController.close();
    await _coordinationNode.dispose();
    await _gameDataTransport.dispose();
  }
}

/// Configuration for a multiplayer game session
class GameSessionConfig {
  final String sessionId;
  final String gameType;
  final int maxPlayers;
  final Map<String, dynamic> gameSettings;
  final Duration startDelay;

  const GameSessionConfig({
    required this.sessionId,
    required this.gameType,
    required this.maxPlayers,
    required this.gameSettings,
    this.startDelay = const Duration(seconds: 3),
  });
}

/// Represents a player action in the game
class PlayerAction {
  final String actionType;
  final Map<String, dynamic> data;
  final bool isTimeCritical;
  final DateTime timestamp;

  PlayerAction({
    required this.actionType,
    required this.data,
    this.isTimeCritical = false,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toMap() => {
    'action_type': actionType,
    'data': data,
    'is_time_critical': isTimeCritical,
    'timestamp': timestamp.microsecondsSinceEpoch,
  };

  factory PlayerAction.fromMap(Map<String, dynamic> map) {
    return PlayerAction(
      actionType: map['action_type'],
      data: Map<String, dynamic>.from(map['data']),
      isTimeCritical: map['is_time_critical'] ?? false,
    );
  }
}

/// Represents the current game state
class GameState {
  final String stateType;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  GameState({required this.stateType, required this.data})
    : timestamp = DateTime.now();

  Map<String, dynamic> toMap() => {
    'state_type': stateType,
    'data': data,
    'timestamp': timestamp.microsecondsSinceEpoch,
  };

  factory GameState.fromMap(Map<String, dynamic> map) {
    return GameState(
      stateType: map['state_type'],
      data: Map<String, dynamic>.from(map['data']),
    );
  }
}

/// Enhanced event type for gaming scenarios
class GameEvent {
  final GameEventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String? senderId;

  GameEvent({
    required this.type,
    required this.data,
    DateTime? timestamp,
    this.senderId,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a game event from a coordination event
  factory GameEvent.fromCoordinationEvent(CoordinationEvent event) {
    GameEventType type;
    Map<String, dynamic> data = {};
    String? senderId;

    switch (event) {
      case RoleChangedEvent():
        type = GameEventType.roleChanged;
        data = {'old_role': event.oldRole.name, 'new_role': event.newRole.name};
        break;
      case NodeJoinedEvent():
        type = GameEventType.playerJoined;
        data = {'node_id': event.nodeId, 'node_name': event.nodeName};
        senderId = event.nodeId;
        break;
      case NodeLeftEvent():
        type = GameEventType.playerLeft;
        data = {'node_id': event.nodeId};
        senderId = event.nodeId;
        break;
      case ApplicationEvent():
        type = GameEventType.coordination;
        data = event.data;
        break;
      default:
        type = GameEventType.other;
        data = {'event': event.toString()};
        break;
    }

    return GameEvent(type: type, data: data, senderId: senderId);
  }

  /// Create a game data event
  factory GameEvent.gameData({
    required String type,
    required Map<String, dynamic> data,
    required DateTime timestamp,
    String? senderId,
  }) {
    GameEventType eventType;
    switch (type) {
      case 'player_action':
        eventType = GameEventType.playerAction;
        break;
      case 'game_state_update':
        eventType = GameEventType.gameStateUpdate;
        break;
      case 'sync_pulse':
        eventType = GameEventType.syncPulse;
        break;
      default:
        eventType = GameEventType.gameData;
        break;
    }

    return GameEvent(
      type: eventType,
      data: data,
      timestamp: timestamp,
      senderId: senderId,
    );
  }
}

/// Types of game events
enum GameEventType {
  // Coordination events
  roleChanged,
  playerJoined,
  playerLeft,
  coordination,

  // Game-specific events
  playerAction,
  gameStateUpdate,
  syncPulse,
  gameData,

  // Other
  other,
}
