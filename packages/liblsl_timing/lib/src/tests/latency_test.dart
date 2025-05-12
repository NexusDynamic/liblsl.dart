// lib/src/tests/latency_test.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/config/constants.dart';
import 'base_test.dart';

class LatencyTest extends BaseTest {
  // LSL resources
  LSLStreamInfo? _streamInfo;
  LSLIsolatedOutlet? _outlet;
  LSLIsolatedInlet? _inlet;

  // Test variables
  int _sampleCounter = 0;
  Timer? _sendTimer;
  bool _isRunning = false;

  LatencyTest(super.config, super.timingManager);

  @override
  String get name => 'Latency Test';

  @override
  String get description => 'Measures communication time and LSL packet timing';

  @override
  Future<void> setup() async {
    _sampleCounter = 0;
    _isRunning = false;

    // Create stream info
    _streamInfo = await LSL.createStreamInfo(
      streamName: config.streamName,
      streamType: config.streamType,
      channelCount: config.channelCount,
      sampleRate: config.sampleRate,
      channelFormat: config.channelFormat,
      sourceId: config.deviceId,
    );

    // Create outlet if this device is a producer
    if (config.isProducer) {
      _outlet = await LSL.createOutlet(
        streamInfo: _streamInfo!,
        chunkSize: 1,
        maxBuffer: 360,
      );
    }

    // Find available streams
    await Future.delayed(const Duration(milliseconds: 500));
    final streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 10);

    // Create inlet if this device is a consumer
    if (config.isConsumer && streams.isNotEmpty) {
      // Try to find a stream with our name but not our device ID
      final otherStream = streams.firstWhere(
        (s) =>
            s.streamName == config.streamName &&
            s.sourceId != config.deviceId &&
            s.channelFormat == config.channelFormat,
        orElse: () => streams.first,
      );

      _inlet = await LSL.createInlet(
        streamInfo: otherStream,
        maxBufferSize: 360,
        maxChunkLength: 1,
        recover: true,
      );
    }

    timingManager.recordEvent(
      EventType.testStarted,
      description: 'Latency test setup completed',
      metadata: {
        'isProducer': config.isProducer,
        'isConsumer': config.isConsumer,
        'streamName': config.streamName,
      },
    );
  }

  @override
  Future<void> run() async {
    _isRunning = true;

    // Start sending samples if this device is a producer
    if (config.isProducer && _outlet != null) {
      _startSending();
    }

    // Start receiving samples if this device is a consumer
    if (config.isConsumer && _inlet != null) {
      _startReceiving();
    }

    // Create a completer that completes when the test is stopped
    final completer = Completer<void>();

    // Wait for test to complete
    await completer.future;
  }

  void _startSending() {
    final sampleIntervalMs = (1000 / config.sampleRate).round();

    _sendTimer = Timer.periodic(
      Duration(milliseconds: sampleIntervalMs),
      _sendSample,
    );
  }

  void _sendSample(Timer timer) {
    if (!_isRunning) {
      timer.cancel();
      return;
    }

    _sampleCounter++;

    // Create a unique sample ID
    final sampleId = '${config.deviceId}_$_sampleCounter';

    // Record when the sample is created
    timingManager.recordEvent(
      EventType.sampleCreated,
      description: 'Sample $sampleId created',
      metadata: {'sampleId': sampleId, 'counter': _sampleCounter},
    );

    // Create sample data (include counter as the first channel)
    final sampleData = List<double>.generate(
      config.channelCount,
      (i) => i == 0 ? _sampleCounter.toDouble() : math.Random().nextDouble(),
    );

    // Push sample to outlet
    _outlet?.pushSample(sampleData).then((_) {
      // Record LSL timestamp
      final lslTime = LSL.localClock();

      timingManager.recordTimestampedEvent(
        EventType.sampleSent,
        lslTime,
        description: 'Sample $sampleId sent',
        metadata: {
          'sampleId': sampleId,
          'counter': _sampleCounter,
          'lslTime': lslTime,
        },
      );
    });
  }

  void _startReceiving() async {
    while (_isRunning) {
      try {
        final sample = await _inlet!.pullSample(timeout: 0.1);

        if (sample.isNotEmpty) {
          // Extract the counter value (first channel)
          final counter = sample[0].toInt();
          final sampleId = '${_inlet!.streamInfo.sourceId}_$counter';

          // Record the receive time
          timingManager.recordEvent(
            EventType.sampleReceived,
            description: 'Sample $sampleId received',
            metadata: {
              'sampleId': sampleId,
              'counter': counter,
              'lslTimestamp': sample.timestamp,
              'data': sample.data,
            },
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error receiving sample: $e');
        }
      }

      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  @override
  Future<void> cleanup() async {
    _isRunning = false;

    _sendTimer?.cancel();
    _sendTimer = null;

    _inlet?.destroy();
    _outlet?.destroy();
    _streamInfo?.destroy();

    _inlet = null;
    _outlet = null;
    _streamInfo = null;
  }
}
