import 'dart:async';
import 'package:test/test.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

import 'test_lsl_config.dart';

void main() {
  group('Simple Layer API Tests', () {
    setUp(() async {
      TestLSLConfig.initializeForTesting();
    });
    tearDown(() async {
      await Future.delayed(Duration(milliseconds: 100));
    });
    test('should create protocol configurations correctly', () {
      // Test basic protocol
      final basicProtocol = ProtocolConfigs.basic;
      expect(basicProtocol.protocolId, equals('basic'));
      expect(basicProtocol.layers, hasLength(1));
      expect(basicProtocol.layers.first.layerId, equals('coordination'));

      // Test gaming protocol
      final gamingProtocol = ProtocolConfigs.gaming;
      expect(gamingProtocol.protocolId, equals('gaming'));
      expect(gamingProtocol.layers, hasLength(2));

      final layerIds = gamingProtocol.layers.map((l) => l.layerId).toList();
      expect(layerIds, contains('coordination'));
      expect(layerIds, contains('game'));
    });

    test('should create layer configurations correctly', () {
      final gameLayerConfig = StreamLayerConfig(
        layerId: 'test_game',
        layerName: 'Test Game Layer',
        streamConfig: StreamConfig(
          streamName: 'test_game_data',
          streamType: LSLContentType.custom('game'),
          channelCount: 4,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.float32,
        ),
        isPausable: true,
        useIsolate: true,
        priority: LayerPriority.high,
      );

      expect(gameLayerConfig.layerId, equals('test_game'));
      expect(gameLayerConfig.layerName, equals('Test Game Layer'));
      expect(gameLayerConfig.isPausable, isTrue);
      expect(gameLayerConfig.useIsolate, isTrue);
      expect(gameLayerConfig.priority, equals(LayerPriority.high));

      expect(gameLayerConfig.streamConfig.streamName, equals('test_game_data'));
      expect(gameLayerConfig.streamConfig.channelCount, equals(4));
      expect(
        gameLayerConfig.streamConfig.sampleRate,
        equals(LSL_IRREGULAR_RATE),
      );
    });

    test('should serialize and deserialize stream config correctly', () {
      final originalConfig = StreamConfig(
        streamName: 'test_stream',
        streamType: LSLContentType.eeg,
        channelCount: 8,
        sampleRate: 250.0,
        channelFormat: LSLChannelFormat.float32,
        maxBuffer: 500,
        chunkSize: 16,
      );

      final map = originalConfig.toMap();
      final deserializedConfig = StreamConfig.fromMap(map);

      expect(deserializedConfig.streamName, equals('test_stream'));
      expect(deserializedConfig.streamType.value, equals('EEG'));
      expect(deserializedConfig.channelCount, equals(8));
      expect(deserializedConfig.sampleRate, equals(250.0));
      expect(
        deserializedConfig.channelFormat,
        equals(LSLChannelFormat.float32),
      );
      expect(deserializedConfig.maxBuffer, equals(500));
      expect(deserializedConfig.chunkSize, equals(16));
    });

    test('should handle layer priorities correctly', () {
      final criticalLayer = StreamLayerConfig(
        layerId: 'critical_test',
        layerName: 'Critical Test',
        streamConfig: StreamConfig(
          streamName: 'critical',
          streamType: LSLContentType.markers,
        ),
        priority: LayerPriority.critical,
      );

      final highLayer = StreamLayerConfig(
        layerId: 'high_test',
        layerName: 'High Test',
        streamConfig: StreamConfig(
          streamName: 'high',
          streamType: LSLContentType.eeg,
        ),
        priority: LayerPriority.high,
      );

      final mediumLayer = StreamLayerConfig(
        layerId: 'medium_test',
        layerName: 'Medium Test',
        streamConfig: StreamConfig(
          streamName: 'medium',
          streamType: LSLContentType.audio,
        ),
        priority: LayerPriority.medium,
      );

      final protocol = ProtocolConfig(
        protocolId: 'priority_test',
        protocolName: 'Priority Test',
        layers: [criticalLayer, highLayer, mediumLayer],
      );

      final criticalLayers = protocol.getLayersByPriority(
        LayerPriority.critical,
      );
      final highLayers = protocol.getLayersByPriority(LayerPriority.high);
      final mediumLayers = protocol.getLayersByPriority(LayerPriority.medium);

      expect(criticalLayers, hasLength(1));
      expect(criticalLayers.first.layerId, equals('critical_test'));

      expect(highLayers, hasLength(1));
      expect(highLayers.first.layerId, equals('high_test'));

      expect(mediumLayers, hasLength(1));
      expect(mediumLayers.first.layerId, equals('medium_test'));
    });

    test('should create coordinator with correct properties', () {
      final coordinator = MultiLayerCoordinator(
        nodeId: 'test_node',
        nodeName: 'Test Device',
        protocolConfig: ProtocolConfigs.gaming,
        coordinationConfig: CoordinationConfig(
          discoveryInterval: 1.0,
          heartbeatInterval: 0.5,
          autoPromote: true,
        ),
      );

      expect(coordinator.nodeId, equals('test_node'));
      expect(coordinator.nodeName, equals('Test Device'));
      expect(coordinator.role, equals(NodeRole.discovering));
      expect(coordinator.isActive, isFalse);
      expect(coordinator.protocolConfig.protocolId, equals('gaming'));
    });

    test('should provide empty layer collection before initialization', () {
      final coordinator = MultiLayerCoordinator(
        nodeId: 'test_node',
        nodeName: 'Test Device',
        protocolConfig: ProtocolConfigs.basic,
      );

      final layers = coordinator.layers;
      expect(layers, isA<LayerCollection>());
      expect(layers.isEmpty, isTrue);
      expect(layers.length, equals(0));
      expect(layers.all, isEmpty);
      expect(layers.layerIds, isEmpty);
    });

    test(
      'should handle layer collection operations on empty collection',
      () async {
        final layers = LayerCollection();

        expect(layers.isEmpty, isTrue);
        expect(layers.isNotEmpty, isFalse);
        expect(layers.length, equals(0));
        expect(layers['nonexistent'], isNull);
        expect(layers.contains('nonexistent'), isFalse);

        // Bulk operations should not throw on empty collection
        await layers.pauseAll();
        await layers.resumeAll();
        await layers.sendDataToLayers([], []);

        final emptyStream = layers.getCombinedDataStream([]);
        expect(emptyStream, isA<Stream<LayerDataEvent>>());

        await layers.dispose();
      },
    );

    test('should create custom protocol configurations', () {
      final customProtocol = ProtocolConfig(
        protocolId: 'custom_sensors',
        protocolName: 'Custom Sensor Protocol',
        layers: [
          StreamLayerConfig(
            layerId: 'coordination',
            layerName: 'Coordination',
            streamConfig: StreamConfig(
              streamName: 'coord',
              streamType: LSLContentType.markers,
              channelCount: 1,
              sampleRate: LSL_IRREGULAR_RATE,
              channelFormat: LSLChannelFormat.string,
            ),
            isPausable: false,
            priority: LayerPriority.critical,
          ),
          StreamLayerConfig(
            layerId: 'accelerometer',
            layerName: 'Accelerometer Data',
            streamConfig: StreamConfig(
              streamName: 'accel_data',
              streamType: LSLContentType.custom('accelerometer'),
              channelCount: 3,
              sampleRate: 100.0,
              channelFormat: LSLChannelFormat.float32,
            ),
            isPausable: true,
            priority: LayerPriority.medium,
          ),
          StreamLayerConfig(
            layerId: 'gyroscope',
            layerName: 'Gyroscope Data',
            streamConfig: StreamConfig(
              streamName: 'gyro_data',
              streamType: LSLContentType.custom('gyroscope'),
              channelCount: 3,
              sampleRate: 100.0,
              channelFormat: LSLChannelFormat.float32,
            ),
            isPausable: true,
            priority: LayerPriority.medium,
          ),
        ],
      );

      expect(customProtocol.protocolId, equals('custom_sensors'));
      expect(customProtocol.layers, hasLength(3));

      final coordLayer = customProtocol.getLayer('coordination');
      expect(coordLayer, isNotNull);
      expect(coordLayer!.isPausable, isFalse);
      expect(coordLayer.priority, equals(LayerPriority.critical));

      final accelLayer = customProtocol.getLayer('accelerometer');
      expect(accelLayer, isNotNull);
      expect(accelLayer!.streamConfig.channelCount, equals(3));
      expect(accelLayer.streamConfig.sampleRate, equals(100.0));

      final pausableLayers = customProtocol.getPausableLayers();
      expect(pausableLayers, hasLength(2));
      expect(
        pausableLayers.map((l) => l.layerId),
        containsAll(['accelerometer', 'gyroscope']),
      );
    });

    test('should validate layer configuration constraints', () {
      // Test that certain combinations make sense
      final gameLayer = ProtocolConfigs.gaming.getLayer('game');
      expect(gameLayer, isNotNull);
      if (gameLayer != null) {
        // Game layers should typically be pausable for menu systems
        expect(gameLayer.isPausable, isTrue);

        // Game layers should support bi-directional communication
        expect(gameLayer.requiresOutlet, isTrue);
        expect(gameLayer.requiresInletFromAll, isTrue);

        // Game layers should use isolates for performance
        expect(gameLayer.useIsolate, isTrue);
      }

      final coordLayer = ProtocolConfigs.gaming.getLayer('coordination');
      expect(coordLayer, isNotNull);
      if (coordLayer != null) {
        // Coordination should never be pausable
        expect(coordLayer.isPausable, isFalse);

        // Coordination should be low priority in gaming protocol (game data is critical)
        expect(coordLayer.priority, equals(LayerPriority.low));

        // Coordination has asymmetric communication pattern
        expect(coordLayer.requiresOutlet, isTrue);
        expect(coordLayer.requiresInletFromAll, isFalse);
      }
    });

    test('should handle LayerDataEvent creation', () {
      final now = DateTime.now();
      final event = LayerDataEvent(
        layerId: 'test_layer',
        sourceNodeId: 'test_node',
        data: [1.0, 2.0, 3.0],
        timestamp: now,
      );

      expect(event.layerId, equals('test_layer'));
      expect(event.sourceNodeId, equals('test_node'));
      expect(event.data, equals([1.0, 2.0, 3.0]));
      expect(event.timestamp, equals(now));
    });

    test('should validate stream configuration parameters', () {
      // Test valid configurations
      expect(
        () => StreamConfig(
          streamName: 'valid_stream',
          streamType: LSLContentType.eeg,
          channelCount: 8,
          sampleRate: 250.0,
          channelFormat: LSLChannelFormat.float32,
        ),
        returnsNormally,
      );

      // Test with irregular rate
      expect(
        () => StreamConfig(
          streamName: 'irregular_stream',
          streamType: LSLContentType.markers,
          channelCount: 1,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.string,
        ),
        returnsNormally,
      );

      // Test with custom content type
      expect(
        () => StreamConfig(
          streamName: 'custom_stream',
          streamType: LSLContentType.custom('sensors'),
          channelCount: 6,
          sampleRate: 500.0,
          channelFormat: LSLChannelFormat.float32,
        ),
        returnsNormally,
      );
    });
  });
}
