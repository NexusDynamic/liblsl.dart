import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/src/coordination/core/coordination_config.dart';

/// Comprehensive example showing both coordination and high-performance gaming features
void main() async {
  await runBasicCoordinationExample();
  print('\n${'=' * 50}\n');
  await runGamingCoordinationExample();
}

/// Basic coordination example
Future<void> runBasicCoordinationExample() async {
  print('=== Basic Coordination Example ===');

  // Create basic coordination node
  final node = LSLCoordinationNode(
    nodeId: 'device_001',
    nodeName: 'Test Device 1',
    streamName: 'coordination_test',
    config: CoordinationConfig(
      discoveryInterval: 2.0,
      heartbeatInterval: 1.0,
      nodeTimeout: 5.0,
      capabilities: {'device_type': 'eeg', 'sample_rate': 250},
    ),
  );

  // Listen for events
  node.eventStream.listen((event) {
    switch (event) {
      case RoleChangedEvent():
        print('Role changed: ${event.oldRole} -> ${event.newRole}');
        break;
      case NodeJoinedEvent():
        print('Node joined: ${event.nodeName} (${event.nodeId})');
        break;
      case NodeLeftEvent():
        print('Node left: ${event.nodeId}');
        break;
      case TopologyChangedEvent():
        print('Network topology: ${event.nodes.length} nodes');
        break;
      case ApplicationEvent():
        print('App event: ${event.type} - ${event.data}');
        break;
    }
  });

  try {
    // Initialize and join network
    await node.initialize();
    await node.join();

    // Wait to become coordinator or participant
    await node
        .waitForRole(NodeRole.coordinator)
        .timeout(Duration(seconds: 10))
        .catchError((_) => node.waitForRole(NodeRole.participant));

    if (node.role == NodeRole.coordinator) {
      print('I am the coordinator!');

      // Wait for some participants
      try {
        final nodes = await node.waitForNodes(
          2,
          timeout: Duration(seconds: 10),
        );
        print('Network ready with ${nodes.length} nodes');
      } catch (e) {
        print(
          'Timeout waiting for participants, continuing with current nodes',
        );
      }

      // Send application messages
      await node.sendApplicationMessage('test_start', {
        'test_id': 'latency_001',
        'duration': 30,
      });
    } else {
      print('I am a participant, coordinator is: ${node.coordinatorId}');
    }

    // Keep running briefly
    await Future.delayed(Duration(seconds: 5));
  } finally {
    // Clean up
    await node.dispose();
  }
}

/// High-performance gaming coordination example
Future<void> runGamingCoordinationExample() async {
  print('=== Gaming Coordination Example ===');

  // Create gaming coordination node with high-performance capabilities
  final gameNode = GamingCoordinationNode(
    nodeId: 'player_001',
    nodeName: 'Player 1',
    coordinationStreamName: 'game_coordination',
    gameDataStreamName: 'game_data',
    coordinationConfig: CoordinationConfig(
      discoveryInterval: 1.0,
      heartbeatInterval: 0.5,
      nodeTimeout: 3.0,
      capabilities: {
        'player_type': 'human',
        'supports_high_frequency': true,
        'max_latency_ms': 16, // 60 FPS tolerance
      },
    ),
    gameDataConfig: HighFrequencyConfig(
      targetFrequency: 120.0, // 120 Hz for smooth gameplay
      useBusyWait: true,
      bufferSize: 1000,
      useIsolate: true,
    ),
  );

  // Listen for game events
  gameNode.gameEventStream.listen((event) {
    switch (event.type) {
      case GameEventType.roleChanged:
        print('Game role changed: ${event.data}');
        break;
      case GameEventType.playerJoined:
        print(
          'Player joined: ${event.data['node_name']} (${event.data['node_id']})',
        );
        break;
      case GameEventType.playerLeft:
        print('Player left: ${event.data['node_id']}');
        break;
      case GameEventType.playerAction:
        print(
          'Player action: ${event.data['action_type']} from ${event.senderId}',
        );
        break;
      case GameEventType.gameStateUpdate:
        print('Game state update: ${event.data['state_type']}');
        break;
      case GameEventType.syncPulse:
        final latency =
            DateTime.now().microsecondsSinceEpoch -
            (event.data['timestamp'] as int);
        print('Sync pulse latency: $latency μs');
        break;
      default:
        print('Game event: ${event.type} - ${event.data}');
        break;
    }
  });

  try {
    // Initialize gaming node
    await gameNode.initialize();
    await gameNode.join();

    // Configure for optimal gaming performance
    await gameNode.configureGamePerformance(
      targetFPS: 120.0,
      useBusyWait: true,
      maxLatencyMs: 8,
    );

    // Wait to become game coordinator or player
    await gameNode
        .waitForRole(NodeRole.coordinator)
        .timeout(Duration(seconds: 10))
        .catchError((_) => gameNode.waitForRole(NodeRole.participant));

    if (gameNode.isGameCoordinator) {
      print('I am the game coordinator!');

      // Start a game session
      final sessionConfig = GameSessionConfig(
        sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
        gameType: 'multiplayer_test',
        maxPlayers: 4,
        gameSettings: {
          'map': 'test_arena',
          'difficulty': 'normal',
          'duration_minutes': 10,
        },
        startDelay: Duration(seconds: 5),
      );

      await gameNode.startGameSession(sessionConfig);
      print('Game session started: ${sessionConfig.sessionId}');

      // Simulate game coordinator behavior
      await _simulateGameCoordinator(gameNode);
    } else {
      print('I am a player, coordinator is: ${gameNode.gameCoordinatorId}');

      // Join the game session
      await gameNode.joinGameSession('multiplayer_session');

      // Simulate player behavior
      await _simulatePlayer(gameNode);
    }

    // Monitor performance
    final metrics = gameNode.gamePerformanceMetrics;
    print('Game Performance Metrics:');
    print(
      '  Actual frequency: ${metrics.actualFrequency.toStringAsFixed(1)} Hz',
    );
    print('  Time corrections (LSL): ${metrics.timeCorrections}');
    print('  Messages processed: ${metrics.samplesProcessed}');
    print('  Dropped messages: ${metrics.droppedSamples}');
  } finally {
    // Clean up
    await gameNode.dispose();
  }
}

/// Simulate game coordinator behavior
Future<void> _simulateGameCoordinator(GamingCoordinationNode gameNode) async {
  print('Starting coordinator simulation...');

  // Send periodic sync pulses
  final syncTimer = Stream.periodic(Duration(milliseconds: 100), (i) => i)
      .take(50) // Run for 5 seconds
      .listen((_) async {
        await gameNode.sendSyncPulse();
      });

  // Send game state updates
  final stateTimer = Stream.periodic(
        Duration(milliseconds: 33),
        (i) => i,
      ) // ~30 FPS
      .take(150) // Run for 5 seconds
      .listen((frame) async {
        final gameState = GameState(
          stateType: 'world_update',
          data: {
            'frame': frame,
            'timestamp': DateTime.now().microsecondsSinceEpoch,
            'world_state': {
              'time': frame * 33, // milliseconds
              'entities': [
                {'id': 'entity_1', 'x': frame % 100, 'y': 50},
                {'id': 'entity_2', 'x': 50, 'y': frame % 100},
              ],
            },
          },
        );

        await gameNode.sendGameStateUpdate(gameState);
      });

  await Future.delayed(Duration(seconds: 5));
  syncTimer.cancel();
  stateTimer.cancel();
}

/// Simulate player behavior
Future<void> _simulatePlayer(GamingCoordinationNode gameNode) async {
  print('Starting player simulation...');

  // Send player actions
  final actionTimer = Stream.periodic(Duration(milliseconds: 50), (i) => i)
      .take(100) // Run for 5 seconds
      .listen((actionCount) async {
        final action = PlayerAction(
          actionType: 'move',
          data: {
            'direction': ['up', 'down', 'left', 'right'][actionCount % 4],
            'speed': 1.0,
            'timestamp': DateTime.now().microsecondsSinceEpoch,
          },
          isTimeCritical: true,
        );

        await gameNode.sendPlayerAction(action);
      });

  await Future.delayed(Duration(seconds: 5));
  actionTimer.cancel();
}
