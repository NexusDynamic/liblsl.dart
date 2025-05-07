import 'dart:async';
import 'dart:math' as math;
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/tests/base/lsl_test.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/tests/base/timing_test.dart';

class SampleRateStabilityTest extends BaseTimingTest with LSLStreamHelper {
  int sampleCounter = 0;
  double sampleIntervalMs = 0.0;
  // Create a list to store expected vs actual sample times
  final expectedTimes = <double>[];
  final actualTimes = <double>[];
  final receivedTimestamps = <double>[];

  @override
  String get name => 'Sample Rate Stability';

  @override
  String get description =>
      'Tests the stability of the LSL sample rate under different conditions';

  @override
  Future<void> setupTestResources(
    TimingManager timingManager,
    TestConfiguration config,
  ) async {
    // Reset the timing manager
    timingManager.reset();
    sampleCounter = 0;
    sampleIntervalMs = 1000.0 / config.sampleRate;

    // Create the stream info
    final streamInfo = await createStreamInfo(config);

    // Create the outlet
    await createOutlet(streamInfo);

    // Find our own stream
    LSLStreamInfo? resolvedStreamInfo = await findStream(config.streamName);

    if (resolvedStreamInfo == null) {
      timingManager.recordEvent(
        'stream_resolution_failed',
        description: 'Could not find our own stream',
      );
      throw Exception('Could not find our own stream for loopback testing');
    }

    // Create an inlet from the resolved stream info
    await createInlet(resolvedStreamInfo);
  }

  @override
  Future<void> runTestImplementation(
    TimingManager timingManager,
    TestConfiguration config,
    Completer<void> completer,
  ) async {
    // Start time reference
    final startTime = DateTime.now().microsecondsSinceEpoch / 1000000;

    // Timer that tries to send samples at precise intervals
    final sendTimer = Timer.periodic(
      Duration(milliseconds: sampleIntervalMs.round()),
      (timer) {
        sampleCounter++;

        if (sampleCounter > config.sampleRate * config.testDurationSeconds) {
          timer.cancel();
          // Give some time for the last samples to be received
          Future.delayed(const Duration(seconds: 2), () {
            if (!completer.isCompleted) completer.complete();
          });
          return;
        }

        // Calculate expected time for this sample
        final expectedTime =
            startTime + (sampleCounter * sampleIntervalMs / 1000.0);
        expectedTimes.add(expectedTime);

        // Record actual time
        final actualTime = DateTime.now().microsecondsSinceEpoch / 1000000;
        actualTimes.add(actualTime);

        // Record sample timing
        timingManager.recordEvent(
          'sample_scheduled',
          description: 'Sample $sampleCounter scheduled',
          metadata: {
            'sampleId': sampleCounter,
            'expectedTime': expectedTime,
            'actualTime': actualTime,
            'deviation': actualTime - expectedTime,
          },
        );

        // Push the sample with the counter as value
        outletCache.values.first
            .pushSample(
              List.generate(
                config.channelCount,
                (index) => sampleCounter.toDouble(),
              ),
            )
            .then((_) {
              // Record the LSL time
              final lslTime = LSL.localClock();
              timingManager.recordTimestampedEvent(
                'lsl_timestamp',
                lslTime,
                description: 'LSL timestamp for sample $sampleCounter',
                metadata: {
                  'sampleId': sampleCounter,
                  'expectedTime': expectedTime,
                  'actualTime': actualTime,
                  'lslTime': lslTime,
                },
              );
              timingManager.recordEvent(
                'sample_sent',
                description: 'Sample $sampleCounter sent to LSL',
                metadata: {'sampleId': sampleCounter, 'lslTime': lslTime},
              );
            });
      },
    );

    // Set up a pull loop to receive samples
    void pullSamples() async {
      while (!completer.isCompleted) {
        try {
          // Pull sample with a small timeout
          final sample = await inletCache.values.first.pullSample(timeout: 0.1);

          // Only process if we got a valid sample
          if (sample.isNotEmpty) {
            // Extract the sample ID (counter)
            final sampleId = sample[0].toInt();
            final receiveTime = DateTime.now().microsecondsSinceEpoch / 1000000;

            receivedTimestamps.add(receiveTime);

            // Record the receive time
            timingManager.recordEvent(
              'sample_received',
              description: 'Sample $sampleId received',
              metadata: {
                'sampleId': sampleId,
                'timestamp': sample.timestamp,
                'receiveTime': receiveTime,
              },
            );
          }
        } catch (e) {
          // Handle errors gracefully
          print('Error pulling sample: $e');
        }

        // Small delay to avoid hammering the CPU
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }

    // Start the pull loop
    pullSamples();

    await completer.future;

    sendTimer.cancel();

    // Calculate and record jitter statistics
    if (expectedTimes.length > 1 &&
        actualTimes.length == expectedTimes.length) {
      // Calculate timing jitter (deviation from expected times)
      final deviations = <double>[];
      for (int i = 0; i < expectedTimes.length; i++) {
        deviations.add(actualTimes[i] - expectedTimes[i]);
      }

      // Calculate statistics
      final avgDeviation =
          deviations.reduce((a, b) => a + b) / deviations.length;
      final maxDeviation = deviations.reduce(math.max);
      final minDeviation = deviations.reduce(math.min);

      // Calculate standard deviation
      final sumSquaredDiff = deviations.fold(
        0.0,
        (sum, value) => sum + math.pow(value - avgDeviation, 2),
      );
      final stdDev = math.sqrt(sumSquaredDiff / deviations.length);

      // Record these stats
      timingManager.recordEvent(
        'jitter_stats',
        description: 'Sample timing jitter statistics',
        metadata: {
          'avgDeviation': avgDeviation,
          'maxDeviation': maxDeviation,
          'minDeviation': minDeviation,
          'stdDev': stdDev,
          'sampleCount': deviations.length,
        },
      );
    }

    // Also calculate inter-sample intervals for both send and receive
    if (actualTimes.length > 1) {
      final sendIntervals = <double>[];
      for (int i = 1; i < actualTimes.length; i++) {
        sendIntervals.add(actualTimes[i] - actualTimes[i - 1]);
      }

      // Calculate statistics for send intervals
      final avgSendInterval =
          sendIntervals.reduce((a, b) => a + b) / sendIntervals.length;
      final maxSendInterval = sendIntervals.reduce(math.max);
      final minSendInterval = sendIntervals.reduce(math.min);

      // Calculate standard deviation
      final sumSquaredDiff = sendIntervals.fold(
        0.0,
        (sum, value) => sum + math.pow(value - avgSendInterval, 2),
      );
      final stdDevSend = math.sqrt(sumSquaredDiff / sendIntervals.length);

      // Record send interval stats
      timingManager.recordEvent(
        'send_interval_stats',
        description: 'Sample sending interval statistics',
        metadata: {
          'avgInterval': avgSendInterval,
          'maxInterval': maxSendInterval,
          'minInterval': minSendInterval,
          'stdDev': stdDevSend,
          'idealInterval': sampleIntervalMs / 1000.0,
          'sampleCount': sendIntervals.length,
        },
      );
    }

    // Do the same for receive times
    if (receivedTimestamps.length > 1) {
      final receiveIntervals = <double>[];
      for (int i = 1; i < receivedTimestamps.length; i++) {
        receiveIntervals.add(receivedTimestamps[i] - receivedTimestamps[i - 1]);
      }

      // Calculate statistics for receive intervals
      final avgReceiveInterval =
          receiveIntervals.reduce((a, b) => a + b) / receiveIntervals.length;
      final maxReceiveInterval = receiveIntervals.reduce(math.max);
      final minReceiveInterval = receiveIntervals.reduce(math.min);

      // Calculate standard deviation
      final sumSquaredDiff = receiveIntervals.fold(
        0.0,
        (sum, value) => sum + math.pow(value - avgReceiveInterval, 2),
      );
      final stdDevReceive = math.sqrt(sumSquaredDiff / receiveIntervals.length);

      // Record receive interval stats
      timingManager.recordEvent(
        'receive_interval_stats',
        description: 'Sample receiving interval statistics',
        metadata: {
          'avgInterval': avgReceiveInterval,
          'maxInterval': maxReceiveInterval,
          'minInterval': minReceiveInterval,
          'stdDev': stdDevReceive,
          'idealInterval': sampleIntervalMs / 1000.0,
          'sampleCount': receiveIntervals.length,
        },
      );
    }
  }

  @override
  Future<void> cleanupTestResources() async {
    // Clean up
    await cleanupLSL();
    expectedTimes.clear();
    actualTimes.clear();
    receivedTimestamps.clear();
    sampleCounter = 0;
    sampleIntervalMs = 0;
  }

  @override
  void setTestSpecificConfig(Map<String, dynamic> config) {}

  @override
  Map<String, dynamic>? get testSpecificConfig => throw UnimplementedError();
}
