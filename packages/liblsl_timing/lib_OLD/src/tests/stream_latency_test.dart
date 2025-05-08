import 'dart:async';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/tests/base/lsl_test.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/tests/base/timing_test.dart';

class StreamLatencyTest extends BaseTimingTest with LSLStreamHelper {
  Timer? sendTimer;
  int sampleCounter = 0;

  @override
  String get name => 'Stream Latency Test';

  @override
  String get description =>
      'Measures latency between sending data through LSL and receiving it';

  @override
  Future<void> setupTestResources(
    TimingManager timingManager,
    TestConfiguration config,
  ) async {
    timingManager.reset();
    sampleCounter = 0;
    // Create the stream info for our outlet
    final outletStreamInfo = await createStreamInfo(config);

    // Create the outlet
    await createOutlet(outletStreamInfo);

    timingManager.recordEvent(
      'initial_sample_sent',
      description: 'Initial sample sent to LSL',
      metadata: {'sampleId': 0},
    );

    // Find our own stream

    LSLStreamInfo? streamInfo = await findStream(config.streamName);

    if (streamInfo == null) {
      timingManager.recordEvent(
        'stream_resolution_failed',
        description: 'Could not find our own stream',
      );
      throw Exception('Could not find our own stream for loopback testing');
    }

    // Create an inlet from the resolved stream info
    await createInlet(streamInfo);
  }

  @override
  Future<void> runTestImplementation(
    TimingManager timingManager,
    TestConfiguration config,
    Completer<void> completer,
  ) async {
    // Set up a timer to continuously send samples

    sendTimer = Timer.periodic(
      Duration(milliseconds: (1000 / config.sampleRate).round()),
      (timer) {
        // Generate sample with counter as ID
        sampleCounter++;

        if (sampleCounter > config.sampleRate * config.testDurationSeconds) {
          timer.cancel();
          // Give some time for the last samples to be received
          Future.delayed(const Duration(seconds: 2), () {
            if (!completer.isCompleted) completer.complete();
          });
          return;
        }

        // Record when sample is created in our app
        timingManager.recordEvent(
          'sample_created',
          description: 'Sample $sampleCounter created',
          metadata: {'sampleId': sampleCounter},
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
              // Record the time when the sample was sent
              timingManager.recordEvent(
                'sample_sent',
                description: 'Sample $sampleCounter sent to LSL',
                metadata: {'sampleId': sampleCounter},
              );

              // Record what the LSL timestamp would be
              timingManager.recordTimestampedEvent(
                'lsl_timestamp',
                LSL.localClock(),
                description: 'LSL timestamp for sample $sampleCounter',
                metadata: {'sampleId': sampleCounter},
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

            // Record the receive time
            timingManager.recordTimestampedEvent(
              'received_lsl_timestamp',
              sample.timestamp,
              description: 'Sample $sampleId received',
              metadata: {'sampleId': sampleId, 'timestamp': sample.timestamp},
            );

            // Record the processing completion time
            timingManager.recordEvent(
              'sample_processed',
              description: 'Sample $sampleId processed',
              metadata: {'sampleId': sampleId},
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

    // Wait for the test to complete
    await completer.future;
  }

  @override
  Future<void> cleanupTestResources() async {
    // Clean up the inlet and outlet
    await cleanupLSL();
    sendTimer?.cancel();
    sendTimer = null;
    sampleCounter = 0;
  }

  @override
  Map<String, dynamic>? get testSpecificConfig => throw UnimplementedError();
}
