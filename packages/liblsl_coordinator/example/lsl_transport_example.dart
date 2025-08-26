import 'dart:async';
import 'dart:math';

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

/// Minimal example demonstrating LSL transport coordination
/// 
/// This example shows:
/// 1. Event-driven coordination setup (no arbitrary delays)
/// 2. Using completers to wait for network state changes  
/// 3. Coordinator consuming its own data stream
/// 4. Proper coordination flow for single-node and multi-node scenarios
Future<void> main() async {
  print('🚀 Starting LSL Transport Example');
  
  // 1. Create session configuration  
  final sessionConfig = CoordinationSessionConfig(
    name: 'ExampleSession',
    heartbeatInterval: Duration(seconds: 1),
  );
  
  // 2. Create coordination configuration (meta-config)
  final coordinationConfig = CoordinationConfig(
    sessionConfig: sessionConfig,
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: 4,
    ),
    streamConfig: CoordinationStreamConfig(
      name: 'CoordinationChannel',
      sampleRate: 50.0,
    ),
    transportConfig: LSLTransportConfig(),
  );
  
  // 3. Create LSL coordination session
  final session = LSLCoordinationSession(coordinationConfig);
  
  // 3. Set up completers for network state
  final coordinationEstablished = Completer<void>();
  final dataStreamReady = Completer<LSLDataStream>();
  
  // 4. Set up event listeners
  _setupEventListeners(session, coordinationEstablished);
  
  // 5. Initialize and join the coordination network
  await session.initialize();
  print('📡 Session initialized, joining coordination network...');
  
  await session.join();
  
  // 6. Wait for coordination to be established (event-driven)
  print('⏳ Waiting for coordination to establish...');
  await coordinationEstablished.future;
  
  print('✅ Coordination established!');
  print('   Role: ${session.isCoordinator ? "Coordinator" : "Node"}');
  print('   Connected nodes: ${session.connectedNodes.length}');
  
  // 7. Create data stream now that coordination is ready
  print('📊 Creating data stream...');
  final dataStreamConfig = DataStreamConfig(
    name: 'ExperimentData',
    channels: 8,
    sampleRate: 500.0,  // 500 Hz
    dataType: StreamDataType.float32,
  );
  
  final dataStream = await session.createDataStream(dataStreamConfig);
  await dataStream.start();
  dataStreamReady.complete(dataStream);
  
  // 8. If we're the coordinator, set up to receive our own data
  if (session.isCoordinator) {
    print('🎯 Coordinator: Setting up to consume own data stream...');
    await _setupCoordinatorDataConsumption(dataStream);
  }
  
  // 9. Start data generation
  print('📈 Starting data generation...');
  await dataStreamReady.future;
  _startDataGeneration(dataStream);
  
  // 10. Coordinator coordination tasks
  if (session.isCoordinator) {
    _startCoordinatorTasks(session);
  }
  
  // 11. Send periodic status updates
  _startStatusUpdates(session);
  
  print('');
  print('✅ Example running! Network state:');
  print('   - Coordination: Established');
  print('   - Data stream: Active (${dataStream.sampleRate}Hz)');  
  print('   - Role: ${session.isCoordinator ? "Coordinator" : "Node"}');
  print('');
  print('🛑 Press Ctrl+C to stop');
  
  // Keep running until interrupted  
  await _waitForInterrupt();
  
  // Cleanup
  print('🧹 Cleaning up...');
  await dataStream.dispose();
  await session.leave();
  await session.dispose();
  print('👋 Example finished');
}

/// Sets up event listeners and completes coordination when established
void _setupEventListeners(
  LSLCoordinationSession session, 
  Completer<void> coordinationEstablished,
) {
  bool coordinationComplete = false;
  
  // Listen to coordination events
  session.coordinationEvents.listen((event) {
    print('🤝 Coordination: ${event.description}');
    
    // Complete coordination when we've joined the session
    if (event.id == 'joined_session' && !coordinationComplete) {
      coordinationComplete = true;
      coordinationEstablished.complete();
    }
  });
  
  // Listen to user events from other nodes
  session.userEvents.listen((event) {
    print('💬 User Event: ${event.description}');
    
    if (event.id == 'experiment_command') {
      final phase = event.getMetadata('phase', defaultValue: 'unknown');
      print('   🎯 Experiment command received: $phase');
    }
    
    if (event.id == 'data_collection_start') {
      print('   📊 Data collection phase started');
    }
  });
}

/// Sets up coordinator to consume its own data stream
Future<void> _setupCoordinatorDataConsumption(LSLDataStream dataStream) async {
  // Coordinator needs to create an inlet to its own outlet
  // This simulates the hierarchical topology where coordinator receives all data
  
  print('🔄 Coordinator creating inlet to consume own data...');
  
  // In a real scenario, the coordinator would discover its own stream
  // For this example, we'll simulate this by listening to the incoming stream
  dataStream.incoming.listen((data) {
    // Print every 100th sample to avoid spam (500Hz / 5 = 100Hz display rate)
    if (DateTime.now().millisecond % 20 == 0) {  // Approximate 50Hz display
      final summary = data.take(3).map((v) => v.toStringAsFixed(1)).join(', ');
      print('📥 Coordinator received: [$summary...] (${data.length} channels)');
    }
  });
  
  print('✅ Coordinator data consumption ready');
}

/// Starts coordinator-specific tasks
void _startCoordinatorTasks(LSLCoordinationSession session) {
  print('👑 Starting coordinator tasks...');
  
  // Send experiment commands periodically
  Timer.periodic(Duration(seconds: 10), (timer) {
    final phase = DateTime.now().second < 30 ? 'collection' : 'rest';
    
    session.sendUserEvent(UserEvent(
      id: 'experiment_command',
      description: 'Experiment phase: $phase',
      metadata: {
        'phase': phase,
        'timestamp': DateTime.now().toIso8601String(),
        'nodes_active': session.connectedNodes.length.toString(),
      },
    ));
    
    print('🎮 Coordinator sent experiment command: $phase');
  });
  
  // Send data collection start signal
  Timer(Duration(seconds: 3), () {
    session.sendUserEvent(UserEvent(
      id: 'data_collection_start', 
      description: 'Starting data collection phase',
      metadata: {'duration': '60s'},
    ));
  });
}

/// Starts periodic status updates from this node
void _startStatusUpdates(LSLCoordinationSession session) {
  Timer.periodic(Duration(seconds: 5), (timer) {
    session.sendUserEvent(UserEvent(
      id: 'node_status',
      description: 'Node operational status',
      metadata: {
        'node_id': session.thisNode.id,
        'is_coordinator': session.isCoordinator.toString(),
        'uptime': DateTime.now().toIso8601String(),
        'status': 'running',
      },
    ));
  });
}

/// Generates realistic experiment data at high frequency
void _startDataGeneration(LSLDataStream dataStream) {
  final random = Random();
  var sampleCount = 0;
  
  // Generate data at 500 Hz (2ms intervals)
  Timer.periodic(Duration(microseconds: 2000), (timer) {
    if (dataStream.disposed) {
      timer.cancel();
      return;
    }
    
    // Generate 8 channels of synthetic EEG-like data
    final timeInSeconds = sampleCount / dataStream.sampleRate;
    final data = List.generate(8, (channel) {
      // Each channel has different frequency characteristics
      final baseFreq = 8.0 + channel * 1.5; // 8-18.5 Hz range (alpha/beta)
      final amplitude = 20.0 + random.nextDouble() * 30; // 20-50 μV
      final noise = (random.nextDouble() - 0.5) * 5; // ±2.5 μV noise
      
      // Add some event-related potential occasionally
      final erp = sampleCount % 1000 < 50 ? 
        15 * exp(-((sampleCount % 1000) / 20.0)) : 0;
      
      return amplitude * sin(2 * pi * baseFreq * timeInSeconds) + noise + erp;
    });
    
    // Send the data sample
    dataStream.sendData(data);
    sampleCount++;
    
    // Print generation status every 5 seconds
    if (sampleCount % 2500 == 0) { // 2500 samples = 5 seconds at 500Hz
      final seconds = sampleCount / dataStream.sampleRate;
      print('📊 Generated $sampleCount samples (${seconds.toStringAsFixed(1)}s)');
    }
  });
  
  print('📊 Data generation started (${dataStream.channelCount} channels @ ${dataStream.sampleRate}Hz)');
}

/// Waits for interrupt signal (Ctrl+C)
Future<void> _waitForInterrupt() async {
  final completer = Completer<void>();
  
  // Auto-stop after 2 minutes for demo purposes
  Timer(Duration(minutes: 2), () {
    print('⏰ Demo auto-stopping after 2 minutes...');
    completer.complete();
  });
  
  return completer.future;
}