import 'dart:async';
import 'package:test/test.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/src/coordination/lsl/high_frequency_transport.dart';
import 'package:liblsl_coordinator/src/coordination/core/coordination_message.dart';

/// Integration tests that simulate multiple devices on the same machine
/// These tests verify the isolate separation and multi-device coordination
void main() {
  group('Multi-Device Integration Tests', () {
    late List<HighFrequencyLSLTransport> transports;
    late StreamController<String> testLogController;

    setUp(() {
      transports = [];
      testLogController = StreamController<String>.broadcast();
    });

    tearDown(() async {
      // Clean up all transports
      for (final transport in transports) {
        try {
          await transport.dispose();
        } catch (e) {
          print('Error disposing transport: $e');
        }
      }
      transports.clear();
      await testLogController.close();
    });

    /// Helper function to create a transport with unique identifiers
    HighFrequencyLSLTransport createTransport(
      String nodeId, {
      bool useIsolate = false,
      double targetFrequency = 100.0,
      bool useBusyWait = false,
    }) {
      final transport = HighFrequencyLSLTransport(
        streamName: 'integration_test_stream',
        nodeId: nodeId,
        sampleRate: targetFrequency,
        performanceConfig: HighFrequencyConfig(
          targetFrequency: targetFrequency,
          useBusyWait: useBusyWait,
          bufferSize: 50,
          useIsolate: useIsolate,
          channelFormat: LSLChannelFormat.int32,
          channelCount: 1,
        ),
        lslApiConfig: LSLApiConfig(
          ipv6: IPv6Mode.disable,
          resolveScope: ResolveScope.link,
          listenAddress: '127.0.0.1', // Use loopback for testing
          addressesOverride: ['224.0.0.183'],
          knownPeers: ['127.0.0.1'],
        ),
      );
      transports.add(transport);
      return transport;
    }

    group('Basic Multi-Device Tests', () {
      test('should create multiple transports without interference', () async {
        final transport1 = createTransport('device_1');
        final transport2 = createTransport('device_2');
        final transport3 = createTransport('device_3');

        expect(transport1.nodeId, equals('device_1'));
        expect(transport2.nodeId, equals('device_2'));
        expect(transport3.nodeId, equals('device_3'));

        // All should use the same stream name
        expect(transport1.streamName, equals('integration_test_stream'));
        expect(transport2.streamName, equals('integration_test_stream'));
        expect(transport3.streamName, equals('integration_test_stream'));
      });

      test('should initialize multiple transports concurrently', () async {
        final transport1 = createTransport('concurrent_1');
        final transport2 = createTransport('concurrent_2');
        final transport3 = createTransport('concurrent_3');

        // Initialize all concurrently
        await Future.wait([
          transport1.initialize(),
          transport2.initialize(),
          transport3.initialize(),
        ]);

        // All should be initialized successfully
        expect(transport1.nodeId, equals('concurrent_1'));
        expect(transport2.nodeId, equals('concurrent_2'));
        expect(transport3.nodeId, equals('concurrent_3'));
      });

      test('should send data from multiple devices simultaneously', () async {
        final transport1 = createTransport('sender_1');
        final transport2 = createTransport('sender_2');
        final transport3 = createTransport('sender_3');

        await Future.wait([
          transport1.initialize(),
          transport2.initialize(),
          transport3.initialize(),
        ]);

        // Send data from all devices simultaneously
        await Future.wait([
          transport1.sendEvent(100),
          transport2.sendEvent(200),
          transport3.sendEvent(300),
        ]);

        // Send different types of data
        await Future.wait([
          transport1.sendEventWithValue(10, 11),
          transport2.sendPositionData([1.0, 2.0, 3.0]),
          transport3.sendGameData([1, 2, 3, 4, 5]),
        ]);

        // Should not throw and all transports should remain responsive
        expect(transport1.nodeId, equals('sender_1'));
        expect(transport2.nodeId, equals('sender_2'));
        expect(transport3.nodeId, equals('sender_3'));
      });
    });

    group('Isolate Separation Tests', () {
      test('should handle isolate-based transports without blocking', () async {
        final transport1 = createTransport('isolate_1', useIsolate: true);
        final transport2 = createTransport('isolate_2', useIsolate: true);

        await Future.wait([transport1.initialize(), transport2.initialize()]);

        // Allow isolates to start up
        await Future.delayed(const Duration(milliseconds: 500));

        // Send data from both isolate-based transports
        await Future.wait([
          transport1.sendEvent(1001),
          transport2.sendEvent(2002),
        ]);

        // Should not block or interfere with each other
        expect(transport1.nodeId, equals('isolate_1'));
        expect(transport2.nodeId, equals('isolate_2'));
      });

      test('should handle mixed isolate and non-isolate transports', () async {
        final isolateTransport = createTransport(
          'isolate_mixed',
          useIsolate: true,
        );
        final nonIsolateTransport = createTransport(
          'non_isolate_mixed',
          useIsolate: false,
        );

        await Future.wait([
          isolateTransport.initialize(),
          nonIsolateTransport.initialize(),
        ]);

        // Allow isolate to start up
        await Future.delayed(const Duration(milliseconds: 300));

        // Send data from both types
        await Future.wait([
          isolateTransport.sendEvent(3003),
          nonIsolateTransport.sendEvent(4004),
        ]);

        expect(isolateTransport.nodeId, equals('isolate_mixed'));
        expect(nonIsolateTransport.nodeId, equals('non_isolate_mixed'));
      });
    });

    group('Performance and Timing Tests', () {
      test('should handle high-frequency data sending', () async {
        final transport = createTransport(
          'high_freq',
          targetFrequency: 500.0,
          useIsolate: false, // Use non-isolate for faster testing
        );

        await transport.initialize();

        // Send data at high frequency
        final startTime = DateTime.now();
        const numSamples = 100;

        for (int i = 0; i < numSamples; i++) {
          await transport.sendEvent(i);
        }

        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);

        testLogController.add(
          'Sent $numSamples samples in ${duration.inMilliseconds}ms',
        );

        // Should complete within reasonable time (allow for overhead)
        expect(duration.inMilliseconds, lessThan(5000)); // 5 seconds max
      });

      test('should handle burst data sending from multiple devices', () async {
        final transport1 = createTransport('burst_1');
        final transport2 = createTransport('burst_2');
        final transport3 = createTransport('burst_3');

        await Future.wait([
          transport1.initialize(),
          transport2.initialize(),
          transport3.initialize(),
        ]);

        // Send burst of data from all devices
        const burstSize = 50;
        final futures = <Future>[];

        for (int i = 0; i < burstSize; i++) {
          futures.add(transport1.sendEvent(1000 + i));
          futures.add(transport2.sendEvent(2000 + i));
          futures.add(transport3.sendEvent(3000 + i));
        }

        final startTime = DateTime.now();
        await Future.wait(futures);
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);

        testLogController.add(
          'Burst sent ${burstSize * 3} samples in ${duration.inMilliseconds}ms',
        );

        // Should complete within reasonable time
        expect(duration.inMilliseconds, lessThan(10000)); // 10 seconds max
      });
    });

    group('Stream Handling Tests', () {
      test('should handle multiple stream subscriptions', () async {
        final transport1 = createTransport('stream_1');
        final transport2 = createTransport('stream_2');

        await Future.wait([transport1.initialize(), transport2.initialize()]);

        final receivedSamples1 = <GameDataSample>[];
        final receivedSamples2 = <GameDataSample>[];

        // Subscribe to both streams
        final subscription1 = transport1.gameDataStream.listen((sample) {
          receivedSamples1.add(sample);
        });

        final subscription2 = transport2.gameDataStream.listen((sample) {
          receivedSamples2.add(sample);
        });

        // Allow some time for potential samples (none expected in non-isolate mode)
        await Future.delayed(const Duration(milliseconds: 100));

        // Clean up subscriptions
        await subscription1.cancel();
        await subscription2.cancel();

        // Should not throw and streams should be manageable
        expect(
          receivedSamples1.length,
          equals(0),
        ); // No samples expected in test mode
        expect(
          receivedSamples2.length,
          equals(0),
        ); // No samples expected in test mode
      });

      test('should handle backward compatibility message streams', () async {
        final transport = createTransport('compat_test');
        await transport.initialize();

        final receivedMessages = <CoordinationMessage>[];

        final subscription = transport.highPerformanceMessageStream.listen((
          message,
        ) {
          receivedMessages.add(message);
        });

        // Allow some time for potential messages
        await Future.delayed(const Duration(milliseconds: 100));

        await subscription.cancel();

        // Should not throw and provide proper message stream
        expect(
          receivedMessages.length,
          equals(0),
        ); // No messages expected in test mode
      });
    });

    group('Configuration Tests', () {
      test('should handle different configurations per device', () async {
        final fastTransport = createTransport(
          'fast_device',
          targetFrequency: 1000.0,
          useBusyWait: true,
          useIsolate: false, // Keep false for testing
        );

        final slowTransport = createTransport(
          'slow_device',
          targetFrequency: 10.0,
          useBusyWait: false,
          useIsolate: false,
        );

        await Future.wait([
          fastTransport.initialize(),
          slowTransport.initialize(),
        ]);

        // Both should coexist with different configurations
        expect(fastTransport.nodeId, equals('fast_device'));
        expect(slowTransport.nodeId, equals('slow_device'));

        // Send data with different frequencies
        await Future.wait([
          fastTransport.sendEvent(9001),
          slowTransport.sendEvent(9002),
        ]);
      });

      test('should handle runtime configuration changes', () async {
        final transport = createTransport('config_change');
        await transport.initialize();

        // Change configuration at runtime
        await transport.configureRealTimePolling(
          frequency: 200.0,
          useBusyWait: true,
        );

        // Should still be responsive after configuration change
        await transport.sendEvent(5005);
        expect(transport.nodeId, equals('config_change'));
      });
    });

    group('Error Handling and Resilience Tests', () {
      test('should handle transport disposal during operation', () async {
        final transport1 = createTransport('disposal_1');
        final transport2 = createTransport('disposal_2');

        await Future.wait([transport1.initialize(), transport2.initialize()]);

        // Start sending data
        final sendingFuture = transport1.sendEvent(7007);

        // Dispose transport1 while potentially sending
        await transport1.dispose();

        // transport2 should still work
        await transport2.sendEvent(7008);
        expect(transport2.nodeId, equals('disposal_2'));

        // Wait for the potentially interrupted send to complete
        try {
          await sendingFuture;
        } catch (e) {
          // It's okay if this fails due to disposal
        }
      });

      test('should handle rapid initialization and disposal', () async {
        for (int i = 0; i < 5; i++) {
          final transport = createTransport('rapid_$i');
          await transport.initialize();
          await transport.sendEvent(8000 + i);
          await transport.dispose();
          transports.remove(transport); // Remove from cleanup list
        }
      });

      test(
        'should handle concurrent disposal of multiple transports',
        () async {
          final transport1 = createTransport('concurrent_disposal_1');
          final transport2 = createTransport('concurrent_disposal_2');
          final transport3 = createTransport('concurrent_disposal_3');

          await Future.wait([
            transport1.initialize(),
            transport2.initialize(),
            transport3.initialize(),
          ]);

          // Send some data
          await Future.wait([
            transport1.sendEvent(9001),
            transport2.sendEvent(9002),
            transport3.sendEvent(9003),
          ]);

          // Dispose all concurrently
          await Future.wait([
            transport1.dispose(),
            transport2.dispose(),
            transport3.dispose(),
          ]);

          // Remove from cleanup list since we manually disposed
          transports.removeWhere(
            (t) => [transport1, transport2, transport3].contains(t),
          );
        },
      );
    });
  });
}
