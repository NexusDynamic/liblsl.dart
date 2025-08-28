import 'dart:async';
import 'dart:math';

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:logging/logging.dart';

/// Multi-node coordination test
/// Tests automatic discovery, coordinator election, and bi-directional data flow
Future<void> main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(
      '[${record.level.name}] ${record.time}: ${record.loggerName}: ${record.message}',
    );
  });

  print('🚀 Starting Multi-Node Coordination Test');

  // Start both nodes concurrently with different delays
  final futures = <Future<void>>[];

  // Both nodes start simultaneously
  futures.add(
    _runNode(
      nodeId: 'Node1',
      appId: 'TestApp_${Random().nextInt(1000)}',
      delay: Duration.zero,
      nodeRole: 'primary',
    ),
  );

  futures.add(
    _runNode(
      nodeId: 'Node2',
      appId: 'TestApp_${Random().nextInt(1000)}',
      delay: Duration.zero, // Start at the same time!
      nodeRole: 'secondary',
    ),
  );

  // Wait for both nodes to run
  await Future.wait(futures);
}

Future<void> _runNode({
  required String nodeId,
  required String appId,
  required Duration delay,
  required String nodeRole,
}) async {
  // Stagger the start times
  if (delay > Duration.zero) {
    print('⏳ $nodeId: Waiting ${delay.inSeconds}s before starting...');
    await Future.delayed(delay);
  }

  print('🎯 $nodeId: Initializing...');

  try {
    // Create session configuration
    final sessionConfig = CoordinationSessionConfig(
      name: 'MultiNodeTest_2024',
      heartbeatInterval: Duration(seconds: 1),
      discoveryInterval: Duration(seconds: 2), // Faster discovery
      nodeTimeout: Duration(seconds: 8), // Shorter timeout for faster election
      maxNodes: 10,
    );

    // Create coordination configuration for this node
    final coordinationConfig = CoordinationConfig(
      name: appId,
      sessionConfig: sessionConfig,
      topologyConfig: HierarchicalTopologyConfig(
        promotionStrategy: PromotionStrategyRandom(),
        maxNodes: 10,
      ),
      streamConfig: CoordinationStreamConfig(
        name: 'coordination',
        sampleRate: 50.0,
      ),
      transportConfig: LSLTransportConfig(coordinationFrequency: 50.0),
    );

    // Create session
    final session = LSLCoordinationSession(coordinationConfig);

    // Simple debugging without events for now

    print('📡 $nodeId: Joining coordination network...');
    await session.initialize();

    print('🔄 $nodeId: Starting join process...');
    await session.join();
    print('✅ $nodeId: Join completed!');

    // Wait for coordination to establish
    await Future.delayed(Duration(seconds: 2));

    final role = session.isCoordinator ? 'Coordinator' : 'Participant';
    print('✅ $nodeId: Coordination established! Role: $role');

    // Create a data stream for this node
    final streamConfig = DataStreamConfig(
      name: '${nodeId}_Data',
      sampleRate: 100.0, // 100Hz
      channels: 2,
      dataType: StreamDataType.double64,
      participationMode: StreamParticipationMode.allNodes, // Fully connected!
    );

    print('📊 $nodeId: Creating data stream ${streamConfig.name}...');
    final dataStream = await session.createDataStream(streamConfig);

    // Start the stream
    await dataStream.start();
    print('🎵 $nodeId: Data stream ${streamConfig.name} started');

    // Subscribe to incoming data
    int messageCount = 0;
    dataStream.inbox.listen((message) {
      messageCount++;
      if (messageCount <= 5 || messageCount % 20 == 0) {
        print('📥 $nodeId: Received data: ${message.data}');
      }
    });

    // Send some test data
    final sendTimer = Timer.periodic(Duration(milliseconds: 100), (
      timer,
    ) async {
      final timestamp = DateTime.now();
      final sampleData = [
        sin(timestamp.millisecondsSinceEpoch / 1000.0) * 100, // Sine wave
        cos(timestamp.millisecondsSinceEpoch / 1000.0) * 50, // Cosine wave
      ];

      final message = MessageFactory.double64Message(
        data: sampleData,
        channels: 2,
        timestamp: timestamp,
      );

      await dataStream.sendMessage(message);

      // Stop after 10 seconds
      if (timer.tick > 100) {
        timer.cancel();
        print('🛑 $nodeId: Stopping data transmission');
      }
    });

    // Wait for the test to complete
    await Future.delayed(Duration(seconds: 12));
    sendTimer.cancel();

    print('📈 $nodeId: Final stats - Received $messageCount messages');
    await dataStream.stop();
    // Cleanup
    await dataStream.dispose();
    await session.dispose();

    print('🏁 $nodeId: Test completed successfully!');
  } catch (e, stack) {
    print('❌ $nodeId: Error during test: $e');
    print('📜 $nodeId: Stack trace: $stack');
  }
}
