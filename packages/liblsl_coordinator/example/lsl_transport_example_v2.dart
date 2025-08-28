import 'dart:async';
import 'dart:math';

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:logging/logging.dart';

/// Enhanced example demonstrating:
/// 1. Multi-app coordination with automatic discovery
/// 2. Isolate-based stream processing
/// 3. High-precision data streaming with busy-wait
/// 4. Type-safe data handling for different data types
/// 5. Experiment configuration broadcasting
Future<void> main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // Simple console logging
    print(
      '[${record.level.name}] ${record.time}: ${record.loggerName}: ${record.message}',
    );
  });
  print('🚀 Starting Enhanced LSL Coordination Example');

  // 1. Create session configuration
  final sessionConfig = CoordinationSessionConfig(
    name: 'MultiAppExperiment_2024', // Shared across all apps in experiment
    heartbeatInterval: Duration(seconds: 2),
    discoveryInterval: Duration(seconds: 3),
    nodeTimeout: Duration(seconds: 10),
    maxNodes: 10,
  );

  // 2. Create coordination configuration
  final coordinationConfig = CoordinationConfig(
    name: 'ExperimentApp_${Random().nextInt(1000)}', // Unique per app instance
    sessionConfig: sessionConfig,
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(), // Fair coordinator election
      maxNodes: 10,
    ),
    streamConfig: CoordinationStreamConfig(
      name: 'coordination',
      sampleRate: 50.0, // 50 Hz coordination messages
    ),
    transportConfig: LSLTransportConfig(coordinationFrequency: 50.0),
  );

  // 3. Create enhanced LSL session
  final session = LSLCoordinationSession(coordinationConfig);

  // 4. Set up event listeners for multi-app coordination
  _setupEnhancedEventListeners(session);

  // 5. Initialize and join with enhanced multi-app support
  print('📡 Initializing enhanced session...');
  await session.initialize();
  await session.join();

  print('✅ Enhanced coordination established!');
  print('   Role: ${session.isCoordinator ? "Coordinator" : "Participant"}');
  print('   Session: ${session.config.name}');
  print('   App ID: ${coordinationConfig.name}');

  // 6. Wait a moment for other apps to join
  await Future.delayed(Duration(seconds: 2));

  // 7. If coordinator, broadcast experiment configuration
  if (session.isCoordinator) {
    final experimentConfig = {
      'experiment_type': 'multi_modal_recording',
      'duration_seconds': 300,
      'trial_count': 10,
      'sampling_config': {
        'eeg_rate': 1000.0,
        'imu_rate': 100.0,
        'game_input_rate': 60.0,
      },
      'data_types': ['EEG', 'IMU', 'GameInput'],
    };

    print('📋 Broadcasting experiment configuration...');
    await session.broadcastExperimentConfig(experimentConfig);
  }

  // 8. Create different types of data streams with isolates

  // High-frequency float data (e.g., EEG)
  final eegStream = await _createEEGStream(session);

  // Integer data stream (e.g., game inputs)
  final gameInputStream = await _createGameInputStream(session);

  // String data stream (e.g., event markers)
  final markerStream = await _createMarkerStream(session);

  // 9. Start data generation/processing
  print('📊 Starting multi-stream data processing...');

  // Start EEG simulation (1000 Hz)
  _startEEGSimulation(eegStream);

  // Start game input simulation (60 Hz)
  _startGameInputSimulation(gameInputStream);

  // Start marker generation (occasional)
  _startMarkerGeneration(markerStream);

  // 10. If coordinator, aggregate and process all data
  if (session.isCoordinator) {
    print('🎯 Coordinator: Processing aggregated data from all nodes...');
    _processAggregatedData(eegStream, gameInputStream, markerStream);
  }

  // 11. Send status updates
  final statusBroadcastTimer = _startStatusBroadcast(session);

  print('');
  print('✅ Enhanced multi-app coordination running!');
  print('   - Multiple data streams active with type safety');
  print('   - Isolates handling I/O for zero main thread blocking');
  print('   - Busy-wait timing for high-precision data');
  print('   - Automatic multi-app discovery and coordination');
  print('');
  print('🛑 Press Ctrl+C to stop');

  // Keep running
  await _waitForInterrupt();

  // Cleanup
  print('🧹 Cleaning up...');

  // Cancel all timers first to prevent race conditions
  _running = false;
  _eegTimer?.cancel();
  _gameTimer?.cancel();
  statusBroadcastTimer.cancel();
  await eegStream.dispose();
  await gameInputStream.dispose();
  await markerStream.dispose();
  await session.leave();
  await session.dispose();
  print('👋 Enhanced example finished');
}

/// Set up event listeners for coordination events
void _setupEnhancedEventListeners(LSLCoordinationSession session) {
  // Coordination events
  session.coordinationEvents.listen((event) {
    print('🤝 Coordination Event: ${event.description}');

    if (event.id == 'config_updated') {
      print('   📋 Received experiment configuration:');
      event.metadata.forEach((key, value) {
        print('      $key: $value');
      });
    }

    if (event.id == 'node_joined') {
      print('   ➕ New node joined: ${event.getMetadata('nodeId')}');
    }

    if (event.id == 'coordination_established') {
      final isCoordinator = event.getMetadata('isCoordinator') == 'true';
      print('   ${isCoordinator ? '👑' : '👤'} Role established');
    }
  });

  // User events
  session.userEvents.listen((event) {
    print('💬 User Event: ${event.description}');

    if (event.id == 'data_stream_created') {
      final streamName = event.getMetadata('streamName');
      final dataType = event.getMetadata('dataType');
      print('   📊 Stream created: $streamName (type: $dataType)');
    }

    if (event.id == 'experiment_started') {
      print('   🎬 Experiment started!');
    }
  });
}

/// Create high-frequency EEG stream with float data
Future<LSLDataStream> _createEEGStream(LSLCoordinationSession session) async {
  final config = DataStreamConfig(
    name: 'EEG_Data',
    channels: 32, // 32 EEG channels
    sampleRate: 1000.0, // 1 kHz
    dataType: StreamDataType.float32,
  );

  final stream = await session.createDataStream(config);
  await stream.start();

  print('🧠 Created EEG stream (32ch @ 1000Hz, float32)');
  return stream;
}

/// Create game input stream with integer data
Future<LSLDataStream> _createGameInputStream(
  LSLCoordinationSession session,
) async {
  final config = DataStreamConfig(
    name: 'Game_Input',
    channels: 6, // x, y, buttons (4)
    sampleRate: 60.0, // 60 Hz
    dataType: StreamDataType.int16,
  );

  final stream = await session.createDataStream(config);
  await stream.start();

  print('🎮 Created game input stream (6ch @ 60Hz, int16)');
  return stream;
}

/// Create marker stream with string data
Future<LSLDataStream> _createMarkerStream(
  LSLCoordinationSession session,
) async {
  final config = DataStreamConfig(
    name: 'Event_Markers',
    channels: 1,
    sampleRate: 100.0, // Irregular rate
    dataType: StreamDataType.string,
    participationMode:
        StreamParticipationMode.allNodes, // All nodes receive markers
  );

  final stream = await session.createDataStream(config);
  await stream.start();

  // Listen for received marker data
  stream.inbox.listen((message) {
    if (message.data.isNotEmpty) {
      final marker = message.data.first;
      print('📥 Received marker: $marker');
    }
  });

  print('🏷️ Created marker stream (1ch, irregular, string)');
  return stream;
}

// Global timer references for cleanup
Timer? _eegTimer;
Timer? _gameTimer;
bool _running = true;

/// Simulate EEG data generation
void _startEEGSimulation(LSLDataStream stream) {
  final random = Random();
  var sampleCount = 0;

  // High-frequency timer (handled by isolate with busy-wait)
  _eegTimer = Timer.periodic(Duration(microseconds: 1000), (timer) {
    if (stream.disposed) {
      timer.cancel();
      return;
    }

    // Generate realistic EEG-like data
    final data = List.generate(32, (channel) {
      final baseFreq =
          10.0 + channel * 0.5; // Different frequencies per channel
      final amplitude = 50.0 + random.nextDouble() * 20; // 50-70 μV
      final noise = (random.nextDouble() - 0.5) * 5; // ±2.5 μV noise
      final t = sampleCount / stream.config.sampleRate;

      return amplitude * sin(2 * pi * baseFreq * t) + noise;
    });

    // Send through isolate-managed outlet
    stream.sendDataTyped<double>(data);
    sampleCount++;

    if (sampleCount % 10000 == 0) {
      // Log every 10 seconds
      print('🧠 EEG: ${sampleCount ~/ 1000}k samples sent');
    }
  });
}

/// Simulate game input
void _startGameInputSimulation(LSLDataStream stream) {
  final random = Random();
  var frameCount = 0;

  _gameTimer = Timer.periodic(Duration(milliseconds: 17), (timer) {
    // ~60 Hz
    if (stream.disposed) {
      timer.cancel();
      return;
    }

    // Simulate joystick and button inputs
    final data = [
      (random.nextDouble() * 100).round() - 50, // X axis (-50 to 50)
      (random.nextDouble() * 100).round() - 50, // Y axis
      random.nextBool() ? 1 : 0, // Button A
      random.nextBool() ? 1 : 0, // Button B
      random.nextBool() ? 1 : 0, // Button X
      random.nextBool() ? 1 : 0, // Button Y
    ];

    stream.sendDataTyped<int>(data);
    frameCount++;

    if (frameCount % 600 == 0) {
      // Log every 10 seconds
      print('🎮 Game: $frameCount frames sent');
    }
  });
}

/// Generate event markers
void _startMarkerGeneration(LSLDataStream stream) {
  final events = [
    'trial_start',
    'stimulus_on',
    'response',
    'stimulus_off',
    'trial_end',
    'rest_start',
    'rest_end',
    'block_start',
    'block_end',
  ];

  var eventCount = 0;

  // Random markers every 1-5 seconds
  void scheduleNextMarker() {
    if (!_running || stream.disposed) return;
    final delay = Duration(milliseconds: 1000 + Random().nextInt(4000));

    Timer(delay, () {
      if (!_running || stream.disposed) return;

      final marker = events[eventCount % events.length];
      stream.sendDataTyped<String>([marker]);

      print('🏷️ Marker: $marker');
      eventCount++;

      scheduleNextMarker();
    });
  }

  scheduleNextMarker();
}

/// Process aggregated data (coordinator only)
void _processAggregatedData(
  LSLDataStream eegStream,
  LSLDataStream gameStream,
  LSLDataStream markerStream,
) {
  // Listen to aggregated EEG data
  eegStream.dataStream.listen((data) {
    // Process high-frequency EEG data
    // The isolate handles the heavy lifting
    if (DateTime.now().millisecond % 1000 == 0) {
      final mean = data.take(4).reduce((a, b) => a + b) / 4;
      print('📥 EEG aggregate: mean=${mean.toStringAsFixed(2)}μV');
    }
  });

  // Listen to game inputs
  gameStream.dataStream.listen((data) {
    if (data.length >= 2) {
      final x = data[0];
      final y = data[1];
      if (x.abs() > 40 || y.abs() > 40) {
        print('📥 Game input spike: x=$x, y=$y');
      }
    }
  });

  // Listen to markers
  markerStream.inbox.listen((message) {
    if (message.data.isNotEmpty) {
      print('📥 Marker received: ${message.data[0]}');
    }
  });
}

/// Broadcast status updates
Timer _startStatusBroadcast(LSLCoordinationSession session) {
  return Timer.periodic(Duration(seconds: 10), (timer) {
    session.sendUserEvent(
      UserEvent(
        id: 'node_status',
        description: 'Operational status update',
        metadata: {
          'node_id': session.thisNode.id,
          'role': session.isCoordinator ? 'coordinator' : 'participant',
          'uptime': DateTime.now().toIso8601String(),
          'connected_nodes': session.connectedNodes.length.toString(),
        },
      ),
    );
  });
}

/// Wait for interrupt
Future<void> _waitForInterrupt() async {
  final completer = Completer<void>();

  // Auto-stop after 30 seconds for demo
  Timer(Duration(seconds: 30), () {
    print('⏰ Demo auto-stopping after 5 minutes...');
    completer.complete();
  });

  return completer.future;
}
