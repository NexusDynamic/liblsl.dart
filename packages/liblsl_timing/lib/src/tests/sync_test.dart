// lib/src/tests/sync_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import '../config/constants.dart';
import 'base_test.dart';

class SynchronizationTest extends BaseTest {
  // LSL resources
  LSLStreamInfo? _syncStreamInfo;
  LSLIsolatedOutlet? _syncOutlet;
  List<LSLIsolatedInlet> _syncInlets = [];

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
  String get description =>
      'Analyzes clock differences and drift between devices';

  @override
  Future<void> setup() async {
    _syncCounter = 0;
    _isRunning = false;
    _deviceTimeOffsets.clear();

    // Create a sync stream
    _syncStreamInfo = await LSL.createStreamInfo(
      streamName: '${config.deviceName}_Sync',
      streamType: LSLContentType.custom('Sync'),
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: config.deviceId,
    );

    // Create an outlet for sync markers
    _syncOutlet = await LSL.createOutlet(
      streamInfo: _syncStreamInfo!,
      chunkSize: 1,
      maxBuffer: 360,
    );

    // Find all available sync streams
    await Future.delayed(const Duration(milliseconds: 500));
    final streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 20);

    final syncStreams =
        streams.where((s) => s.streamType.value == 'Sync').toList();

    // Create inlets for each sync stream
    _syncInlets = [];
    for (final stream in syncStreams) {
      if (stream.sourceId != config.deviceId) {
        final inlet = await LSL.createInlet(
          streamInfo: stream,
          maxBufferSize: 360,
          maxChunkLength: 1,
          recover: true,
        );
        _syncInlets.add(inlet);

        // Initialize time offset tracking for this device
        _deviceTimeOffsets[stream.sourceId] = [];
      }
    }

    timingManager.recordEvent(
      EventType.testStarted,
      description: 'Synchronization test setup completed',
      metadata: {
        'syncStreams': syncStreams.length,
        'syncInlets': _syncInlets.length,
      },
    );
  }

  @override
  Future<void> run() async {
    _isRunning = true;

    // Start sending sync markers
    _startSendingMarkers();

    // Start receiving sync markers
    for (final inlet in _syncInlets) {
      _startReceivingMarkers(inlet);
    }

    // Create a completer that completes when the test is stopped
    final completer = Completer<void>();

    // Wait for test to complete
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
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error receiving marker: $e');
        }
      }

      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  @override
  Future<void> cleanup() async {
    _isRunning = false;

    _syncTimer?.cancel();
    _syncTimer = null;

    // Analyze time synchronization data
    _analyzeTimeSynchronization();

    // Clean up LSL resources
    for (final inlet in _syncInlets) {
      inlet.destroy();
    }
    _syncInlets = [];

    _syncOutlet?.destroy();
    _syncStreamInfo?.destroy();

    _syncOutlet = null;
    _syncStreamInfo = null;
  }

  void _analyzeTimeSynchronization() {
    for (final deviceKey in _deviceTimeOffsets.keys) {
      final offsets = _deviceTimeOffsets[deviceKey];
      if (offsets == null || offsets.isEmpty) continue;

      // Calculate drift over time
      double? initialLslDiff;
      double? finalLslDiff;
      double? initialLocalDiff;
      double? finalLocalDiff;
      double? initialTime;
      double? finalTime;

      if (offsets.length > 1) {
        initialLslDiff = offsets.first['lslTimeDiff'] as double?;
        finalLslDiff = offsets.last['lslTimeDiff'] as double?;
        initialLocalDiff = offsets.first['localTimeDiff'] as double?;
        finalLocalDiff = offsets.last['localTimeDiff'] as double?;
        initialTime = offsets.first['timestamp'] as double?;
        finalTime = offsets.last['timestamp'] as double?;
      }

      // Calculate drift rates if we have time data
      double? lslDriftRate;
      double? localDriftRate;

      if (initialTime != null &&
          finalTime != null &&
          initialLslDiff != null &&
          finalLslDiff != null &&
          initialLocalDiff != null &&
          finalLocalDiff != null) {
        final timeSpan = finalTime - initialTime;
        if (timeSpan > 0) {
          lslDriftRate = (finalLslDiff - initialLslDiff) / timeSpan;
          localDriftRate = (finalLocalDiff - initialLocalDiff) / timeSpan;
        }
      }

      // Calculate statistics for LSL time differences
      final lslTimeDiffs =
          offsets.map((o) => o['lslTimeDiff'] as double).toList();

      final localTimeDiffs =
          offsets.map((o) => o['localTimeDiff'] as double).toList();

      final lslDiffStats = _calculateStats(lslTimeDiffs);
      final localDiffStats = _calculateStats(localTimeDiffs);

      // Record the analysis
      timingManager.recordEvent(
        EventType.testCompleted,
        description: 'Clock synchronization analysis for $deviceKey',
        metadata: {
          'deviceKey': deviceKey,
          'measurements': offsets.length,
          'lslTimeDiffStats': lslDiffStats,
          'localTimeDiffStats': localDiffStats,
          'lslDriftRate': lslDriftRate,
          'localDriftRate': localDriftRate,
          'timeSpan':
              finalTime != null && initialTime != null
                  ? finalTime - initialTime
                  : null,
        },
      );
    }
  }

  Map<String, double> _calculateStats(List<double> values) {
    if (values.isEmpty) return {};

    // Calculate mean
    final mean = values.reduce((a, b) => a + b) / values.length;

    // Find min and max
    double? min;
    double? max;

    for (final value in values) {
      min = (min != null) ? (value < min ? value : min) : value;
      max = (max != null) ? (value > max ? value : max) : value;
    }

    // Calculate standard deviation
    double sumSquaredDiffs = 0;
    for (final value in values) {
      sumSquaredDiffs += (value - mean) * (value - mean);
    }

    final stdDev =
        (values.length > 1)
            ? (sumSquaredDiffs / (values.length - 1)).sqrt()
            : 0.0;

    return {'mean': mean, 'min': min ?? 0, 'max': max ?? 0, 'stdDev': stdDev};
  }
}

extension on double {
  double sqrt() => this <= 0 ? 0 : math.sqrt(this);
}
