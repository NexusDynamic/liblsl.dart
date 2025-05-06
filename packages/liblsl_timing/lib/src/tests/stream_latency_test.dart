import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/tests/test_registry.dart';

class StreamLatencyTest implements TimingTest {
  @override
  String get name => 'Stream Latency Test';

  @override
  String get description =>
      'Measures latency between sending data through LSL and receiving it';

  @override
  Future<void> runTest(
    TimingManager timingManager,
    TestConfiguration config,
  ) async {
    timingManager.reset();

    // Create the stream info for our outlet
    final streamInfo = await LSL.createStreamInfo(
      streamName: config.streamName,
      streamType: config.streamType,
      channelCount: config.channelCount,
      sampleRate: config.sampleRate,
      channelFormat: config.channelFormat,
      sourceId: config.sourceId,
    );

    // Create the outlet
    final outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: 0,
      maxBuffer: 360,
    );

    // Find our own stream
    final streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 5);

    // Find the right stream
    LSLStreamInfo? resolvedStreamInfo;
    for (final stream in streams) {
      if (stream.streamName == config.streamName) {
        resolvedStreamInfo = stream;
        break;
      }
    }

    if (resolvedStreamInfo == null) {
      throw Exception('Could not find our own stream for loopback testing');
    }

    // Create an inlet from the resolved stream info
    final inlet = await LSL.createInlet<double>(
      streamInfo: resolvedStreamInfo,
      maxBufferSize: 360,
      maxChunkLength: 0,
      recover: true,
    );

    // Complete when test is done
    final completer = Completer<void>();

    // Set up a timer to continuously send samples
    int sampleCounter = 0;
    final sendTimer = Timer.periodic(
      Duration(milliseconds: (1000 / config.sampleRate).round()),
      (timer) {
        // Generate sample with counter as ID
        sampleCounter++;

        if (sampleCounter > config.sampleRate * config.testDurationSeconds) {
          timer.cancel();
          // Give some time for the last samples to be received
          Future.delayed(const Duration(seconds: 2), () {
            completer.complete();
          });
          return;
        }

        // Record when sample is created in our app
        final sampleCreationTime =
            DateTime.now().microsecondsSinceEpoch / 1000000;
        timingManager.recordEvent(
          'sample_created',
          description: 'Sample $sampleCounter created',
          metadata: {'sampleId': sampleCounter},
        );

        // Push the sample with the counter as value
        outlet.pushSample([sampleCounter.toDouble()]).then((_) {
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
          final sample = await inlet.pullSample(timeout: 0.1);

          // Only process if we got a valid sample
          if (sample.isNotEmpty) {
            // Extract the sample ID (counter)
            final sampleId = sample[0].toInt();

            // Record the receive time
            timingManager.recordEvent(
              'sample_received',
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

    // Wait until the test completes
    await completer.future;

    // Clean up
    inlet.destroy();
    outlet.destroy();
    streamInfo.destroy();

    // Calculate metrics
    timingManager.calculateMetrics();
  }

  @override
  void setTestSpecificConfig(Map<String, dynamic> config) {}

  @override
  Map<String, dynamic>? get testSpecificConfig => throw UnimplementedError();
}
