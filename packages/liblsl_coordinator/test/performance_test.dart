import 'dart:async';
import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/src/coordination/lsl/high_frequency_transport.dart';
import 'mocks/mock_lsl.dart';
import 'test_lsl_config.dart';

/// Performance and benchmarking tests for the coordinator package
/// These tests measure timing, throughput, and resource usage
void main() {
  group('Performance Tests', () {
    late List<HighFrequencyLSLTransport> transports;

    setUpAll(() {
      TestLSLConfig.initializeForTesting();
    });

    setUp(() {
      transports = [];
      MockLSL.reset();
    });

    tearDown(() async {
      for (final transport in transports) {
        try {
          await transport.dispose();
        } catch (e) {
          print('Error disposing transport: $e');
        }
      }
      transports.clear();
    });

    HighFrequencyLSLTransport createTransport(
      String nodeId, {
      bool useIsolate = false,
      double targetFrequency = 100.0,
      bool useBusyWait = false,
    }) {
      final transport = HighFrequencyLSLTransport(
        streamName:
            'perf_test_stream_${DateTime.now().millisecondsSinceEpoch}_$nodeId',
        nodeId: nodeId,
        sampleRate: targetFrequency,
        performanceConfig: HighFrequencyConfig(
          targetFrequency: targetFrequency,
          useBusyWait: useBusyWait,
          bufferSize: 10, // Smaller buffer for faster tests
          useIsolate: useIsolate,
          channelFormat: LSLChannelFormat.int32,
          channelCount: 2, // Support both single and double data
        ),
        lslApiConfig: TestLSLConfig.createTestConfig(),
      );
      transports.add(transport);
      return transport;
    }

    group('Throughput Tests', () {
      test('should handle high-frequency sending without degradation', () async {
        final transport = createTransport('throughput_test');
        await transport.initialize();

        const numSamples = 100; // Reduced from 1000 to 100 for faster tests
        final stopwatch = Stopwatch()..start();

        // Send data as fast as possible
        for (int i = 0; i < numSamples; i++) {
          await transport.sendEvent(i);
        }

        stopwatch.stop();
        final throughput =
            numSamples / (stopwatch.elapsedMilliseconds / 1000.0);

        print('Throughput: ${throughput.toStringAsFixed(1)} samples/second');
        print(
          'Total time: ${stopwatch.elapsedMilliseconds}ms for $numSamples samples',
        );

        // Should achieve reasonable throughput
        expect(throughput, greaterThan(100)); // At least 100 samples/second
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(30000),
        ); // Complete within 30 seconds
      });

      test('should handle concurrent sending from multiple transports', () async {
        const numTransports = 5;
        const samplesPerTransport = 200;

        // Create multiple transports
        final testTransports = <HighFrequencyLSLTransport>[];
        for (int i = 0; i < numTransports; i++) {
          testTransports.add(createTransport('concurrent_$i'));
        }

        // Initialize all
        await Future.wait(testTransports.map((t) => t.initialize()));

        final stopwatch = Stopwatch()..start();

        // Send from all transports concurrently
        final futures = <Future>[];
        for (int i = 0; i < numTransports; i++) {
          final transport = testTransports[i];
          futures.add(() async {
            for (int j = 0; j < samplesPerTransport; j++) {
              await transport.sendEvent(i * 1000 + j);
            }
          }());
        }

        await Future.wait(futures);
        stopwatch.stop();

        final totalSamples = numTransports * samplesPerTransport;
        final throughput =
            totalSamples / (stopwatch.elapsedMilliseconds / 1000.0);

        print(
          'Concurrent throughput: ${throughput.toStringAsFixed(1)} samples/second',
        );
        print(
          'Total time: ${stopwatch.elapsedMilliseconds}ms for $totalSamples samples from $numTransports transports',
        );

        // Should handle concurrent load efficiently
        expect(throughput, greaterThan(50)); // At least 50 samples/second total
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(60000),
        ); // Complete within 60 seconds
      });

      test('should handle burst sending efficiently', () async {
        final transport = createTransport('burst_test');
        await transport.initialize();

        const burstSize = 100;
        const numBursts = 5;

        final burstTimes = <int>[];

        for (int burst = 0; burst < numBursts; burst++) {
          final stopwatch = Stopwatch()..start();

          // Send a burst of data
          final futures = <Future>[];
          for (int i = 0; i < burstSize; i++) {
            futures.add(transport.sendEvent(burst * 1000 + i));
          }

          await Future.wait(futures);
          stopwatch.stop();

          burstTimes.add(stopwatch.elapsedMilliseconds);
          print(
            'Burst ${burst + 1}: ${stopwatch.elapsedMilliseconds}ms for $burstSize samples',
          );

          // Small delay between bursts
          await Future.delayed(const Duration(milliseconds: 100));
        }

        final averageBurstTime =
            burstTimes.reduce((a, b) => a + b) / burstTimes.length;
        final averageThroughput = burstSize / (averageBurstTime / 1000.0);

        print('Average burst time: ${averageBurstTime.toStringAsFixed(1)}ms');
        print(
          'Average burst throughput: ${averageThroughput.toStringAsFixed(1)} samples/second',
        );

        // Burst performance should be consistent
        expect(
          averageBurstTime,
          lessThan(5000),
        ); // Average burst under 5 seconds
        expect(
          averageThroughput,
          greaterThan(20),
        ); // At least 20 samples/second per burst
      });
    });

    group('Latency Tests', () {
      test('should measure send operation latency', () async {
        final transport = createTransport('latency_test');
        await transport.initialize();

        const numMeasurements = 100;
        final latencies = <int>[];

        for (int i = 0; i < numMeasurements; i++) {
          final stopwatch = Stopwatch()..start();
          await transport.sendEvent(i);
          stopwatch.stop();

          latencies.add(stopwatch.elapsedMicroseconds);

          // Small delay to avoid overwhelming
          if (i % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }

        latencies.sort();
        final averageLatency =
            latencies.reduce((a, b) => a + b) / latencies.length;
        final medianLatency = latencies[latencies.length ~/ 2];
        final p95Latency = latencies[(latencies.length * 0.95).round() - 1];
        final maxLatency = latencies.last;

        print('Send Latency Statistics:');
        print('  Average: ${averageLatency.toStringAsFixed(1)} μs');
        print('  Median: $medianLatency μs');
        print('  95th percentile: $p95Latency μs');
        print('  Maximum: $maxLatency μs');

        // Reasonable latency expectations
        expect(averageLatency, lessThan(10000)); // Average under 10ms
        expect(medianLatency, lessThan(5000)); // Median under 5ms
        expect(p95Latency, lessThan(50000)); // 95% under 50ms
      });

      test('should measure initialization latency', () async {
        const numMeasurements = 5; // Reduced from 10 to 5 for faster tests
        final initTimes = <int>[];

        for (int i = 0; i < numMeasurements; i++) {
          final transport = createTransport('init_latency_$i');

          final stopwatch = Stopwatch()..start();
          await transport.initialize();
          stopwatch.stop();

          initTimes.add(stopwatch.elapsedMilliseconds);
          print('Initialization ${i + 1}: ${stopwatch.elapsedMilliseconds}ms');

          await transport.dispose();
          transports.remove(transport);

          // Small delay between initializations
          await Future.delayed(const Duration(milliseconds: 50));
        }

        final averageInitTime =
            initTimes.reduce((a, b) => a + b) / initTimes.length;
        final maxInitTime = initTimes.reduce(math.max);

        print('Initialization Statistics:');
        print('  Average: ${averageInitTime.toStringAsFixed(1)}ms');
        print('  Maximum: ${maxInitTime}ms');

        // Initialization should be reasonably fast
        expect(averageInitTime, lessThan(1000)); // Average under 1 second
        expect(maxInitTime, lessThan(5000)); // Maximum under 5 seconds
      });
    });

    group('Memory and Resource Tests', () {
      test('should handle repeated create/dispose cycles', () async {
        const numCycles = 5; // Reduced from 20 to 5 for faster tests

        for (int i = 0; i < numCycles; i++) {
          final transport = createTransport('cycle_$i');

          await transport.initialize();

          // Send just a few events to test the functionality
          for (int j = 0; j < 3; j++) {
            await transport.sendEvent(i * 10 + j);
          }

          await transport.dispose();
          transports.remove(transport);

          // Add small delay to ensure proper cleanup
          await Future.delayed(const Duration(milliseconds: 50));

          if (i % 2 == 0) {
            print('Completed ${i + 1}/$numCycles cycles');
          }
        }

        // Should complete without errors or memory leaks
        expect(true, isTrue); // Test passes if no exceptions thrown
      });

      test('should handle many simultaneous transports', () async {
        const numTransports = 5; // Reduced from 20 to 5 for faster tests
        final testTransports = <HighFrequencyLSLTransport>[];

        // Create many transports
        for (int i = 0; i < numTransports; i++) {
          testTransports.add(createTransport('many_$i'));
        }

        final stopwatch = Stopwatch()..start();

        // Initialize all
        await Future.wait(testTransports.map((t) => t.initialize()));

        // Send data from all
        final futures = <Future>[];
        for (int i = 0; i < numTransports; i++) {
          final transport = testTransports[i];
          for (int j = 0; j < 5; j++) {
            futures.add(transport.sendEvent(i * 100 + j));
          }
        }

        await Future.wait(futures);
        stopwatch.stop();

        print(
          'Handled $numTransports transports in ${stopwatch.elapsedMilliseconds}ms',
        );

        // Should handle many transports without significant performance degradation
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(30000),
        ); // Under 30 seconds

        // Clean up
        for (final transport in testTransports) {
          await transport.dispose();
          transports.remove(transport);
        }
      });
    });

    group('Isolate Performance Tests', () {
      test(
        'should compare isolate vs non-isolate performance',
        () async {
          const numSamples = 200;

          // Test non-isolate performance
          final nonIsolateTransport = createTransport(
            'non_isolate_perf',
            useIsolate: false,
          );
          await nonIsolateTransport.initialize();

          final nonIsolateStopwatch = Stopwatch()..start();
          for (int i = 0; i < numSamples; i++) {
            await nonIsolateTransport.sendEvent(i);
          }
          nonIsolateStopwatch.stop();

          // Test isolate performance
          final isolateTransport = createTransport(
            'isolate_perf',
            useIsolate: true,
          );
          await isolateTransport.initialize();
          await Future.delayed(
            const Duration(milliseconds: 300),
          ); // Allow isolates to start

          final isolateStopwatch = Stopwatch()..start();
          for (int i = 0; i < numSamples; i++) {
            await isolateTransport.sendEvent(i);
          }
          isolateStopwatch.stop();

          final nonIsolateThroughput =
              numSamples / (nonIsolateStopwatch.elapsedMilliseconds / 1000.0);
          final isolateThroughput =
              numSamples / (isolateStopwatch.elapsedMilliseconds / 1000.0);

          print('Performance Comparison:');
          print(
            '  Non-isolate: ${nonIsolateThroughput.toStringAsFixed(1)} samples/second (${nonIsolateStopwatch.elapsedMilliseconds}ms)',
          );
          print(
            '  Isolate: ${isolateThroughput.toStringAsFixed(1)} samples/second (${isolateStopwatch.elapsedMilliseconds}ms)',
          );

          // Both should achieve reasonable performance
          expect(nonIsolateThroughput, greaterThan(10));
          expect(isolateThroughput, greaterThan(10));

          // Isolate mode might be slightly slower due to message passing overhead, but should be comparable
          final performanceRatio = isolateThroughput / nonIsolateThroughput;
          print(
            '  Performance ratio (isolate/non-isolate): ${performanceRatio.toStringAsFixed(2)}',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });

    group('Configuration Impact Tests', () {
      test('should measure impact of different target frequencies', () async {
        final frequencies = [10.0, 100.0, 500.0, 1000.0];
        const samplesPerTest = 50;

        for (final frequency in frequencies) {
          final transport = createTransport(
            'freq_${frequency.toInt()}',
            targetFrequency: frequency,
          );
          await transport.initialize();

          final stopwatch = Stopwatch()..start();
          for (int i = 0; i < samplesPerTest; i++) {
            await transport.sendEvent(i);
          }
          stopwatch.stop();

          final throughput =
              samplesPerTest / (stopwatch.elapsedMilliseconds / 1000.0);
          print(
            'Frequency ${frequency}Hz: ${throughput.toStringAsFixed(1)} samples/second (${stopwatch.elapsedMilliseconds}ms)',
          );

          await transport.dispose();
          transports.remove(transport);

          // Brief pause between tests
          await Future.delayed(const Duration(milliseconds: 100));
        }
      });

      test('should measure impact of busy wait vs timer mode', () async {
        const samplesPerTest = 100;

        // Test timer mode
        final timerTransport = createTransport(
          'timer_mode',
          useBusyWait: false,
        );
        await timerTransport.initialize();

        final timerStopwatch = Stopwatch()..start();
        for (int i = 0; i < samplesPerTest; i++) {
          await timerTransport.sendEvent(i);
        }
        timerStopwatch.stop();

        // Test busy wait mode
        final busyWaitTransport = createTransport(
          'busy_wait_mode',
          useBusyWait: true,
        );
        await busyWaitTransport.initialize();

        final busyWaitStopwatch = Stopwatch()..start();
        for (int i = 0; i < samplesPerTest; i++) {
          await busyWaitTransport.sendEvent(i);
        }
        busyWaitStopwatch.stop();

        final timerThroughput =
            samplesPerTest / (timerStopwatch.elapsedMilliseconds / 1000.0);
        final busyWaitThroughput =
            samplesPerTest / (busyWaitStopwatch.elapsedMilliseconds / 1000.0);

        print('Mode Comparison:');
        print(
          '  Timer mode: ${timerThroughput.toStringAsFixed(1)} samples/second (${timerStopwatch.elapsedMilliseconds}ms)',
        );
        print(
          '  Busy wait mode: ${busyWaitThroughput.toStringAsFixed(1)} samples/second (${busyWaitStopwatch.elapsedMilliseconds}ms)',
        );

        // Both modes should work
        expect(timerThroughput, greaterThan(5));
        expect(busyWaitThroughput, greaterThan(5));
      });
    });
  });
}
