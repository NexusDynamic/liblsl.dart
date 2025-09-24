// packages/liblsl_coordinator/example/multi_node_coordination_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:logging/logging.dart';

/// Multi-node coordination test to verify election, joining, messaging, and stream management
Future<void> main(List<String> args) async {
  // Configure logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(Log.defaultPrinter);

  // Parse command line arguments
  final nodeCount = args.isNotEmpty ? int.tryParse(args[0]) ?? 3 : 3;

  /// Maxnodes includes the coordinator
  final maxNodes = args.length > 1
      ? int.tryParse(args[1]) ?? 2
      : 3; // Set low to test rejection
  final testDuration =
      args.length > 2 ? int.tryParse(args[2]) ?? 10 : 10; // seconds

  logger.info('🚀 Starting Multi-Node Coordination Test');
  logger.info('   Nodes to start: $nodeCount');
  logger.info('   Max nodes allowed: $maxNodes');
  logger.info('   Test duration: ${testDuration}s');
  logger.info(
    '   Expected: ${min(nodeCount, maxNodes)} nodes should join successfully',
  );
  logger.info('');
  final sessionSuffix = Random().nextInt(10000);

  // Start nodes concurrently with slight delays to test election
  final futures = <Future<void>>[];

  for (int i = 0; i < nodeCount; i++) {
    futures.add(
      _runNode(
        sessionName: 'TestSession_$sessionSuffix',
        nodeId: 'Node_$i',
        appId: 'TestApp_${Random().nextInt(1000)}',
        maxNodes: maxNodes,
        delay: Duration(milliseconds: i * 500), // Stagger starts
        testDuration: testDuration,
      ),
    );
  }

  // Wait for all nodes to complete
  try {
    await Future.wait(futures);
  } catch (e) {
    logger.info('❌ Test completed with errors: $e');
  }

  logger.info('🏁 Multi-node coordination test completed');

  // Give some time for cleanup
  await Future.delayed(Duration(seconds: 2));
  exit(0);
}

/// Run a single node instance
Future<void> _runNode({
  required String sessionName,
  required String nodeId,
  required String appId,
  required int maxNodes,
  required Duration delay,
  required int testDuration,
}) async {
  // Stagger the start times to test election
  if (delay > Duration.zero) {
    logger.info(
      '⏳ $nodeId: Waiting ${delay.inMilliseconds}ms before starting...',
    );
    await Future.delayed(delay);
  }

  logger.info('🎯 $nodeId: Initializing...');

  try {
    // Create session configuration with the specified maxNodes
    final sessionConfig = CoordinationSessionConfig(
      name: sessionName,
      heartbeatInterval: Duration(seconds: 1),
      discoveryInterval: Duration(seconds: 5),
      nodeTimeout: Duration(seconds: 10),
      maxNodes: maxNodes, // This will cause some nodes to be rejected
    );

    // Create coordination configuration
    final coordinationConfig = CoordinationConfig(
      name: appId,
      sessionConfig: sessionConfig,
      topologyConfig: HierarchicalTopologyConfig(
        promotionStrategy: PromotionStrategyRandom(),
        maxNodes: maxNodes,
      ),
      streamConfig: CoordinationStreamConfig(
        name: 'coordination',
        sampleRate: 50.0,
      ),
      transportConfig: LSLTransportConfig(
        // This LSL API config specifically restricts to IPv4 and local machine
        // these wont go over the network
        lslApiConfig: LSLApiConfig(
          ipv6: IPv6Mode.disable,
          portRange: 128,
          logLevel: -2, // -2 Error only -> 9 is the most verbose
          resolveScope: ResolveScope.link,
          listenAddress: '127.0.0.1', // Use loopback for testing
          addressesOverride: ['224.0.0.183'],
          knownPeers: ['127.0.0.1'],
        ),
        coordinationFrequency: 50.0,
      ),
    );

    final dataStreamConfig = DataStreamConfig(
      name: 'TestData',
      channels: 3, // timestamp, node_id, sample_count
      sampleRate: 10.0,
      dataType: StreamDataType.double64,
      participationMode: StreamParticipationMode.allNodes,
    );

    // Create session using the new simplified API
    final session = LSLCoordinationSession(coordinationConfig);

    // Set up comprehensive event listeners
    _setupEventListeners(session, nodeId);

    // Track test state
    bool joinSuccessful = false;
    bool testCompleted = false;

    logger.info('📡 $nodeId: Initializing session...');
    await session.initialize();

    logger.info('🔄 $nodeId: Attempting to join coordination network...');

    try {
      await session.join();
      joinSuccessful = true;

      final role = session.isCoordinator ? 'Coordinator' : 'Participant';
      logger.info('✅ $nodeId: Successfully joined as $role');
      logger.info('   Connected nodes: ${session.connectedNodes.length}');

      // Run role-specific logic
      if (session.isCoordinator) {
        await _runCoordinatorTestLogic(
          session,
          nodeId,
          testDuration,
          maxNodes,
          dataStreamConfig,
        );
      } else {
        await _runParticipantTestLogic(
          session,
          nodeId,
          testDuration,
          dataStreamConfig,
        );
      }

      testCompleted = true;
    } catch (e) {
      if (e.toString().contains('rejected')) {
        logger.info('🚫 $nodeId: Join rejected (expected if > maxNodes): $e');
        joinSuccessful = false;
      } else {
        logger.info('❌ $nodeId: Join failed unexpectedly: $e');
        rethrow;
      }
    }

    // Wait for test duration if joined successfully
    if (joinSuccessful && !testCompleted) {
      logger.info('⏱️ $nodeId: Running test for ${testDuration}s...');
      await Future.delayed(Duration(seconds: testDuration));
    }

    // Cleanup
    if (joinSuccessful) {
      logger.info('🧹 $nodeId: Cleaning up...');
      await session.leave();
      await session.dispose();
    }

    logger.info('🏁 $nodeId: Test completed successfully');
  } catch (e, stack) {
    logger.info('❌ $nodeId: Error during test: $e');
    logger.info('📜 $nodeId: Stack trace: $stack');
    rethrow;
  }
}

/// Set up comprehensive event listeners for testing
void _setupEventListeners(LSLCoordinationSession session, String nodeId) {
  // Phase changes
  session.phaseChanges.listen((phase) {
    logger.info('📊 $nodeId: Phase changed to $phase');
  });

  // Node topology changes
  session.nodeJoined.listen((node) {
    logger.info('➕ $nodeId: Node joined: ${node.name} (${node.id})');
    logger.info('   Total nodes: ${session.connectedNodes.length}');
  });

  session.nodeLeft.listen((node) {
    logger.info('➖ $nodeId: Node left: ${node.name} (${node.id})');
    logger.info('   Total nodes: ${session.connectedNodes.length}');
  });

  // User messages (coordination commands)
  session.userMessages.listen((message) {
    logger.info(
      '💬 $nodeId: User Message: ${message.messageId} - ${message.description}',
    );
    if (message.payload.isNotEmpty) {
      logger.info('   Payload: ${message.payload}');
    }
  });

  // Configuration updates
  session.configUpdates.listen((update) {
    logger.info('⚙️ $nodeId: Config Update: ${update.config}');
  });

  // Stream commands
  session.streamStartCommands.listen((command) {
    logger.info('▶️ $nodeId: Stream START command: ${command.streamName}');
    if (command.startAt != null) {
      logger.info('   Scheduled for: ${command.startAt}');
    }
  });

  session.streamStopCommands.listen((command) {
    logger.info('⏹️ $nodeId: Stream STOP command: ${command.streamName}');
  });
}

/// Coordinator test logic - manages the test sequence
Future<void> _runCoordinatorTestLogic(
  LSLCoordinationSession session,
  String nodeId,
  int testDuration,
  int maxNodes,
  DataStreamConfig streamConfig,
) async {
  logger.info('👑 $nodeId: Running COORDINATOR test logic');

  // Test sequence timeline
  final testSteps = [
    {'delay': 2, 'action': 'wait_for_nodes'},
    {'delay': 3, 'action': 'pause_accepting'},
    {'delay': 2, 'action': 'send_config'},
    {'delay': 3, 'action': 'create_streams'},
    {'delay': 2, 'action': 'start_data_collection'},
    {'delay': testDuration, 'action': 'start_test_phase_1'},
    {'delay': 2, 'action': 'pause_between_phases'},
    {'delay': 1, 'action': 'resume_for_phase_2'},
    {'delay': testDuration, 'action': 'start_test_phase_2'},
    {'delay': 2, 'action': 'pause_before_stop'},
    {'delay': 1, 'action': 'flush_and_resume'},
    {'delay': 3, 'action': 'stop_data_collection'},
    {'delay': 2, 'action': 'end_test'},
  ];

  var elapsedTime = 0;
  int messageCount = 0;
  StreamSubscription? inboxSubscription;
  LSLDataStream? dataStream;

  for (final step in testSteps) {
    final delay = step['delay'] as int;
    final action = step['action'] as String;

    await Future.delayed(Duration(seconds: delay));
    elapsedTime += delay;

    try {
      switch (action) {
        case 'wait_for_nodes':
          logger.info(
            '⏳ $nodeId: Waiting for [$maxNodes] participant nodes...',
          );
          try {
            await session.waitForMinNodes(
              maxNodes,
              timeout: Duration(seconds: 20),
            );
            logger.info(
              '✅ $nodeId: Participants joined (${session.connectedNodes.length} nodes)',
            );
          } catch (e) {
            logger.info(
              '⚠️ $nodeId: Timeout waiting for participants, continuing...',
            );
          }
          break;

        case 'pause_accepting':
          logger.info('🛑 $nodeId: Pausing acceptance of new nodes');
          await session.pauseAcceptingNodes();
          logger.info('   Is accepting nodes: ${session.isAcceptingNodes}');
          break;

        case 'send_config':
          logger.info('📋 $nodeId: Broadcasting test configuration...');
          await session.updateConfig({
            'test_type': 'multi_node_coordination',
            'test_duration': testDuration,
            'data_rate': 10.0,
            'channels': 3,
          });
          break;

        case 'create_streams':
          logger.info('📊 $nodeId: Creating test data stream...');

          dataStream = await session.createDataStream(streamConfig);

          inboxSubscription = dataStream.inbox.listen((data) {
            // logger.info('📥 $nodeId: Received data: $data');
            messageCount++;
          });
          break;

        case 'start_test_phase_1':
          logger.info('🎯 $nodeId: Starting test phase 1...');
          logger.info('   $nodeId: Current message count: $messageCount');
          await session.sendUserMessage(
            'start_test_phase',
            'Starting coordinated test - Phase 1',
            {
              'phase': 1,
              'intensity': 'low',
              'start_at':
                  DateTime.now().add(Duration(seconds: 5)).toIso8601String(),
            },
          );
          break;

        case 'start_data_collection':
          logger.info('📈 $nodeId: Starting data collection...');
          logger.info('   $nodeId: Current message count: $messageCount');
          await session.startStream('TestData');
          break;

        case 'pause_between_phases':
          logger.info('⏸️  $nodeId: Pausing data streams between phases...');
          logger.info('   $nodeId: Current message count: $messageCount');
          await session.pauseStream('TestData');
          logger.info(
            '   $nodeId: All nodes have paused busy-wait polling - system resources freed',
          );
          break;

        case 'resume_for_phase_2':
          logger.info('▶️  $nodeId: Resuming data streams for Phase 2...');
          await session.resumeStream('TestData', flushBeforeResume: true);
          logger.info('   $nodeId: All nodes resumed with fresh buffers');
          break;

        case 'start_test_phase_2':
          logger.info('🎯 $nodeId: Starting test phase 2...');
          logger.info('   $nodeId: Current message count: $messageCount');
          await session.sendUserMessage(
            'start_test_phase',
            'Starting coordinated test - Phase 2',
            {
              'phase': 2,
              'intensity': 'high',
              'start_at':
                  DateTime.now().add(Duration(seconds: 1)).toIso8601String(),
            },
          );
          break;

        case 'pause_before_stop':
          logger.info('⏸️  $nodeId: Pausing before final data collection...');
          logger.info('   $nodeId: Current message count: $messageCount');
          await session.pauseStream('TestData');
          break;

        case 'flush_and_resume':
          logger.info(
            '🚿 $nodeId: Flushing and resuming for final collection...',
          );
          await session.flushStream('TestData');
          await session.resumeStream('TestData', flushBeforeResume: false);
          logger.info(
            '   $nodeId: Streams flushed manually and resumed without auto-flush',
          );
          break;

        case 'stop_data_collection':
          logger.info('📉 $nodeId: Stopping data collection...');
          logger.info('   $nodeId: Current message count: $messageCount');
          await session.stopStream('TestData');
          break;

        case 'end_test':
          logger.info('🏁 $nodeId: Ending test...');
          await session.sendUserMessage('end_test', 'Test sequence completed', {
            'total_duration': elapsedTime,
            'final_node_count': session.connectedNodes.length,
          });
          logger.info('   $nodeId: FINAL message count: $messageCount');
          inboxSubscription?.cancel();
          break;
      }
    } catch (e, stack) {
      logger.info('❌ $nodeId: Error in step $action: $e');
      logger.info('📜 $nodeId: Stack trace: $stack');
    }
  }

  logger.info('✅ $nodeId: Coordinator test sequence completed');
}

/// Participant test logic - responds to coordinator commands
Future<void> _runParticipantTestLogic(
  LSLCoordinationSession session,
  String nodeId,
  int testDuration,
  DataStreamConfig streamConfig,
) async {
  logger.info('👤 $nodeId: Running PARTICIPANT test logic');

  int currentPhase = 0;
  String intensity = 'low';
  Timer? dataTimer;
  final nodeIdHash = nodeId.hashCode.abs() % 1000; // Unique ID for this node
  int messageReceivedCount = 0;
  StreamSubscription? inboxSubscription;

  // Listen for test commands
  session.userMessages.listen((message) async {
    switch (message.messageId) {
      case 'start_test_phase':
        final phase = message.payload['phase'] as int;
        intensity = message.payload['intensity'] as String;
        final startAtStr = message.payload['start_at'] as String;
        final startAt = DateTime.parse(startAtStr);

        logger.info(
          '🎯 $nodeId: Received phase command: Phase $phase ($intensity)',
        );
        logger.info('   Starting at: $startAt');

        currentPhase = phase;

        // Wait until the specified start time for synchronization
        final delay = startAt.difference(DateTime.now());
        if (delay.isNegative) {
          logger.info('⚡ $nodeId: Starting immediately (past scheduled time)');
        } else {
          logger.info(
            '⏱️ $nodeId: Waiting ${delay.inMilliseconds}ms for synchronized start',
          );
          await Future.delayed(delay);
        }

        logger.info('▶️ $nodeId: Phase $phase ($intensity) started!');

        /// show current message count
        logger.info('   $nodeId: Current message count: $messageReceivedCount');
        break;

      case 'end_test':
        logger.info('🏁 $nodeId: Test ended by coordinator');
        logger.info('   $nodeId: FINAL message count: $messageReceivedCount');
        dataTimer?.cancel();
        inboxSubscription?.cancel();
        final duration = message.payload['total_duration'];
        logger.info('   Total test duration: ${duration}s');
        break;
    }
  });

  // Listen for stream commands and generate data accordingly
  session.streamStartCommands.listen((command) async {
    final testStream = await session.getDataStream(command.streamName);
    inboxSubscription = testStream.inbox.listen((data) {
      // logger.info('📥 $nodeId: Received data: $data');
      messageReceivedCount++;
    });
    logger.info('📊 $nodeId: Data stream started: ${command.streamName}');
    dataTimer = _startDataGeneration(
      nodeId,
      nodeIdHash,
      testStream,
      () => currentPhase,
      () => intensity,
    );
  });

  session.streamReadyNotifications.listen((notification) async {
    logger.info(
      '✅ $nodeId: Stream ready acknowledged: ${notification.streamName}',
    );
  });

  session.streamStopCommands.listen((command) {
    logger.info('📊 $nodeId: Data stream stopped: ${command.streamName}');
    dataTimer?.cancel();
  });

  // Listen for pause/resume commands to show coordination working
  session.streamPauseCommands.listen((command) {
    logger.info(
      '⏸️  $nodeId: PARTICIPANT received pause command for ${command.streamName}',
    );
    logger.info(
      '   $nodeId: Busy-wait polling paused - freeing system resources',
    );
  });

  session.streamResumeCommands.listen((command) {
    logger.info(
      '▶️  $nodeId: PARTICIPANT received resume command for ${command.streamName}',
    );
    logger.info(
      '   $nodeId: Flush before resume: ${command.flushBeforeResume}',
    );
    logger.info('   $nodeId: Busy-wait polling resumed');
  });

  session.streamFlushCommands.listen((command) {
    logger.info(
      '🚿 $nodeId: PARTICIPANT received flush command for ${command.streamName}',
    );
    logger.info('   $nodeId: Stream buffers cleared');
  });

  session.streamDestroyCommands.listen((command) {
    logger.info(
      '💥 $nodeId: PARTICIPANT received destroy command for ${command.streamName}',
    );
    logger.info('   $nodeId: Stream resources completely destroyed');
  });

  logger.info(
    '⏳ $nodeId: Participant ready, waiting for coordinator commands...',
  );

  // Wait for the test duration or until test completes
  bool testCompleted = false;
  final testCompleter = Completer<void>();

  // Listen for test completion
  session.userMessages.listen((message) {
    if (message.messageId == 'end_test' && !testCompleted) {
      testCompleted = true;
      testCompleter.complete();
    }
  });

  // Wait for test completion or timeout
  try {
    await testCompleter.future.timeout(Duration(seconds: testDuration + 120));
  } on TimeoutException {
    logger.info('⏰ $nodeId: Participant test timeout, completing...');
  }
}

/// Generate test data for participants
Timer _startDataGeneration(
  String nodeId,
  int nodeIdHash,
  LSLDataStream testStream,
  int Function() getCurrentPhase,
  String Function() getIntensity,
) {
  final random = Random();
  var sampleCount = 0;

  final timer = Timer.periodic(Duration(milliseconds: 100), (timer) {
    // 10 Hz
    if (!testStream.started) {
      logger.info('🛑 $nodeId: Data stream stopped, ending data generation');
      timer.cancel();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final phase = getCurrentPhase();
    final intensity = getIntensity();

    // Generate data based on current phase and intensity
    var dataValue = random.nextDouble() * 100;
    if (intensity == 'high') {
      dataValue *= 2; // Higher amplitude for high intensity
    }

    // Add phase-specific patterns
    if (phase == 2) {
      dataValue += sin(sampleCount * 0.1) * 20; // Add sine wave in phase 2
    }

    final data = [
      now, // timestamp
      nodeIdHash.toDouble(), // node identifier
      dataValue, // sample value
    ];

    testStream.sendData(data);
    sampleCount++;

    // logger.info status every 2 seconds
    if (sampleCount % 20 == 0) {
      logger.info(
        '📈 $nodeId: Generated $sampleCount samples (Phase: $phase, Intensity: $intensity)',
      );
    }
  });

  logger.info('🎵 $nodeId: Data generation started (10 Hz)');
  return timer;
}
