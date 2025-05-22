// lib/src/tests/latency_test.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/config/constants.dart';
import 'package:liblsl_timing/src/lsl/comms_isolate.dart';
import 'base_test.dart';

class LatencyTest extends BaseTest {
  // LSL resources
  LSLStreamInfo? _streamInfo;
  InletManager? _inletManager;
  OutletManager? _outletManager;

  final String _srcPrefix = 'LatencyTest_';

  // Test variables
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  LatencyTest(super.config, super.timingManager);

  @override
  String get name => 'Latency Test';

  @override
  TestType get testType => TestType.latency;

  @override
  String get description => 'Measures communication time and LSL packet timing';

  @override
  Future<void> setup() async {
    _isRunning = false;
    if (kDebugMode) {
      print('Setting up Latency Test for device: $config');
    }
    // Create stream info
    _streamInfo = await LSL.createStreamInfo(
      streamName: config.streamName,
      streamType: config.streamType,
      channelCount: config.channelCount,
      sampleRate: config.sampleRate,
      channelFormat: config.channelFormat,
      sourceId: '$_srcPrefix${config.deviceId}',
    );

    // Create outlet if this device is a producer
    if (config.isProducer) {
      _outletManager = OutletManager();
      await _outletManager!.prepareOutletProducer(
        _streamInfo!,
        config.sampleRate,
        '$_srcPrefix${config.deviceId}_',
        onSampleSent: (IsolateSampleMessage sample) async {
          // Record the send time
          timingManager.recordEvent(
            EventType.sampleSent,
            description: 'Sample ${sample.sampleId} sent',
            metadata: {
              'sampleId': sample.sampleId,
              'counter': sample.counter,
              'lslTimestamp': sample.timestamp,
              'lslSent': sample.lslNow,
              'dartTimestamp': sample.dartNow,
            },
          );
        },
      );
    }

    // Find available streams
    await Future.delayed(const Duration(milliseconds: 500));
    final streams = await LSL.resolveStreams(
      waitTime: config.streamMaxWaitTimeSeconds,
      maxStreams: config.streamMaxStreams,
    );

    // Create inlet if this device is a consumer
    if (config.isConsumer && streams.isNotEmpty) {
      // Find all matching streams
      final otherStreams = streams.where(
        (s) =>
            s.streamName == config.streamName &&
            s.sourceId.startsWith(_srcPrefix) &&
            s.channelFormat == config.channelFormat,
      );

      if (otherStreams.isNotEmpty) {
        _inletManager = InletManager();
        await _inletManager!.prepareInletConsumers(
          otherStreams,
          onSampleReceived: (IsolateSampleMessage sample) async {
            timingManager.recordEvent(
              EventType.sampleReceived,
              description: 'Sample ${sample.sampleId} received',
              metadata: {
                'sampleId': sample.sampleId,
                'counter': sample.counter,
                'lslTimestamp': sample.timestamp,
                'lslRecieved': sample.lslNow,
                'dartTimestamp': sample.dartNow,
                // 'data': sample.data,
              },
            );
          },
        );
      } else {
        if (kDebugMode) {
          print('No matching streams found.');
        }
      }
    }

    timingManager.recordEvent(
      EventType.testStarted,
      description: 'Latency test setup completed',
      metadata: {'config': config.toMap()},
      testType: testType.toString(),
    );
  }

  @override
  Future<void> run(Completer<void> completer) async {
    _isRunning = true;

    // Start sending samples if this device is a producer
    if (config.isProducer && _outletManager != null) {
      _outletManager!.startOutletProducer();
    }

    // Start receiving samples if this device is a consumer
    if (config.isConsumer && _inletManager != null) {
      _inletManager!.startInletConsumers();
    }

    // wait for timeout, this should be refactored
    await completer.future;
    // stop the test
    if (kDebugMode) {
      print('Stopping Latency Test');
    }
    _isRunning = false;
    // stop sending samples if this device is a producer
    if (config.isProducer && _outletManager != null) {
      await _outletManager!.stopOutletProducer();
    }
    // stop receiving samples if this device is a consumer
    if (config.isConsumer && _inletManager != null) {
      await _inletManager!.stopInletConsumers();
    }
  }

  @override
  Future<void> cleanup() async {
    _isRunning = false;

    _outletManager = null;
    _inletManager = null;
    // destroy the stream info
    _streamInfo?.destroy();

    _streamInfo = null;
  }
}
