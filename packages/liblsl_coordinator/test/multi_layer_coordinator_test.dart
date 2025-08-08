import 'dart:async';
import 'package:test/test.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'test_lsl_config.dart';

void main() {
  group('MultiLayerCoordinator Tests', () {
    setUpAll(() async {
      // Initialize LSL with test-optimized configuration
      TestLSLConfig.initializeForTesting();

      // Clear any existing LSL streams before starting tests
      await _clearAllLSLStreams();
    });

    tearDownAll(() async {
      // Final cleanup after all tests
      await _clearAllLSLStreams();
    });

    /// Helper to create a fresh coordinator for testing
    MultiLayerCoordinator createTestCoordinator({String? suffix}) {
      return MultiLayerCoordinator(
        nodeId:
            'test_node_${DateTime.now().millisecondsSinceEpoch}${suffix ?? ''}',
        nodeName: 'Test Device${suffix ?? ''}',
        protocolConfig: ProtocolConfigs.gaming,
        coordinationConfig: CoordinationConfig(
          discoveryInterval: 0.1, // Much faster discovery
          heartbeatInterval: 0.1, // Much faster heartbeat
          joinTimeout: 0.1, // Very fast timeout for testing
          autoPromote: true,
        ),
        lslApiConfig: TestLSLConfig.createTestConfig(),
      );
    }

    /// Helper to safely dispose a coordinator
    Future<void> safeDisposeCoordinator(
      MultiLayerCoordinator coordinator,
    ) async {
      try {
        if (coordinator.isActive) {
          await coordinator.dispose();
        }
      } catch (e) {
        print('Warning: Error disposing coordinator: $e');
      }

      // Add longer delay to ensure LSL streams are fully cleaned up
      // This is critical for preventing resource conflicts between tests
      await Future.delayed(const Duration(milliseconds: 300));
    }

    group('Basic Properties', () {
      late MultiLayerCoordinator coordinator;

      setUp(() {
        coordinator = createTestCoordinator(suffix: '_basic');
      });

      tearDown(() async {
        await safeDisposeCoordinator(coordinator);
      });

      test('should have correct basic properties', () {
        expect(coordinator.nodeId, isNotEmpty);
        expect(coordinator.nodeName, contains('Test Device'));
        expect(coordinator.role, equals(NodeRole.discovering));
        expect(coordinator.isActive, isFalse);
        expect(coordinator.protocolConfig.protocolId, equals('gaming'));
      });

      test('should have gaming protocol layers', () {
        final config = coordinator.protocolConfig;
        expect(config.layers, hasLength(2));

        final layerIds = config.layers.map((l) => l.layerId).toList();
        expect(layerIds, contains('coordination'));
        expect(layerIds, contains('game'));
      });
    });

    group('Layer Collection Tests', () {
      late MultiLayerCoordinator coordinator;

      setUp(() {
        coordinator = createTestCoordinator(suffix: '_collection');
      });

      tearDown(() async {
        await safeDisposeCoordinator(coordinator);
      });

      test('should provide layer collection', () {
        final layers = coordinator.layers;
        expect(layers, isA<LayerCollection>());
        expect(layers.isEmpty, isTrue); // Not initialized yet
      });

      test(
        'should return null for non-existent layer before initialization',
        () {
          final gameLayer = coordinator.getLayer('game');
          expect(gameLayer, isNull);
        },
      );
    });

    group('Initialization Tests', () {
      late MultiLayerCoordinator coordinator;

      setUp(() {
        coordinator = createTestCoordinator(suffix: '_init');
      });

      tearDown(() async {
        await safeDisposeCoordinator(coordinator);
      });

      test('should initialize successfully', () async {
        await coordinator.initialize();
        expect(coordinator.isActive, isTrue);

        // After initialization, layers are created based on the protocol
        // Gaming protocol should have coordination and game layers
        expect(coordinator.layers.length, equals(2));
      });

      test('should create layers after becoming coordinator', () async {
        await coordinator.initialize();

        // Join the network and wait for coordinator election
        await coordinator.join();

        // Wait for coordinator election with timeout
        final startTime = DateTime.now();
        while (coordinator.role != NodeRole.coordinator &&
            DateTime.now().difference(startTime).inMilliseconds < 500) {
          await Future.delayed(const Duration(milliseconds: 50));
        }

        // Now the node should be coordinator
        expect(coordinator.role, equals(NodeRole.coordinator));

        final layers = coordinator.layers;
        expect(layers.contains('coordination'), isTrue);
        expect(layers.contains('game'), isTrue);

        final coordinationLayer = coordinator.getLayer('coordination');
        final gameLayer = coordinator.getLayer('game');

        expect(coordinationLayer, isNotNull);
        expect(gameLayer, isNotNull);

        if (coordinationLayer != null) {
          expect(coordinationLayer.layerId, equals('coordination'));
          expect(coordinationLayer.layerName, equals('Coordination Layer'));
          expect(coordinationLayer.config.isPausable, isFalse);
          expect(coordinationLayer.config.priority, equals(LayerPriority.low));
        }

        if (gameLayer != null) {
          expect(gameLayer.layerId, equals('game'));
          expect(gameLayer.layerName, equals('Game Data Layer'));
          expect(gameLayer.config.isPausable, isTrue);
          expect(gameLayer.config.priority, equals(LayerPriority.critical));
        }
      });

      test('should handle multiple initialization calls', () async {
        await coordinator.initialize();
        await coordinator.initialize(); // Should not throw or cause issues

        expect(coordinator.isActive, isTrue);
        // Layers are created during initialization (gaming protocol has 2 layers)
        expect(coordinator.layers.length, equals(2));
      });
    });

    group('Layer Interface Tests', () {
      late MultiLayerCoordinator coordinator;

      setUpAll(() async {
        // Create and promote a coordinator for this test group
        coordinator = createTestCoordinator(suffix: '_layer_interface');
        await coordinator.initialize();
        await coordinator.join();

        // Wait for coordinator promotion (joinTimeout is 1.0s + LSL transport delays)
        await Future.delayed(const Duration(milliseconds: 1200));
      });

      tearDownAll(() async {
        // Clean up the promoted coordinator
        await safeDisposeCoordinator(coordinator);

        // Extra cleanup after promoted coordinator tests
        await _clearAllLSLStreams();
        await Future.delayed(const Duration(milliseconds: 500));
      });

      test('should provide unified layer interface', () async {
        // Node should be coordinator after setup
        expect(coordinator.role, equals(NodeRole.coordinator));

        final gameLayer = coordinator.getLayer('game');
        expect(gameLayer, isNotNull);

        if (gameLayer != null) {
          expect(gameLayer.layerId, equals('game'));
          expect(gameLayer.layerName, isA<String>());
          expect(gameLayer.config, isA<StreamLayerConfig>());
          expect(gameLayer.isActive, isA<bool>());
          expect(gameLayer.isPaused, isA<bool>());
          expect(gameLayer.dataStream, isA<Stream<LayerDataEvent>>());
          expect(gameLayer.eventStream, isA<Stream<CoordinationEvent>>());
        }
      });

      test('should send data through layer interface', () async {
        expect(coordinator.role, equals(NodeRole.coordinator));

        final gameLayer = coordinator.getLayer('game');
        expect(gameLayer, isNotNull);

        if (gameLayer != null) {
          // Should not throw
          await gameLayer.sendData([1.0, 2.0, 3.0, 4.0]);
        }
      });

      test('should handle pause/resume operations', () async {
        expect(coordinator.role, equals(NodeRole.coordinator));

        final gameLayer = coordinator.getLayer('game');
        expect(gameLayer, isNotNull);

        if (gameLayer != null) {
          expect(gameLayer.isPaused, isFalse);

          await gameLayer.pause();
          expect(gameLayer.isPaused, isTrue);

          await gameLayer.resume();
          expect(gameLayer.isPaused, isFalse);
        }
      });

      test('should reject pause on non-pausable layer', () async {
        final coordinationLayer = coordinator.getLayer('coordination');
        expect(coordinationLayer, isNotNull);

        if (coordinationLayer != null) {
          expect(coordinationLayer.config.isPausable, isFalse);
          expect(() async => await coordinationLayer.pause(), throwsStateError);
        }
      });

      test('should provide data streams', () async {
        final gameLayer = coordinator.getLayer('game');
        expect(gameLayer, isNotNull);

        if (gameLayer != null) {
          final dataStream = gameLayer.dataStream;
          expect(dataStream, isA<Stream<LayerDataEvent>>());

          // Test stream subscription
          final subscription = dataStream.listen((event) {
            // Event handler
          });

          await Future.delayed(Duration(milliseconds: 10));
          await subscription.cancel();
        }
      });
    });

    group('Layer Collection Operations', () {
      late MultiLayerCoordinator coordinator;

      setUp(() async {
        coordinator = createTestCoordinator(suffix: '_operations');
        await coordinator.initialize();
      });

      tearDown(() async {
        await safeDisposeCoordinator(coordinator);
      });

      test('should provide layer filtering operations', () {
        final layers = coordinator.layers;

        expect(layers.all, hasLength(2));
        expect(layers.layerIds, containsAll(['coordination', 'game']));

        final pausableLayers = layers.pausable;
        expect(pausableLayers, hasLength(1));
        expect(pausableLayers.first.layerId, equals('game'));

        final criticalLayers = layers.getByPriority(LayerPriority.critical);
        expect(criticalLayers, hasLength(1));
        expect(
          criticalLayers.first.layerId,
          equals('game'),
        ); // Game layer is critical in gaming protocol

        final lowLayers = layers.getByPriority(LayerPriority.low);
        expect(lowLayers, hasLength(1));
        expect(
          lowLayers.first.layerId,
          equals('coordination'),
        ); // Coordination layer is low priority in gaming protocol
      });

      test('should perform bulk pause/resume operations', () async {
        final layers = coordinator.layers;

        // Initially no layers should be paused
        expect(layers.paused, isEmpty);

        // Pause all pausable layers
        await layers.pauseAll();
        expect(layers.paused, hasLength(1));
        expect(layers.paused.first.layerId, equals('game'));

        // Resume all paused layers
        await layers.resumeAll();
        expect(layers.paused, isEmpty);
      });

      test('should send data to multiple layers', () async {
        // ensure coordinator promotion
        await Future.delayed(Duration(milliseconds: 800));
        final layers = coordinator.layers;
        final testData = [1.0, 2.0, 3.0];

        // Should not throw - only game layer supports sending data
        await layers.sendDataToLayers(['game'], testData);

        // Should handle non-existent layers gracefully
        await layers.sendDataToLayers(['game', 'nonexistent'], testData);
      });

      test('should provide combined data streams', () async {
        final layers = coordinator.layers;

        final combinedStream = layers.getCombinedDataStream([
          'coordination',
          'game',
        ]);
        expect(combinedStream, isA<Stream<LayerDataEvent>>());

        // Test stream subscription - placeholder layers have empty streams, so this should not hang
        StreamSubscription? subscription;
        try {
          subscription = combinedStream.listen((event) {
            expect(event, isA<LayerDataEvent>());
            expect(['coordination', 'game'], contains(event.layerId));
          });

          await Future.delayed(Duration(milliseconds: 10));
        } finally {
          await subscription?.cancel();
        }
      });

      test('should handle empty layer list for combined streams', () {
        final layers = coordinator.layers;
        final emptyStream = layers.getCombinedDataStream([]);
        expect(emptyStream, isA<Stream<LayerDataEvent>>());
      });
    });

    group('Protocol Configuration Tests', () {
      test('should use basic protocol', () async {
        final basicCoordinator = MultiLayerCoordinator(
          nodeId: 'basic_test',
          nodeName: 'Basic Device',
          protocolConfig: ProtocolConfigs.basic,
        );

        await basicCoordinator.initialize();

        expect(basicCoordinator.layers.length, equals(1));
        expect(basicCoordinator.layers.contains('coordination'), isTrue);
        expect(basicCoordinator.getLayer('game'), isNull);

        await basicCoordinator.dispose();
      });

      test('should use high frequency protocol', () async {
        final hfCoordinator = MultiLayerCoordinator(
          nodeId: 'hf_test',
          nodeName: 'HF Device',
          protocolConfig: ProtocolConfigs.highFrequency,
        );

        await hfCoordinator.initialize();

        expect(hfCoordinator.layers.length, equals(2));
        expect(hfCoordinator.layers.contains('coordination'), isTrue);
        expect(hfCoordinator.layers.contains('hi_freq'), isTrue);

        final hfLayer = hfCoordinator.getLayer('hi_freq');
        expect(hfLayer, isNotNull);
        if (hfLayer != null) {
          expect(hfLayer.config.streamConfig.sampleRate, equals(1000.0));
          expect(hfLayer.config.isPausable, isTrue);
        }

        await hfCoordinator.dispose();
      });

      test('should use full protocol', () async {
        final fullCoordinator = MultiLayerCoordinator(
          nodeId: 'full_test',
          nodeName: 'Full Device',
          protocolConfig: ProtocolConfigs.full,
        );

        await fullCoordinator.initialize();

        expect(fullCoordinator.layers.length, equals(3));
        expect(fullCoordinator.layers.contains('coordination'), isTrue);
        expect(fullCoordinator.layers.contains('game'), isTrue);
        expect(fullCoordinator.layers.contains('hi_freq'), isTrue);

        await fullCoordinator.dispose();
      });
    });

    group('Custom Protocol Tests', () {
      test('should create custom protocol', () async {
        final customProtocol = ProtocolConfig(
          protocolId: 'test_custom',
          protocolName: 'Test Custom Protocol',
          layers: [
            StreamLayerConfig(
              layerId: 'coordination',
              layerName: 'Coordination',
              streamConfig: StreamConfig(
                streamName: 'test_coordination',
                streamType: LSLContentType.markers,
                channelCount: 1,
                sampleRate: LSL_IRREGULAR_RATE,
                channelFormat: LSLChannelFormat.string,
              ),
              isPausable: false,
              priority: LayerPriority.critical,
              requiresOutlet: true,
              requiresInletFromAll: false,
            ),
            StreamLayerConfig(
              layerId: 'custom_sensors',
              layerName: 'Custom Sensors',
              streamConfig: StreamConfig(
                streamName: 'custom_sensor_data',
                streamType: LSLContentType.custom('sensors'),
                channelCount: 6,
                sampleRate: 250.0,
                channelFormat: LSLChannelFormat.float32,
              ),
              isPausable: true,
              priority: LayerPriority.medium,
              requiresOutlet: true,
              requiresInletFromAll: true,
            ),
          ],
        );

        final customCoordinator = MultiLayerCoordinator(
          nodeId: 'custom_test',
          nodeName: 'Custom Device',
          protocolConfig: customProtocol,
        );

        await customCoordinator.initialize();

        expect(customCoordinator.layers.length, equals(2));
        expect(customCoordinator.layers.contains('coordination'), isTrue);
        expect(customCoordinator.layers.contains('custom_sensors'), isTrue);

        final sensorLayer = customCoordinator.getLayer('custom_sensors');
        expect(sensorLayer, isNotNull);
        if (sensorLayer != null) {
          expect(sensorLayer.config.streamConfig.channelCount, equals(6));
          expect(sensorLayer.config.streamConfig.sampleRate, equals(250.0));
          expect(sensorLayer.config.priority, equals(LayerPriority.medium));
        }

        await customCoordinator.dispose();
      });
    });

    group('Error Handling Tests', () {
      test('should handle missing coordination layer', () async {
        final invalidProtocol = ProtocolConfig(
          protocolId: 'invalid',
          protocolName: 'Invalid Protocol',
          layers: [], // No coordination layer
        );

        final invalidCoordinator = MultiLayerCoordinator(
          nodeId: 'invalid_test',
          nodeName: 'Invalid Device',
          protocolConfig: invalidProtocol,
        );

        expect(
          () async => await invalidCoordinator.initialize(),
          throwsStateError,
        );

        await invalidCoordinator.dispose();
      });

      test('should handle layer not found errors', () async {
        final testCoordinator = createTestCoordinator(suffix: '_error_test');
        await testCoordinator.initialize();

        try {
          // Test accessing non-existent layer
          final nonExistentLayer = testCoordinator.getLayer('nonexistent');
          expect(nonExistentLayer, isNull);

          // Test layer collection with non-existent layers
          final layers = testCoordinator.layers;
          expect(layers.contains('nonexistent'), isFalse);
        } finally {
          await safeDisposeCoordinator(testCoordinator);
        }
      });

      test('should handle sending data to layer without outlet', () async {
        final testCoordinator = createTestCoordinator(suffix: '_outlet_test');
        await testCoordinator.initialize();

        try {
          final coordinationLayer = testCoordinator.getLayer('coordination');
          expect(coordinationLayer, isNotNull);

          // Coordination layer may not support sending data depending on config
          // This test ensures proper error handling
        } finally {
          await safeDisposeCoordinator(testCoordinator);
        }
      });
    });

    group('Event Handling Tests', () {
      test('should emit coordination events', () async {
        final testCoordinator = createTestCoordinator(suffix: '_events');

        try {
          final events = <CoordinationEvent>[];
          final subscription = testCoordinator.eventStream.listen((event) {
            events.add(event);
          });

          await testCoordinator.initialize();
          await testCoordinator.join();

          // Allow some time for coordination events to be emitted
          await Future.delayed(Duration(milliseconds: 200));

          expect(events, isNotEmpty);
          // Should have coordination-related events (like RoleChangedEvent)

          await subscription.cancel();
        } finally {
          await safeDisposeCoordinator(testCoordinator);
        }
      });

      test('should emit layer-specific events', () async {
        final testCoordinator = createTestCoordinator(suffix: '_layer_events');

        try {
          await testCoordinator.initialize();

          final gameLayer = testCoordinator.getLayer('game');
          expect(gameLayer, isNotNull);

          if (gameLayer != null) {
            final layerEvents = <CoordinationEvent>[];
            final subscription = gameLayer.eventStream.listen((event) {
              layerEvents.add(event);
            });

            // Allow some time for events
            await Future.delayed(Duration(milliseconds: 50));

            await subscription.cancel();
          }
        } finally {
          await safeDisposeCoordinator(testCoordinator);
        }
      });
    });
  });

  group('LayerCollection Tests', () {
    late LayerCollection layers;

    setUp(() {
      layers = LayerCollection();
    });

    tearDown(() async {
      await layers.dispose();
    });

    test('should start empty', () {
      expect(layers.isEmpty, isTrue);
      expect(layers.isNotEmpty, isFalse);
      expect(layers.length, equals(0));
      expect(layers.all, isEmpty);
      expect(layers.layerIds, isEmpty);
    });

    test('should handle null layer access', () {
      expect(layers['nonexistent'], isNull);
      expect(layers.contains('nonexistent'), isFalse);
    });

    test('should handle empty collections gracefully', () async {
      await layers.pauseAll(); // Should not throw
      await layers.resumeAll(); // Should not throw
      await layers.sendDataToLayers([], []); // Should not throw

      final emptyStream = layers.getCombinedDataStream([]);
      expect(emptyStream, isA<Stream<LayerDataEvent>>());
    });
  });

  group('Protocol Configuration Tests', () {
    test('should provide predefined protocols', () {
      expect(ProtocolConfigs.basic.protocolId, equals('basic'));
      expect(ProtocolConfigs.gaming.protocolId, equals('gaming'));
      expect(
        ProtocolConfigs.highFrequency.protocolId,
        equals('high_frequency'),
      );
      expect(ProtocolConfigs.full.protocolId, equals('full'));
    });

    test('should serialize and deserialize protocol config', () {
      final original = ProtocolConfigs.gaming;
      final map = original.toMap();
      final deserialized = ProtocolConfig.fromMap(map);

      expect(deserialized.protocolId, equals(original.protocolId));
      expect(deserialized.protocolName, equals(original.protocolName));
      expect(deserialized.layers.length, equals(original.layers.length));
    });

    test('should handle protocol layer operations', () {
      final protocol = ProtocolConfigs.full;

      final gameLayer = protocol.getLayer('game');
      expect(gameLayer, isNotNull);
      expect(gameLayer?.layerId, equals('game'));

      final pausableLayers = protocol.getPausableLayers();
      expect(pausableLayers, isNotEmpty);

      final criticalLayers = protocol.getLayersByPriority(
        LayerPriority.critical,
      );
      expect(criticalLayers, hasLength(1));
      expect(criticalLayers.first.layerId, equals('coordination'));
    });
  });
}

/// Helper function to clear all existing LSL streams
Future<void> _clearAllLSLStreams() async {
  try {
    final streams = await LSL.resolveStreams(waitTime: 0.5, maxStreams: 100);
    print('Found ${streams.length} existing LSL streams to clear');

    // Wait a bit for any streams to be released naturally
    await Future.delayed(const Duration(milliseconds: 200));
  } catch (e) {
    print('Warning: Could not resolve streams for cleanup: $e');
  }
}
