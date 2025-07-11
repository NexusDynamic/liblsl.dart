import 'dart:async';
import 'dart:io';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

/// Interactive demo application for testing coordination features
/// This demonstrates the real coordinator functionality in a controlled
/// environment
///
/// Usage:
/// ```
/// dart run example/unified_api_demo.dart
/// ```

void main() async {
  print('=== LibLSL Coordinator Unified API Demo ===');
  print('This demo shows the unified layer API in action.\n');

  // Check if we should run as coordinator or participant
  print('Choose mode:');
  print('1. Coordinator (starts first, manages network)');
  print('2. Participant (joins existing network)');
  print('3. Standalone (single device demo)');
  stdout.write('Enter choice (1-3): ');

  final choice = stdin.readLineSync();

  switch (choice) {
    case '1':
      await runCoordinatorDemo();
      break;
    case '2':
      await runParticipantDemo();
      break;
    case '3':
      await runStandaloneDemo();
      break;
    default:
      print('Invalid choice. Running standalone demo...');
      await runStandaloneDemo();
  }
}

/// Run as coordinator (manages the network)
Future<void> runCoordinatorDemo() async {
  print('\n=== Starting Coordinator Demo ===');

  final coordinator = MultiLayerCoordinator(
    nodeId: 'demo_coordinator',
    nodeName: 'Demo Coordinator',
    protocolConfig: ProtocolConfigs.gaming,
  );

  try {
    print('Initializing coordinator...');
    await coordinator.initialize();

    print('Joining network...');
    await coordinator.join();

    // Wait for initialization
    await Future.delayed(const Duration(seconds: 2));

    print('\n=== Coordinator Status ===');
    print('Node ID: ${coordinator.nodeId}');
    print('Node Name: ${coordinator.nodeName}');
    print('Role: ${coordinator.role}');
    print('Available Layers: ${coordinator.layers.layerIds}');

    // Test layer operations
    await demonstrateLayerOperations(coordinator);

    // Keep coordinator running
    print('\nCoordinator is running. Press Ctrl+C to stop.');
    print('Other devices can now join as participants.');

    // Listen for Ctrl+C
    ProcessSignal.sigint.watch().listen((_) async {
      print('\nShutting down coordinator...');
      await coordinator.dispose();
      exit(0);
    });

    // Keep alive
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
    }
  } catch (e) {
    print('Error in coordinator demo: $e');
  } finally {
    await coordinator.dispose();
  }
}

/// Run as participant (joins existing network)
Future<void> runParticipantDemo() async {
  print('\n=== Starting Participant Demo ===');

  final participant = MultiLayerCoordinator(
    nodeId: 'demo_participant_${DateTime.now().millisecondsSinceEpoch}',
    nodeName: 'Demo Participant',
    protocolConfig: ProtocolConfigs.gaming,
  );

  try {
    print('Initializing participant...');
    await participant.initialize();

    print('Looking for coordinator...');
    await Future.delayed(const Duration(seconds: 3));

    print('\n=== Participant Status ===');
    print('Node ID: ${participant.nodeId}');
    print('Node Name: ${participant.nodeName}');
    print('Role: ${participant.role}');
    print('Available Layers: ${participant.layers.layerIds}');

    // Test layer operations
    await demonstrateLayerOperations(participant);

    // Send some test data
    final gameLayer = participant.getLayer('game');
    if (gameLayer != null) {
      print('\nSending test data...');
      for (int i = 0; i < 5; i++) {
        await gameLayer.sendData([i * 10.0, i * 20.0, i * 1.0, i * 2.0]);
        print(
          'Sent game data: [${i * 10.0}, ${i * 20.0}, ${i * 1.0}, ${i * 2.0}]',
        );
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    print('\nParticipant demo completed.');
  } catch (e) {
    print('Error in participant demo: $e');
  } finally {
    await participant.dispose();
  }
}

/// Run standalone demo (single device)
Future<void> runStandaloneDemo() async {
  print('\n=== Starting Standalone Demo ===');

  final coordinator = MultiLayerCoordinator(
    nodeId: 'demo_standalone',
    nodeName: 'Demo Standalone',
    protocolConfig: ProtocolConfigs.full,
    coordinationConfig: CoordinationConfig(
      discoveryInterval: 0.5,
      heartbeatInterval: 0.5,
      nodeTimeout: 1.0,
      joinTimeout: 0.1,
    ),
  );

  try {
    print('Initializing coordinator...');
    await coordinator.initialize();

    print('Joining network...');
    await coordinator.join();

    // Wait for initialization
    await Future.delayed(const Duration(seconds: 1));

    print('\n=== Standalone Status ===');
    print('Node ID: ${coordinator.nodeId}');
    print('Node Name: ${coordinator.nodeName}');
    print('Role: ${coordinator.role}');
    print('Available Layers: ${coordinator.layers.layerIds}');

    // Demonstrate all features
    await demonstrateUnifiedAPI(coordinator);
    await demonstrateLayerOperations(coordinator);
    await demonstrateDataFlow(coordinator);

    print('\nStandalone demo completed.');
  } catch (e) {
    print('Error in standalone demo: $e');
  } finally {
    await coordinator.dispose();
  }
}

/// Demonstrate the unified layer API
Future<void> demonstrateUnifiedAPI(MultiLayerCoordinator coordinator) async {
  print('\n=== Unified API Demonstration ===');

  final layers = coordinator.layers;

  print('Available layers: ${layers.layerIds}');
  print('Layer count: ${layers.layerIds.length}');

  // Individual layer access
  for (final layerId in layers.layerIds) {
    final layer = coordinator.getLayer(layerId);
    if (layer != null) {
      print('Layer $layerId:');
      print('  - Name: ${layer.layerName}');
      print('  - Active: ${layer.isActive}');
      print('  - Pausable: ${layer.config.isPausable}');
      print('  - Priority: ${layer.config.priority}');
      print('  - Uses Isolate: ${layer.config.useIsolate}');
    }
  }

  // Collection operations
  final pausableLayers = layers.pausable;
  print('\nPausable layers: ${pausableLayers.map((l) => l.layerId).toList()}');

  final highPriorityLayers = layers.getByPriority(LayerPriority.high);
  print(
    'High priority layers: ${highPriorityLayers.map((l) => l.layerId).toList()}',
  );
}

/// Demonstrate layer operations
Future<void> demonstrateLayerOperations(
  MultiLayerCoordinator coordinator,
) async {
  print('\n=== Layer Operations Demonstration ===');

  final layers = coordinator.layers;
  final gameLayer = coordinator.getLayer('game');

  if (gameLayer != null) {
    print('\nTesting game layer operations:');

    // Pause/Resume
    print('  - Pausing game layer...');
    await gameLayer.pause();
    print('  - Game layer paused: ${gameLayer.isPaused}');

    print('  - Resuming game layer...');
    await gameLayer.resume();
    print('  - Game layer paused: ${gameLayer.isPaused}');

    // Data sending
    print('  - Sending game data...');
    await gameLayer.sendData([100.0, 200.0, 5.0, 10.0]);
    print('  - Game data sent successfully');
  }

  // Bulk operations
  print('\nTesting bulk operations:');
  print('  - Pausing all pausable layers...');
  await layers.pauseAll();

  final pausedLayers = layers.pausable.where((l) => l.isPaused).toList();
  print('  - Paused layers: ${pausedLayers.map((l) => l.layerId).toList()}');

  print('  - Resuming all paused layers...');
  await layers.resumeAll();

  final activeLayers = layers.pausable.where((l) => !l.isPaused).toList();
  print('  - Active layers: ${activeLayers.map((l) => l.layerId).toList()}');
}

/// Demonstrate data flow
Future<void> demonstrateDataFlow(MultiLayerCoordinator coordinator) async {
  print('\n=== Data Flow Demonstration ===');

  final layers = coordinator.layers;
  final gameLayer = coordinator.getLayer('game');
  final hiFreqLayer = coordinator.getLayer('hi_freq');

  // Set up data listeners
  final subscriptions = <StreamSubscription>[];

  if (gameLayer != null) {
    print('Setting up game layer data listener...');
    final sub = gameLayer.dataStream.listen((event) {
      print('Game data received from ${event.sourceNodeId}: ${event.data}');
    });
    subscriptions.add(sub);
  }

  if (hiFreqLayer != null) {
    print('Setting up hi-freq layer data listener...');
    final sub = hiFreqLayer.dataStream.listen((event) {
      print('Hi-freq data received from ${event.sourceNodeId}: ${event.data}');
    });
    subscriptions.add(sub);
  }

  // Combined stream
  final combinedStream = layers.getCombinedDataStream(['game', 'hi_freq']);
  final combinedSub = combinedStream.listen((event) {
    print('Combined stream - ${event.layerId}: ${event.data}');
  });
  subscriptions.add(combinedSub);

  // Send test data
  print('\nSending test data...');

  if (gameLayer != null) {
    await gameLayer.sendData([1.0, 2.0, 3.0, 4.0]);
    print('Game data sent');
  }

  if (hiFreqLayer != null) {
    await hiFreqLayer.sendData([
      10.0,
      20.0,
      30.0,
      40.0,
      50.0,
      60.0,
      70.0,
      80.0,
    ]);
    print('Hi-freq data sent');
  }

  // Wait for potential data
  await Future.delayed(const Duration(seconds: 2));

  // Cleanup
  for (final sub in subscriptions) {
    await sub.cancel();
  }

  print('Data flow demonstration completed.');
}

/// Demonstrate error handling
Future<void> demonstrateErrorHandling(MultiLayerCoordinator coordinator) async {
  print('\n=== Error Handling Demonstration ===');

  // Test invalid layer access
  final nonExistentLayer = coordinator.getLayer('nonexistent');
  print(
    'Accessing non-existent layer: ${nonExistentLayer == null ? 'null (expected)' : 'unexpected!'}',
  );

  // Test operations on empty collection
  final emptyCoordinator = MultiLayerCoordinator(
    nodeId: 'empty_test',
    nodeName: 'Empty Test',
    protocolConfig: ProtocolConfigs.basic,
  );

  try {
    await emptyCoordinator.initialize();

    final layers = emptyCoordinator.layers;
    print('Empty coordinator layers: ${layers.layerIds}');

    // These should not throw
    await layers.pauseAll();
    await layers.resumeAll();

    print('Empty collection operations handled gracefully');
  } finally {
    await emptyCoordinator.dispose();
  }
}
