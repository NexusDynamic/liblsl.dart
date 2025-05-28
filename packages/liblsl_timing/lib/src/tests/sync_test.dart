// lib/src/tests/sync_test.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/lsl/comms_isolate.dart';
import '../config/constants.dart';
import 'base_test.dart';

class SynchronizationTest extends BaseTest {
  // LSL resources
  LSLStreamInfo? _syncStreamInfo;
  InletManager? _inletManager;
  OutletManager? _outletManager;
  final String _srcPrefix = 'Sync_';

  // Track time offsets for each device
  final Map<String, List<Map<String, dynamic>>> _deviceTimeOffsets = {};

  SynchronizationTest(super.config, super.timingManager);

  @override
  String get name => 'Clock Synchronization Test';

  @override
  TestType get testType => TestType.synchronization;

  @override
  String get description =>
      'Analyzes clock differences and drift between devices';

  @override
  Future<void> setup() async {
    _deviceTimeOffsets.clear();

    // Create a sync stream
    _syncStreamInfo = await LSL.createStreamInfo(
      streamName: config.streamName,
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: 2,
      channelFormat: LSLChannelFormat.float32,
      sourceId: '$_srcPrefix${config.deviceId}',
    );
    if (config.isProducer) {
      _outletManager = OutletManager();
      await _outletManager!.prepareOutletProducer(
        _syncStreamInfo!,
        2,

        '$_srcPrefix${config.deviceId}_',

        onSampleSent: (List<IsolateSampleMessage> samples) async {
          // Record the send time
          for (final sample in samples) {
            timingManager.recordTimestampedEvent(
              EventType.sampleSent,
              sample.dartNow * 1e-6, // Convert to seconds
              lslClock: sample.lslNow,
              description: 'Sync ${sample.sampleId} sent',
              metadata: {
                'sampleId': sample.sampleId,
                'counter': sample.counter,
                'lslTimestamp': sample.timestamp,
                'lslSent': sample.lslNow,
                'dartTimestamp': sample.dartNow,
                'sourceId': sample.sourceId,
                'timeCorrection': sample.lslTimeCorrection,
              },
            );
          }
        },
      );
    }

    // Find all available sync streams
    await Future.delayed(const Duration(milliseconds: 1000));

    final streams = await LSL.resolveStreams(waitTime: 5.0, maxStreams: 20);
    if (config.isConsumer && streams.isNotEmpty) {
      final syncStreams = streams
          .where(
            (s) =>
                s.streamType == LSLContentType.markers &&
                // our own stream
                // s.sourceId != '$_srcPrefix${config.deviceId}' &&
                // sync streams
                s.sourceId.startsWith(_srcPrefix),
          )
          .toList();

      // Create an inlet manager if this device is a consumer
      _inletManager = InletManager();
      await _inletManager!.prepareInletConsumers(
        syncStreams,
        onSampleReceived: (List<IsolateSampleMessage> samples) async {
          // Handle received sync markers
          for (final sample in samples) {
            timingManager.recordTimestampedEvent(
              EventType.sampleReceived,
              sample.dartNow * 1e-6, // Convert to seconds
              lslClock: sample.timestamp,
              description: 'Sync marker received from ${sample.sourceId}',
              metadata: {
                'sampleId': sample.sampleId,
                'counter': sample.counter,
                'lslTimestamp': sample.timestamp,
                'lslReceived': sample.lslNow,
                'dartTimestamp': sample.dartNow,
                'sourceId': sample.sourceId,
                'timeCorrection': sample.lslTimeCorrection,
              },
            );
          }
        },
        timeCorrectEveryN: 2,
      );
    }

    // Initialize time offset tracking for this device
    // _deviceTimeOffsets[stream.sourceId] = [];

    timingManager.recordEvent(
      EventType.testStarted,
      description: 'Synchronization test setup completed',
      metadata: config.toMap(),
    );
  }

  @override
  Future<void> run(Completer<void> completer) async {
    // Start sending samples if this device is a producer
    if (config.isProducer && _outletManager != null) {
      _outletManager!.startOutletProducer();
    } else {
      if (kDebugMode) {
        print('Not a producer, skipping sample sending');
      }
    }

    // Start receiving samples if this device is a consumer
    if (config.isConsumer && _inletManager != null) {
      _inletManager!.startInletConsumers();
    } else {
      if (kDebugMode) {
        print('Not a consumer, skipping sample receiving');
      }
    }
    await completer.future;
    // stop the test
    if (kDebugMode) {
      print('Stopping Sync Test');
    }

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
    _outletManager = null;
    _inletManager = null;

    _syncStreamInfo?.destroy();
    _syncStreamInfo = null;
  }
}
