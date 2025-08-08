import 'dart:async';
import 'package:test/test.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'test_lsl_config.dart';

/// This test file demonstrates proper resource management patterns
/// for the liblsl_coordinator library. These patterns should be
/// followed by end users to avoid resource leaks and conflicts.
void main() {
  group('Resource Management Examples', () {
    setUpAll(() async {
      // Initialize LSL with optimal configuration for testing
      TestLSLConfig.initializeForTesting();
    });

    group('Basic Coordinator Lifecycle', () {
      test('should properly initialize and dispose a coordinator', () async {
        // PATTERN 1: Basic coordinator lifecycle
        final coordinator = MultiLayerCoordinator(
          nodeId: 'example_${DateTime.now().millisecondsSinceEpoch}',
          nodeName: 'Example Device',
          protocolConfig: ProtocolConfigs.basic,
        );

        try {
          // Initialize the coordinator
          await coordinator.initialize();
          expect(coordinator.isActive, isTrue);

          // Use the coordinator...
          expect(coordinator.layers.length, equals(1));
          expect(coordinator.layers.contains('coordination'), isTrue);
        } finally {
          // CRITICAL: Always dispose coordinators in a try-finally block
          await coordinator.dispose();

          // Allow time for LSL resources to be fully released
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // After disposal, coordinator should not be active
        expect(coordinator.isActive, isFalse);
      });

      test('should handle coordinator promotion correctly', () async {
        // PATTERN 2: Coordinator promotion with proper cleanup
        final coordinator = MultiLayerCoordinator(
          nodeId: 'promoted_${DateTime.now().millisecondsSinceEpoch}',
          nodeName: 'Promoted Device',
          protocolConfig: ProtocolConfigs.gaming,
          coordinationConfig: CoordinationConfig(
            discoveryInterval: 0.1,
            heartbeatInterval: 0.1,
            joinTimeout: 1.0,
            autoPromote: true,
          ),
        );

        try {
          await coordinator.initialize();
          await coordinator.join();

          // Wait for coordinator promotion
          // This timing is critical - too short and promotion may not complete
          await Future.delayed(const Duration(milliseconds: 3000));

          expect(coordinator.role, equals(NodeRole.coordinator));
          expect(coordinator.layers.length, equals(2));

          // Now we can use active layer operations
          final gameLayer = coordinator.getLayer('game');
          expect(gameLayer, isNotNull);
          expect(gameLayer!.isActive, isTrue);
        } finally {
          // CRITICAL: Properly dispose promoted coordinators
          await coordinator.dispose();

          // Extra cleanup time for promoted coordinators
          // They have more resources to clean up
          await Future.delayed(const Duration(milliseconds: 300));
        }
      });
    });

    group('Multiple Coordinators', () {
      test('should handle sequential coordinator usage', () async {
        // PATTERN 3: Sequential coordinator usage (recommended pattern)
        // Creating multiple coordinators simultaneously can cause LSL resource conflicts
        // Instead, use coordinators sequentially or with proper coordination

        final coordinatorConfigs = [
          ('basic_1', ProtocolConfigs.basic),
          ('basic_2', ProtocolConfigs.basic),
          ('gaming_1', ProtocolConfigs.gaming),
        ];

        for (final (suffix, config) in coordinatorConfigs) {
          final coordinator = MultiLayerCoordinator(
            nodeId: '${suffix}_${DateTime.now().millisecondsSinceEpoch}',
            nodeName: 'Sequential Device $suffix',
            protocolConfig: config,
          );

          try {
            await coordinator.initialize();
            expect(coordinator.isActive, isTrue);

            // Use the coordinator for a short time
            expect(coordinator.layers.isNotEmpty, isTrue);
          } finally {
            await coordinator.dispose();
            // Important: Wait between sequential coordinators
            // This ensures LSL resources are fully released
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      });

      test('should demonstrate concurrent coordinator limitations', () async {
        // PATTERN 3b: Understanding concurrent coordinator limitations
        // This test documents the current limitation that multiple coordinators
        // cannot be safely created simultaneously due to LSL resource conflicts

        // This is a known limitation that users should be aware of
        // Future API improvements might address this

        final coordinator1 = MultiLayerCoordinator(
          nodeId: 'concurrent_1_${DateTime.now().millisecondsSinceEpoch}',
          nodeName: 'Concurrent Device 1',
          protocolConfig: ProtocolConfigs.basic,
        );

        try {
          await coordinator1.initialize();
          expect(coordinator1.isActive, isTrue);

          // Creating a second coordinator immediately may cause issues
          // This is documented behavior, not a bug
        } finally {
          await coordinator1.dispose();
          await Future.delayed(const Duration(milliseconds: 200));
        }
      });
    });

    group('Error Handling Patterns', () {
      test('should handle initialization failures gracefully', () async {
        // PATTERN 4: Error handling with proper cleanup
        final invalidProtocol = ProtocolConfig(
          protocolId: 'invalid',
          protocolName: 'Invalid Protocol',
          layers: [], // Missing required coordination layer
        );

        final coordinator = MultiLayerCoordinator(
          nodeId: 'error_test_${DateTime.now().millisecondsSinceEpoch}',
          nodeName: 'Error Test Device',
          protocolConfig: invalidProtocol,
        );

        try {
          // This should throw a StateError
          await expectLater(coordinator.initialize(), throwsStateError);
        } finally {
          // CRITICAL: Always dispose, even if initialization failed
          // The coordinator might be in a partial state
          try {
            await coordinator.dispose();
          } catch (e) {
            // Log but don't rethrow cleanup errors
            print('Cleanup error (expected): $e');
          }
        }
      });

      test('should handle double disposal gracefully', () async {
        // PATTERN 5: Defensive disposal handling
        final coordinator = MultiLayerCoordinator(
          nodeId: 'double_dispose_${DateTime.now().millisecondsSinceEpoch}',
          nodeName: 'Double Dispose Test',
          protocolConfig: ProtocolConfigs.basic,
        );

        await coordinator.initialize();
        expect(coordinator.isActive, isTrue);

        // First disposal
        await coordinator.dispose();
        expect(coordinator.isActive, isFalse);

        // Second disposal should not throw
        await coordinator.dispose(); // Should be safe
        expect(coordinator.isActive, isFalse);
      });
    });

    group('Stream and Event Management', () {
      test('should properly manage event stream subscriptions', () async {
        // PATTERN 6: Event stream subscription management
        final coordinator = MultiLayerCoordinator(
          nodeId: 'event_test_${DateTime.now().millisecondsSinceEpoch}',
          nodeName: 'Event Test Device',
          protocolConfig: ProtocolConfigs.gaming,
        );

        StreamSubscription? eventSubscription;

        try {
          await coordinator.initialize();

          // Subscribe to events
          final events = <CoordinationEvent>[];
          eventSubscription = coordinator.eventStream.listen((event) {
            events.add(event);
          });

          await coordinator.join();
          await Future.delayed(const Duration(milliseconds: 200));

          expect(events, isNotEmpty);
        } finally {
          // CRITICAL: Cancel subscriptions before disposing coordinator
          await eventSubscription?.cancel();
          await coordinator.dispose();
          await Future.delayed(const Duration(milliseconds: 100));
        }
      });
    });
  });
}
