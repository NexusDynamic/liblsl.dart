// lib/src/tests/sync_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/lsl/comms_isolate.dart';
import '../config/constants.dart';
import 'base_test.dart';

class SynchronizationTest extends BaseTest {
  // LSL resources
  LSLStreamInfo? _syncStreamInfo;
  LSLIsolatedOutlet? _syncOutlet;
  List<LSLIsolatedInlet> _syncInlets = [];
  InletManager? _inletManager;
  OutletManager? _outletManager;
  final String _srcPrefix = 'Sync_';

  // Test variables
  int _syncCounter = 0;
  Timer? _syncTimer;
  bool _isRunning = false;

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
    _syncCounter = 0;
    _isRunning = false;
    _deviceTimeOffsets.clear();

    // Create a sync stream
    _syncStreamInfo = await LSL.createStreamInfo(
      streamName: config.streamName,
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: 2,
      channelFormat: LSLChannelFormat.string,
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

    // // Create an outlet for sync markers
    // _syncOutlet = await LSL.createOutlet(
    //   streamInfo: _syncStreamInfo!,
    //   chunkSize: 1,
    //   maxBuffer: 360,
    // );

    // Find all available sync streams
    await Future.delayed(const Duration(milliseconds: 1000));

    final streams = await LSL.resolveStreams(waitTime: 5.0, maxStreams: 20);
    if (config.isConsumer && streams.isNotEmpty) {
      final syncStreams = streams
          .where(
            (s) =>
                s.streamType == LSLContentType.markers &&
                // our own stream
                s.sourceId != '$_srcPrefix${config.deviceId}' &&
                // sync streams
                s.streamName.startsWith(_srcPrefix),
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
              sample.timestamp * 1e-6, // Convert to seconds
              lslClock: sample.timestamp,
              description: 'Sync marker received from ${sample.sourceId}',
              metadata: {
                'sampleId': sample.sampleId,
                'counter': sample.counter,
                'lslTimestamp': sample.timestamp,
                'lslReceived': sample.lslNow,
                'dartTimestamp': sample.dartNow,
                'sourceId': sample.sourceId,
              },
            );
          }
        },
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
    _isRunning = true;

    // Start sending samples if this device is a producer
    if (config.isProducer && _outletManager != null) {
      _outletManager!.startOutletProducer();
    }

    // Start receiving samples if this device is a consumer
    if (config.isConsumer && _inletManager != null) {
      _inletManager!.startInletConsumers();
    }

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

    await completer.future;
  }

  void _startSendingMarkers() {
    // Send markers every 500ms
    _syncTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      _sendSyncMarker,
    );
  }

  void _sendSyncMarker(Timer timer) {
    if (!_isRunning) {
      timer.cancel();
      return;
    }

    _syncCounter++;

    // Create timestamp references
    final localTime = DateTime.now().microsecondsSinceEpoch / 1000000;
    final lslTime = LSL.localClock();
    final systemOffset = lslTime - localTime;

    // Create marker data with multiple time references
    final markerData = {
      'syncId': _syncCounter,
      'deviceId': config.deviceId,
      'deviceName': config.deviceName,
      'localTime': localTime,
      'lslTime': lslTime,
      'systemOffset': systemOffset,
    };

    // Encode as JSON
    final markerJson = jsonEncode(markerData);

    // Record marker sent event
    timingManager.recordEvent(
      EventType.markerSent,
      description: 'Sync marker $_syncCounter sent',
      metadata: markerData,
    );

    // Send the marker
    _syncOutlet?.pushSample([markerJson]);

    // For each device we're tracking, measure the time correction
    for (final inlet in _syncInlets) {
      _measureTimeCorrection(inlet);
    }
  }

  void _measureTimeCorrection(LSLIsolatedInlet inlet) async {
    try {
      final timeCorrection = await inlet.getTimeCorrection(1.0);
      final deviceId = inlet.streamInfo.sourceId;

      // Get the remote time
      final lslTime = LSL.localClock();
      final remoteTime = lslTime - timeCorrection;

      // Record time offset info
      final offsetInfo = {
        'syncId': _syncCounter,
        'localTime': DateTime.now().microsecondsSinceEpoch / 1000000,
        'lslTime': lslTime,
        'timeCorrection': timeCorrection,
        'remoteTime': remoteTime,
        'estimatedOffset': lslTime - remoteTime,
      };

      _deviceTimeOffsets[deviceId]?.add(offsetInfo);

      timingManager.recordEvent(
        EventType.clockCorrection,
        description: 'Time correction for $deviceId',
        metadata: {
          'deviceId': deviceId,
          'timeCorrection': timeCorrection,
          'remoteTime': remoteTime,
          'estimatedOffset': lslTime - remoteTime,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error measuring time correction: $e');
        // backtrace
        print('Stack trace: ${StackTrace.current}');
      }
    }
  }

  void _startReceivingMarkers(LSLIsolatedInlet inlet) async {
    final deviceId = inlet.streamInfo.sourceId;

    while (_isRunning) {
      try {
        final sample = await inlet.pullSample(timeout: 0.1);

        if (sample.isNotEmpty) {
          final markerJson = sample[0];

          try {
            // Parse the JSON data
            final markerData = jsonDecode(markerJson) as Map<String, dynamic>;
            final syncId = markerData['syncId'] as int;
            final senderDeviceId = markerData['deviceId'] as String;
            final senderLocalTime = markerData['localTime'] as double;
            final senderLslTime = markerData['lslTime'] as double;
            final senderOffset = markerData['systemOffset'] as double;

            // Local references
            final receiveLocalTime =
                DateTime.now().microsecondsSinceEpoch / 1000000;
            final receiveLslTime = LSL.localClock();
            final sendLslTimestamp = sample.timestamp;
            final localOffset = receiveLslTime - receiveLocalTime;

            // Calculate time differences
            final localTimeDiff = receiveLocalTime - senderLocalTime;
            final lslTimeDiff = receiveLslTime - senderLslTime;
            final offsetDiff = localOffset - senderOffset;

            // Record marker received event
            timingManager.recordEvent(
              EventType.markerReceived,
              description: 'Sync marker $syncId from $senderDeviceId received',
              metadata: {
                'syncId': syncId,
                'senderDeviceId': senderDeviceId,
                'senderLocalTime': senderLocalTime,
                'senderLslTime': senderLslTime,
                'senderOffset': senderOffset,
                'receiveLocalTime': receiveLocalTime,
                'receiveLslTime': receiveLslTime,
                'localOffset': localOffset,
                'localTimeDiff': localTimeDiff,
                'lslTimeDiff': lslTimeDiff,
                'offsetDiff': offsetDiff,
                'sampleTimestamp': sample.timestamp,
                'sendLslTimestamp': sendLslTimestamp,
              },
            );

            // Add to time offset tracking
            final deviceKey = '$deviceId:$senderDeviceId';
            if (!_deviceTimeOffsets.containsKey(deviceKey)) {
              _deviceTimeOffsets[deviceKey] = [];
            }

            _deviceTimeOffsets[deviceKey]?.add({
              'syncId': syncId,
              'localTimeDiff': localTimeDiff,
              'lslTimeDiff': lslTimeDiff,
              'offsetDiff': offsetDiff,
              'timestamp': receiveLocalTime,
            });
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing marker data: $e');
              // backtrace
              print('Stack trace: ${StackTrace.current}');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error receiving marker: $e');
          // backtrace
          print('Stack trace: ${StackTrace.current}');
        }
      }

      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  @override
  Future<void> cleanup() async {
    _isRunning = false;

    _outletManager = null;
    _inletManager = null;

    _syncStreamInfo?.destroy();
    _syncStreamInfo = null;
  }
}
