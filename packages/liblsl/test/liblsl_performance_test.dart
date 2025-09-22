import 'dart:async';
import 'dart:math';

import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1',
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLPerformanceTestSession',
      unicastMinRTT: 0.1,
      multicastMinRTT: 0.1,
      portRange: 64,
      // don't bother checking during the test
      watchdogCheckInterval: 600.0,
      sendSocketBufferSize: 1024,
      receiveSocketBufferSize: 1024,
      outletBufferReserveMs: 2000,
      inletBufferReserveMs: 2000,
    );
    LSL.setConfigContent(apiConfig);
  });

  group('LSL Performance Tests', () {
    test('Performance Matrix Test', () async {
      final performanceTester = LSLPerformanceTester();
      await performanceTester.runPerformanceMatrix();
    });
  });
}

class LSLPerformanceTester {
  static const List<int> streamCounts = [1, 8];
  static const List<int> channelCounts = [1, 2, 16, 64];
  static const List<double> frequencies = [50, 500, 1000, 10_000];
  static const int testDurationSeconds = 3;

  final List<PerformanceResult> results = [];

  Future<void> runPerformanceMatrix() async {
    print('Starting LSL Performance Test Matrix');
    print('Streams: $streamCounts');
    print('Channels: $channelCounts');
    print('Frequencies: $frequencies');
    print('Test Duration: ${testDurationSeconds}s per configuration');
    print(
      'Total Configurations: ${streamCounts.length * channelCounts.length * frequencies.length}',
    );
    print('Note: This is not the most performance-optimized test, because:');
    print('  - Usually you would not need so many outlets (1 producer)');
    print('  - Inlets should run in a single isolate and bulk-poll all inlets');
    print(
      '  - Reported latency is larger than it real latency (polling interval, start time differences)',
    );
    print('  - For high inter-sample-interval accuracy (in sample production)');
    print('    ideally the outlet runs in an isolate, but with sync pushing');
    print('    of samples using the busy wait loop. Or consider using an RTOS');
    print('    with precise scheduling.');
    print('=' * 80);

    for (final streamCount in streamCounts) {
      for (final channelCount in channelCounts) {
        for (final frequency in frequencies) {
          print(
            '\nTesting: $streamCount streams, $channelCount channels, ${frequency}Hz',
          );

          final result = await _runSingleTest(
            streamCount: streamCount,
            channelCount: channelCount,
            frequency: frequency,
          );

          results.add(result);
          _printSingleResult(result);
        }
      }
    }

    _printSummaryReport();
  }

  Future<PerformanceResult> _runSingleTest({
    required int streamCount,
    required int channelCount,
    required double frequency,
  }) async {
    final List<LSLOutlet> outlets = [];
    final List<LSLInlet<double>> inlets = [];
    final List<Completer<void>> completers = [];

    final int expectedSamples =
        (frequency * testDurationSeconds).round() * streamCount;
    final statistics = TestStatistics(expectedSamples);
    final random = Random();

    try {
      // Create a random test instance id
      final testInstanceId = random.nextInt(1 << 32);
      // Create resolver instance
      final resolver = LSLStreamResolver(maxStreams: streamCount);
      // allocate the stream buffer
      resolver.create();
      // Create outlets and inlets
      final String streamName =
          'PerfTest_${testInstanceId}_${streamCount}_${channelCount}_$frequency';
      for (int i = 0; i < streamCount; i++) {
        final streamInfo = await LSL.createStreamInfo(
          streamName: streamName,
          channelCount: channelCount,
          channelFormat: LSLChannelFormat.double64,
          sampleRate: frequency,
          streamType: LSLContentType.eeg,
          sourceId: '${streamName}_$i',
        );
        final outlet = await LSL.createOutlet(
          streamInfo: streamInfo,
          maxBuffer: 1,
          chunkSize: 1,
          useIsolates: false,
        );
        outlets.add(outlet);
      }

      // Wait briefly for outlets to be discoverable
      await Future.delayed(Duration(milliseconds: 150));

      // Resolve streams
      final testStreams = await resolver.resolveByProperty(
        property: LSLStreamProperty.name,
        value: streamName,
        waitTime: 5.0,
        minStreamCount: streamCount,
      );

      resolver.destroy();

      // Sort streams by name to match with outlets
      testStreams.sort((a, b) => a.streamName.compareTo(b.streamName));

      // Create inlets for the resolved streams
      int createdInlets = 0;
      for (LSLStreamInfo info in testStreams) {
        final inlet = await LSL.createInlet<double>(
          streamInfo: info,
          maxBuffer: 1,
          chunkSize: 1,
          recover: true,
          useIsolates: false, // Inlets in main isolate, only with timeout 0.0
        );
        inlets.add(inlet);
        createdInlets++;
        if (createdInlets >= streamCount) break;
      }
      if (inlets.length < streamCount) {
        throw Exception(
          'Could not create enough inlets. Expected $streamCount, created ${inlets.length}',
        );
      }

      // Start data consumers
      // the latency reporting is not completely accurate because if there is
      // a difference in start time between producer and consumer
      // the latency will be off by that difference (hopefully constant)
      final interval = Duration(microseconds: 1_000_000 ~/ frequency);
      _startDataConsumer(inlets, statistics, completers, interval);

      // Start data producers
      final producerFutures = <Future>[];
      final future = _startDataProducer(
        outlets,
        channelCount,
        frequency,
        testDurationSeconds,
        statistics,
        random,
      );
      producerFutures.add(future);

      // Wait for test duration
      final startTime = DateTime.now();
      await Future.wait(producerFutures);
      final endTime = DateTime.now();

      // Calculate final statistics
      final actualDuration =
          endTime.difference(startTime).inMilliseconds / 1_000.0;

      // Wait until all sent samples are received or timeout after 5 seconds
      final timeout = DateTime.now().add(Duration(seconds: 5));
      while (statistics.samplesSent > statistics.samplesReceived) {
        if (DateTime.now().isAfter(timeout)) {
          print('Timeout waiting for samples to be received');
          break;
        }
        await Future.delayed(Duration(milliseconds: 100));
      }
      // Stop consumers
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      return PerformanceResult(
        streamCount: streamCount,
        channelCount: channelCount,
        frequency: frequency,
        duration: actualDuration,
        samplesSent: statistics.samplesSent,
        samplesReceived: statistics.samplesReceived,
        averageLatency: statistics.getAverageLatency(),
        stdDevLatency: statistics.getStdDevLatency(),
        minLatency: statistics.minLatency,
        maxLatency: statistics.maxLatency,
        packetsLost: statistics.samplesSent - statistics.samplesReceived,
        throughputMBps: statistics.getThroughputMBps(actualDuration),
        cpuUsage: await _estimateCpuUsage(),
      );
    } finally {
      // Cleanup
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      for (final inlet in inlets) {
        await inlet.destroy();
      }
      for (final outlet in outlets) {
        await outlet.destroy();
      }
    }
  }

  Future<void> _startDataProducer(
    List<LSLOutlet> outlets,
    int channelCount,
    double frequency,
    int durationSeconds,
    TestStatistics statistics,
    Random random,
  ) async {
    final intervalMicroseconds = (1_000_000 / frequency).round();
    final totalSamples = (frequency * durationSeconds).round();

    var sentSamples = 0;
    final stopwatch = Stopwatch()..start();
    final futures = <LSLOutlet, Future?>{};
    while (sentSamples < totalSamples &&
        stopwatch.elapsedMilliseconds < durationSeconds * 1_000) {
      // Generate sample data
      final sample = List.generate(
        channelCount,
        (_) => random.nextDouble() * 100 - 50,
      );

      // Push sample
      for (final outlet in outlets) {
        // Add timestamp for latency measurement
        sample[0] = LSL.localClock();
        // Track the last push future to avoid overwhelming the outlet
        futures[outlet]?.ignore();
        futures[outlet] = outlet.pushSample(sample);
        // outlet.pushSampleSync(sample);
        statistics.samplesSent++;
      }

      sentSamples++;

      // Precise timing control
      final targetTime = sentSamples * intervalMicroseconds;
      final currentTime = stopwatch.elapsedMicroseconds;
      final sleepTime = targetTime - currentTime;

      if (sleepTime > 0) {
        await Future.delayed(Duration(microseconds: sleepTime));
      }
    }
    // Wait for all pending pushes to complete
    await Future.wait(futures.values.whereType<Future>());
    stopwatch.stop();
  }

  Future<void> _startDataConsumer(
    List<LSLInlet<double>> inlets,
    TestStatistics statistics,
    List<Completer<void>> completers,
    Duration interval,
  ) async {
    final completer = Completer<void>();
    completers.add(completer);
    await runPreciseIntervalAsync(
      interval,
      (state) async {
        for (final inlet in inlets) {
          try {
            final sample = inlet.pullSampleSync(timeout: 0.0);

            if (sample.data.isNotEmpty) {
              // print('  Received sample from ${inlet.streamInfo.streamName}');
              statistics.samplesReceived++;

              // Calculate latency using first channel timestamp
              final sentTimestamp = sample.data[0];
              final receivedTimestamp = LSL.localClock();
              final latency =
                  (receivedTimestamp - sentTimestamp) *
                  1_000; // Convert to milliseconds

              statistics.addLatency(latency);
            }
          } catch (e) {
            // Sample not available, continue
          }
        }
      },
      completer: completer,
      state: null,
      startBusyAt: Duration(microseconds: interval.inMicroseconds ~/ 1.001),
    );
  }

  Future<double> _estimateCpuUsage() async {
    // Placeholder for CPU usage estimation

    return 0.0;
  }

  void _printSingleResult(PerformanceResult result) {
    print(
      '  Samples: ${result.samplesSent} sent, ${result.samplesReceived} received',
    );
    print(
      '  Packet Loss: ${result.packetsLost} (${(result.packetsLost / result.samplesSent * 100).toStringAsFixed(2)}%)',
    );
    print(
      '  Latency: ${result.averageLatency.toStringAsFixed(2)}ms avg, ${result.minLatency.toStringAsFixed(2)}-${result.maxLatency.toStringAsFixed(2)}ms range',
    );
    print('  Throughput: ${result.throughputMBps.toStringAsFixed(2)} MB/s');
  }

  void _printSummaryReport() {
    print('\n${'=' * 80}');
    print('PERFORMANCE TEST SUMMARY');
    print('=' * 80);

    // Print all results in table format
    print('\nComplete Results Table:');
    print(
      'Streams | Channels | Freq(Hz) | Throughput(MB/s) | μ Latency(ms) | 𝛔 Latency(ms) | Min Latency(ms) | Max Latency(ms) | Packet Loss(%)',
    );
    print('-' * 95);

    results.sort((a, b) {
      final streamCmp = a.streamCount.compareTo(b.streamCount);
      if (streamCmp != 0) return streamCmp;
      final channelCmp = a.channelCount.compareTo(b.channelCount);
      if (channelCmp != 0) return channelCmp;
      return a.frequency.compareTo(b.frequency);
    });

    for (final r in results) {
      final lossPercent = (r.packetsLost / r.samplesSent * 100);
      print(
        '${r.streamCount.toString().padLeft(7)} |'
        ' ${r.channelCount.toString().padLeft(8)} |'
        ' ${r.frequency.toStringAsFixed(0).padLeft(8)} |'
        ' ${r.throughputMBps.toStringAsFixed(4).padLeft(16)} |'
        ' ${r.averageLatency.toStringAsFixed(4).padLeft(13)} |'
        ' ${r.stdDevLatency.toStringAsFixed(4).padLeft(13)} |'
        ' ${r.minLatency.toStringAsFixed(4).padLeft(15)} |'
        ' ${r.maxLatency.toStringAsFixed(4).padLeft(15)} |'
        ' ${lossPercent.toStringAsFixed(4).padLeft(13)} |',
      );
    }
  }
}

class PerformanceResult {
  final int streamCount;
  final int channelCount;
  final double frequency;
  final double duration;
  final int samplesSent;
  final int samplesReceived;
  final double averageLatency;
  final double stdDevLatency;
  final double minLatency;
  final double maxLatency;
  final int packetsLost;
  final double throughputMBps;
  final double cpuUsage;

  PerformanceResult({
    required this.streamCount,
    required this.channelCount,
    required this.frequency,
    required this.duration,
    required this.samplesSent,
    required this.samplesReceived,
    required this.averageLatency,
    required this.stdDevLatency,
    required this.minLatency,
    required this.maxLatency,
    required this.packetsLost,
    required this.throughputMBps,
    required this.cpuUsage,
  });
}

class TestStatistics {
  int samplesSent = 0;
  int samplesReceived = 0;
  int index = 0;
  final List<double> _latencies;
  List<double> get latencies => _latencies.sublist(0, index);
  double minLatency = double.infinity;
  double maxLatency = 0.0;
  final int expectedSamples;
  bool get isFull => index >= expectedSamples;

  TestStatistics(this.expectedSamples)
    : _latencies = List<double>.filled(expectedSamples, 0.0, growable: false);

  void addLatency(double latency) {
    if (isFull) {
      print('Warning: Latency array full, cannot add more latencies');
      return;
    }
    _latencies[index] = latency;
    index++;
    if (latency < minLatency) minLatency = latency;
    if (latency > maxLatency) maxLatency = latency;
  }

  double getAverageLatency() {
    if (latencies.isEmpty) return 0.0;
    return latencies.reduce((a, b) => a + b) / latencies.length;
  }

  double getStdDevLatency() {
    final avg = getAverageLatency();
    final sumOfSquares = latencies
        .map((lat) => (lat - avg) * (lat - avg))
        .reduce((a, b) => a + b);
    return sqrt(sumOfSquares / latencies.length);
  }

  double getThroughputMBps(double duration) {
    // Assume 8 bytes per double (64-bit)
    final totalBytes = samplesReceived * 8.0;
    final totalMB = totalBytes / (1_024 * 1_024);
    return totalMB / duration;
  }
}
