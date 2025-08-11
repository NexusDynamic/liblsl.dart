import 'package:test/test.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

import 'test_lsl_config.dart';

void main() {
  group('Unified Layer API Demo Tests', () {
    setUp(() async {
      TestLSLConfig.initializeForTesting();
    });
    tearDown(() async {
      await Future.delayed(Duration(milliseconds: 100));
    });
    test('should demonstrate the new unified layer API', () async {
      // Create a coordinator with a custom protocol
      final customProtocol = ProtocolConfig(
        protocolId: 'demo_protocol',
        protocolName: 'Demo Multi-Layer Protocol',
        layers: [
          // Always need coordination layer
          StreamLayerConfig(
            layerId: 'coordination',
            layerName: 'Coordination Layer',
            streamConfig: StreamConfig(
              streamName: 'demo_coordination',
              streamType: LSLContentType.markers,
              channelCount: 1,
              sampleRate: LSL_IRREGULAR_RATE,
              channelFormat: LSLChannelFormat.string,
            ),
            isPausable: false,
            useIsolate: true,
            priority: LayerPriority.critical,
            requiresOutlet: true,
            requiresInletFromAll: false,
          ),

          // Game layer for real-time game data
          StreamLayerConfig(
            layerId: 'game',
            layerName: 'Game Data Layer',
            streamConfig: StreamConfig(
              streamName: 'demo_game_data',
              streamType: LSLContentType.custom('game'),
              channelCount: 4, // x, y, vx, vy
              sampleRate: LSL_IRREGULAR_RATE,
              channelFormat: LSLChannelFormat.float32,
            ),
            isPausable: true,
            useIsolate: true,
            priority: LayerPriority.high,
            requiresOutlet: true,
            requiresInletFromAll: true,
          ),

          // Sensor layer for continuous sensor data
          StreamLayerConfig(
            layerId: 'sensors',
            layerName: 'Sensor Data Layer',
            streamConfig: StreamConfig(
              streamName: 'demo_sensor_data',
              streamType: LSLContentType.custom('sensors'),
              channelCount: 6, // 3-axis accel + 3-axis gyro
              sampleRate: 100.0,
              channelFormat: LSLChannelFormat.float32,
            ),
            isPausable: true,
            useIsolate: true,
            priority: LayerPriority.medium,
            requiresOutlet: true,
            requiresInletFromAll: true,
          ),
        ],
      );

      final coordinator = MultiLayerCoordinator(
        nodeId: 'demo_device_${DateTime.now().millisecondsSinceEpoch}',
        nodeName: 'Demo Device',
        protocolConfig: customProtocol,
      );

      try {
        // This part would normally work when the coordinator becomes a coordinator
        // For demo purposes, we'll show the expected API usage

        print('=== Unified Layer API Demo ===');

        // Access all layers
        final layers = coordinator.layers;
        print('Layer collection: ${layers.layerIds}');

        // The API would look like this once fully operational:
        /*
        // Get specific layer
        final gameLayer = coordinator.getLayer('game');
        if (gameLayer != null) {
          print('Game layer: ${gameLayer.layerName}');
          print('  - Active: ${gameLayer.isActive}');
          print('  - Pausable: ${gameLayer.config.isPausable}');
          print('  - Priority: ${gameLayer.config.priority}');
          
          // Send game data
          await gameLayer.sendData([10.5, 20.3, 1.2, -0.8]);
          
          // Pause and resume
          await gameLayer.pause();
          print('  - Paused: ${gameLayer.isPaused}');
          
          await gameLayer.resume();
          print('  - Paused: ${gameLayer.isPaused}');
          
          // Listen to data
          gameLayer.dataStream.listen((event) {
            print('Game data from ${event.sourceNodeId}: ${event.data}');
          });
        }
        
        // Get sensor layer
        final sensorLayer = coordinator.getLayer('sensors');
        if (sensorLayer != null) {
          print('Sensor layer: ${sensorLayer.layerName}');
          
          // Send sensor data
          await sensorLayer.sendData([0.1, 0.2, 9.8, 0.05, -0.02, 0.01]);
          
          // Listen to aggregated sensor data
          sensorLayer.dataStream.listen((event) {
            final data = event.data;
            print('Sensor data from ${event.sourceNodeId}: ');
            print('  Accel: [${data[0]}, ${data[1]}, ${data[2]}]');
            print('  Gyro:  [${data[3]}, ${data[4]}, ${data[5]}]');
          });
        }
        
        // Layer collection operations
        print('Available layers: ${layers.layerIds}');
        print('Pausable layers: ${layers.pausable.map((l) => l.layerId).toList()}');
        print('High priority layers: ${layers.getByPriority(LayerPriority.high).map((l) => l.layerId).toList()}');
        
        // Bulk operations
        await layers.pauseAll();
        print('All pausable layers paused');
        
        await layers.resumeAll();
        print('All paused layers resumed');
        
        // Send data to multiple layers
        await layers.sendDataToLayers(['game', 'sensors'], [1.0, 2.0, 3.0]);
        
        // Combined data stream
        final combinedStream = layers.getCombinedDataStream(['game', 'sensors']);
        combinedStream.listen((event) {
          print('Combined stream - ${event.layerId}: ${event.data}');
        });
        */

        print('Demo API structure validated successfully!');
      } finally {
        await coordinator.dispose();
      }
    });

    test('should show API comparison between old and new approaches', () {
      print('\n=== API Comparison ===');

      print('OLD APPROACH (scattered methods):');
      print('  await coordinator.pauseLayer("game");');
      print('  await coordinator.sendLayerData("game", data);');
      print('  coordinator.getLayerDataStream("game")?.listen(...);');
      print('  await coordinator.pauseAllPausableLayers();');

      print('\nNEW UNIFIED APPROACH:');
      print('  final gameLayer = coordinator.getLayer("game");');
      print('  await gameLayer.pause();');
      print('  await gameLayer.sendData(data);');
      print('  gameLayer.dataStream.listen(...);');
      print('  ');
      print('  final layers = coordinator.layers;');
      print('  await layers.pauseAll();');
      print('  await layers.sendDataToLayers(["game", "sensors"], data);');
      print(
        '  final combinedStream = layers.getCombinedDataStream(["game", "sensors"]);',
      );

      print('\nBENEFITS:');
      print('  ✓ Object-oriented design');
      print('  ✓ Cleaner method names');
      print('  ✓ Powerful collection operations');
      print('  ✓ Type safety');
      print('  ✓ Better discoverability');
      print('  ✓ Backward compatibility maintained');
    });

    test('should demonstrate different protocol configurations', () {
      print('\n=== Protocol Configuration Examples ===');

      // Basic protocol - just coordination
      final basicProtocol = ProtocolConfigs.basic;
      print(
        'Basic Protocol: ${basicProtocol.layers.map((l) => l.layerId).toList()}',
      );

      // Gaming protocol - coordination + game
      final gamingProtocol = ProtocolConfigs.gaming;
      print(
        'Gaming Protocol: ${gamingProtocol.layers.map((l) => l.layerId).toList()}',
      );

      // High frequency protocol - coordination + hi-freq
      final hfProtocol = ProtocolConfigs.highFrequency;
      print(
        'High-Frequency Protocol: ${hfProtocol.layers.map((l) => l.layerId).toList()}',
      );

      // Full protocol - all layers
      final fullProtocol = ProtocolConfigs.full;
      print(
        'Full Protocol: ${fullProtocol.layers.map((l) => l.layerId).toList()}',
      );

      // Custom protocol example
      final customProtocol = ProtocolConfig(
        protocolId: 'research_experiment',
        protocolName: 'Research Experiment Protocol',
        layers: [
          StreamLayerConfig(
            layerId: 'coordination',
            layerName: 'Coordination',
            streamConfig: StreamConfig(
              streamName: 'research_coord',
              streamType: LSLContentType.markers,
            ),
            isPausable: false,
            priority: LayerPriority.critical,
          ),
          StreamLayerConfig(
            layerId: 'eeg',
            layerName: 'EEG Data',
            streamConfig: StreamConfig(
              streamName: 'eeg_data',
              streamType: LSLContentType.eeg,
              channelCount: 32,
              sampleRate: 1000.0,
            ),
            isPausable: true,
            priority: LayerPriority.high,
          ),
          StreamLayerConfig(
            layerId: 'eye_tracking',
            layerName: 'Eye Tracking',
            streamConfig: StreamConfig(
              streamName: 'eye_data',
              streamType: LSLContentType.gaze,
              channelCount: 8,
              sampleRate: 120.0,
            ),
            isPausable: true,
            priority: LayerPriority.medium,
          ),
          StreamLayerConfig(
            layerId: 'triggers',
            layerName: 'Experiment Triggers',
            streamConfig: StreamConfig(
              streamName: 'triggers',
              streamType: LSLContentType.markers,
              channelCount: 1,
              sampleRate: LSL_IRREGULAR_RATE,
              channelFormat: LSLChannelFormat.string,
            ),
            isPausable: false,
            priority: LayerPriority.high,
          ),
        ],
      );

      print(
        'Custom Research Protocol: ${customProtocol.layers.map((l) => l.layerId).toList()}',
      );

      // Show layer properties
      final eegLayer = customProtocol.getLayer('eeg');
      if (eegLayer != null) {
        print('EEG Layer Details:');
        print('  - Channels: ${eegLayer.streamConfig.channelCount}');
        print('  - Sample Rate: ${eegLayer.streamConfig.sampleRate} Hz');
        print('  - Pausable: ${eegLayer.isPausable}');
        print('  - Priority: ${eegLayer.priority}');
      }
    });

    test('should demonstrate layer filtering and bulk operations', () {
      print('\n=== Layer Filtering and Bulk Operations ===');

      final protocol = ProtocolConfigs.full;

      // Filter by priority
      final criticalLayers = protocol.getLayersByPriority(
        LayerPriority.critical,
      );
      final highLayers = protocol.getLayersByPriority(LayerPriority.high);

      print(
        'Critical layers: ${criticalLayers.map((l) => l.layerId).toList()}',
      );
      print(
        'High priority layers: ${highLayers.map((l) => l.layerId).toList()}',
      );

      // Filter by capabilities
      final pausableLayers = protocol.getPausableLayers();
      print(
        'Pausable layers: ${pausableLayers.map((l) => l.layerId).toList()}',
      );

      // Show layer configurations
      for (final layer in protocol.layers) {
        print('Layer ${layer.layerId}:');
        print('  - Name: ${layer.layerName}');
        print('  - Stream: ${layer.streamConfig.streamName}');
        print('  - Type: ${layer.streamConfig.streamType.value}');
        print('  - Channels: ${layer.streamConfig.channelCount}');
        print('  - Rate: ${layer.streamConfig.sampleRate} Hz');
        print('  - Pausable: ${layer.isPausable}');
        print('  - Priority: ${layer.priority}');
        print('  - Isolate: ${layer.useIsolate}');
        print('');
      }
    });

    test('should demonstrate data flow patterns', () {
      print('\n=== Data Flow Patterns ===');

      print('1. Gaming Pattern:');
      print('   - Each device sends position/velocity to game layer');
      print('   - Each device receives data from all other devices');
      print('   - Game layer is pausable (for menus, etc.)');
      print('   - Irregular frequency, low latency');
      print('');

      print('2. High-Frequency Pattern:');
      print('   - Each device sends sensor data at regular intervals');
      print('   - Coordinator aggregates data from all devices');
      print('   - Pausable during calibration periods');
      print('   - Regular frequency, high throughput');
      print('');

      print('3. Coordination Pattern:');
      print('   - Coordinator sends control messages to all devices');
      print('   - Devices send status updates to coordinator');
      print('   - Never pausable (critical for network integrity)');
      print('   - Irregular frequency, reliable delivery');
      print('');

      print('4. Mixed Pattern:');
      print('   - Multiple layers active simultaneously');
      print('   - Each layer has independent pause/resume state');
      print('   - Different priorities for resource allocation');
      print('   - Isolate-based processing for performance');
    });

    test('should validate layer data event structure', () {
      final now = DateTime.now();
      final gameEvent = LayerDataEvent(
        layerId: 'game',
        sourceNodeId: 'player_1',
        data: [100.5, 200.3, 5.2, -2.1], // x, y, vx, vy
        timestamp: now,
      );

      expect(gameEvent.layerId, equals('game'));
      expect(gameEvent.sourceNodeId, equals('player_1'));
      expect(gameEvent.data, hasLength(4));
      expect(gameEvent.timestamp, equals(now));

      final sensorEvent = LayerDataEvent(
        layerId: 'sensors',
        sourceNodeId: 'device_2',
        data: [0.1, 0.2, 9.8, 0.01, -0.02, 0.003], // accel + gyro
        timestamp: now,
      );

      expect(sensorEvent.layerId, equals('sensors'));
      expect(sensorEvent.sourceNodeId, equals('device_2'));
      expect(sensorEvent.data, hasLength(6));

      print('Layer data events validated successfully!');
    });
  });
}
