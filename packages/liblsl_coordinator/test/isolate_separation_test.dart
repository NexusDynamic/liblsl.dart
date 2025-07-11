import 'dart:async';
import 'package:test/test.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/src/coordination/lsl/high_frequency_transport.dart';
import 'test_lsl_config.dart';

/// Tests specifically focused on isolate separation and ensuring no blocking
/// These tests verify that the inlet consumer and outlet producer isolates
/// work independently without interfering with each other
void main() {
  group('Isolate Separation Tests', () {
    late List<HighFrequencyLSLTransport> transports;

    setUpAll(() {
      // Initialize LSL with test-optimized configuration
      TestLSLConfig.initializeForTesting();
    });

    setUp(() {
      transports = [];
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

      // Add delay to ensure LSL streams are fully cleaned up
      await Future.delayed(const Duration(milliseconds: 100));
    });

    /// Helper to create transport with isolates enabled
    HighFrequencyLSLTransport createIsolateTransport(
      String nodeId, {
      double targetFrequency = 100.0,
      bool useBusyWait = true,
    }) {
      final transport = HighFrequencyLSLTransport(
        streamName:
            'isolate_test_stream_${DateTime.now().millisecondsSinceEpoch}_$nodeId',
        nodeId: nodeId,
        sampleRate: targetFrequency,
        performanceConfig: HighFrequencyConfig(
          targetFrequency: targetFrequency,
          useBusyWait: useBusyWait,
          bufferSize: 100,
          useIsolate: true, // This is the key difference
          channelFormat: LSLChannelFormat.int32,
          channelCount: 2, // Support both single events and event+value pairs
        ),
        lslApiConfig: TestLSLConfig.createTestConfig(),
      );
      transports.add(transport);
      return transport;
    }

    group('Basic Isolate Functionality', () {
      test('should create and initialize isolate-based transport', () async {
        final transport = createIsolateTransport('isolate_basic');

        await transport.initialize();

        // Allow isolates to start up
        await Future.delayed(const Duration(milliseconds: 200));

        expect(transport.nodeId, equals('isolate_basic'));
        expect(transport.streamName, startsWith('isolate_test_stream'));
      });

      test('should handle isolate startup and communication', () async {
        final transport = createIsolateTransport('isolate_comm');

        await transport.initialize();

        // Wait for isolates to be ready
        await Future.delayed(const Duration(milliseconds: 100));

        // Send data through outlet isolate
        await transport.sendEvent(12345);

        // Should not block or throw
        expect(transport.nodeId, equals('isolate_comm'));
      });

      test('should handle rapid isolate operations', () async {
        final transport = createIsolateTransport('isolate_rapid');

        await transport.initialize();
        await Future.delayed(const Duration(milliseconds: 100));

        // Send multiple events rapidly
        for (int i = 0; i < 10; i++) {
          await transport.sendEvent(1000 + i);
        }

        // Should handle rapid operations without blocking
        expect(transport.nodeId, equals('isolate_rapid'));
      });
    });

    group('Multiple Isolate Transports', () {
      test('should handle multiple isolate transports concurrently', () async {
        final transport1 = createIsolateTransport('multi_1');
        final transport2 = createIsolateTransport('multi_2');
        final transport3 = createIsolateTransport('multi_3');

        // Initialize all concurrently
        await Future.wait([
          transport1.initialize(),
          transport2.initialize(),
          transport3.initialize(),
        ]);

        // Allow all isolates to start
        await Future.delayed(const Duration(milliseconds: 200));

        // Send data from all transports simultaneously
        await Future.wait([
          transport1.sendEvent(111),
          transport2.sendEvent(222),
          transport3.sendEvent(333),
        ]);

        // All should remain responsive
        expect(transport1.nodeId, equals('multi_1'));
        expect(transport2.nodeId, equals('multi_2'));
        expect(transport3.nodeId, equals('multi_3'));
      });

      test(
        'should handle different frequencies per isolate transport',
        () async {
          final highFreqTransport = createIsolateTransport(
            'high_freq',
            targetFrequency: 1000.0,
            useBusyWait: true,
          );

          final lowFreqTransport = createIsolateTransport(
            'low_freq',
            targetFrequency: 50.0,
            useBusyWait: false,
          );

          await Future.wait([
            highFreqTransport.initialize(),
            lowFreqTransport.initialize(),
          ]);

          await Future.delayed(const Duration(milliseconds: 100));

          // Both should coexist with different configurations
          await Future.wait([
            highFreqTransport.sendEvent(9999),
            lowFreqTransport.sendEvent(1111),
          ]);

          expect(highFreqTransport.nodeId, equals('high_freq'));
          expect(lowFreqTransport.nodeId, equals('low_freq'));
        },
      );
    });

    group('Non-Blocking Verification', () {
      test('should not block main thread during isolate operations', () async {
        final transport = createIsolateTransport(
          'non_blocking',
          useBusyWait: true,
        );

        await transport.initialize();
        await Future.delayed(const Duration(milliseconds: 100));

        // Measure time for operations that should not block
        final stopwatch = Stopwatch()..start();

        // These operations should complete quickly as they just send messages to isolates
        for (int i = 0; i < 50; i++) {
          await transport.sendEvent(i);
        }

        stopwatch.stop();

        // Should complete very quickly since it's just sending messages to isolates
        // Allow some overhead but should be much faster than actually processing
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 1 second max
      });

      test('should handle configuration changes without blocking', () async {
        final transport = createIsolateTransport('config_non_blocking');

        await transport.initialize();
        await Future.delayed(const Duration(milliseconds: 100));

        final stopwatch = Stopwatch()..start();

        // Configuration changes should not block
        await transport.configureRealTimePolling(
          frequency: 500.0,
          useBusyWait: false,
        );

        await transport.sendEvent(7777);

        stopwatch.stop();

        // Should complete quickly
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      });
    });

    group('Isolate Lifecycle Tests', () {
      test('should properly dispose isolates', () async {
        final transport = createIsolateTransport('lifecycle_dispose');

        await transport.initialize();
        await Future.delayed(const Duration(milliseconds: 100));

        await transport.sendEvent(8888);

        // Disposal should clean up isolates properly
        await transport.dispose();

        // Remove from cleanup list since we manually disposed
        transports.remove(transport);
      });

      test('should handle isolate errors gracefully', () async {
        final transport = createIsolateTransport('error_handling');

        await transport.initialize();
        await Future.delayed(const Duration(milliseconds: 100));

        // Send some data
        await transport.sendEvent(6666);

        // Even if there are internal isolate errors, disposal should work
        await transport.dispose();
        transports.remove(transport);
      });

      test('should handle rapid dispose after initialize', () async {
        final transport = createIsolateTransport('rapid_dispose');

        await transport.initialize();

        // Don't wait for isolates to fully start, dispose immediately
        await transport.dispose();

        transports.remove(transport);
      });
    });

    group('Stream Handling in Isolates', () {
      test('should provide streams even with isolates', () async {
        final transport = createIsolateTransport('stream_isolate');

        await transport.initialize();
        await Future.delayed(const Duration(milliseconds: 100));

        // Streams should be available
        expect(transport.gameDataStream, isA<Stream<GameDataSample>>());
        expect(transport.highPerformanceMessageStream, isA<Stream>());

        // Should be able to listen to streams
        final subscription = transport.gameDataStream.listen((sample) {
          // Handle samples from inlet isolate
        });

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();
      });

      test(
        'should handle stream subscriptions during isolate operations',
        () async {
          final transport = createIsolateTransport('stream_ops');

          await transport.initialize();
          await Future.delayed(const Duration(milliseconds: 200));

          final receivedSamples = <GameDataSample>[];

          final subscription = transport.gameDataStream.listen((sample) {
            receivedSamples.add(sample);
          });

          // Send data while listening
          await transport.sendEvent(5555);
          await transport.sendEventWithValue(10, 20);

          await Future.delayed(const Duration(milliseconds: 100));
          await subscription.cancel();

          // In a real LSL environment, we might receive samples
          // In test environment, we expect no samples from other sources
          expect(receivedSamples.length, equals(0));
        },
      );
    });

    group('Performance Under Isolate Load', () {
      test(
        'should maintain performance with multiple isolate transports',
        () async {
          // Create multiple isolate transports
          final transports = <HighFrequencyLSLTransport>[];
          for (int i = 0; i < 5; i++) {
            transports.add(createIsolateTransport('perf_$i'));
          }

          // Initialize all
          await Future.wait(transports.map((t) => t.initialize()));
          await Future.delayed(const Duration(milliseconds: 200));

          final stopwatch = Stopwatch()..start();

          // Send data from all simultaneously (reduced iterations for faster tests)
          final futures = <Future>[];
          for (int i = 0; i < 5; i++) {
            for (final transport in transports) {
              futures.add(
                transport.sendEvent(i * 1000 + transport.nodeId.hashCode),
              );
            }
          }

          await Future.wait(futures);
          stopwatch.stop();

          // Should handle load efficiently
          expect(
            stopwatch.elapsedMilliseconds,
            lessThan(2000), // Reduced timeout for faster tests
          ); // 5 seconds max

          // Clean up
          for (final transport in transports) {
            await transport.dispose();
          }
          transports.clear();
        },
      );

      test('should handle burst sending without blocking', () async {
        final transport = createIsolateTransport(
          'burst_test',
          useBusyWait: true,
        );

        await transport.initialize();
        await Future.delayed(const Duration(milliseconds: 100));

        final stopwatch = Stopwatch()..start();

        // Send a smaller burst of data for faster tests
        final futures = <Future>[];
        for (int i = 0; i < 20; i++) {
          futures.add(transport.sendEvent(i));
        }

        await Future.wait(futures);
        stopwatch.stop();

        // Should handle burst efficiently (just queuing messages to isolate)
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 1 second max
      });
    });
  });
}
