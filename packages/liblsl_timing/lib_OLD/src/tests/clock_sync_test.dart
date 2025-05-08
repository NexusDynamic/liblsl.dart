import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/tests/base/lsl_test.dart';
import 'package:liblsl_timing/src/tests/base/timing_test.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

class ClockSyncTest extends BaseTimingTest with LSLStreamHelper {
  final Map<String, List<double>> timeCorrections = {};
  int syncCounter = 0;

  @override
  String get name => 'Clock Synchronization';

  @override
  String get description =>
      'Tests the clock synchronization between LSL devices';

  @override
  Future<void> setupTestResources(
    TimingManager timingManager,
    TestConfiguration config,
  ) async {
    // Reset the timing manager
    timingManager.reset();
    syncCounter = 0;
    // Create a stream info specifically for clock sync testing
    final streamInfo = await createStreamInfoFromValues(
      streamName: '${config.sourceId}_clocksync',
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: '${config.sourceId}_clocksync',
    );

    // Create the outlet
    await createOutlet(streamInfo);

    // Find all available streams (including our own)
    final streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 10);

    // Collect info about all streams for comparison
    final discoveredStreams = <String, LSLStreamInfo>{};
    for (final stream in streams) {
      discoveredStreams[stream.streamName] = stream;

      timingManager.recordEvent(
        'stream_discovered',
        description: 'Discovered stream: ${stream.streamName}',
        metadata: {
          'streamName': stream.streamName,
          'streamType': stream.streamType.value,
          'sourceId': stream.sourceId,
          'hostname': stream.hostname,
          'uid': stream.uid,
        },
      );
    }

    // Counter for sync markers

    // Maps to store time correction values
    final timeCorrections = <String, List<double>>{};
    await createInlets(streams);
    for (final stream in streams) {
      timeCorrections[streamKey(stream)] = [];
    }
  }

  @override
  Future<void> runTestImplementation(
    TimingManager timingManager,
    TestConfiguration config,
    Completer<void> completer,
  ) async {
    // Function to query time correction for all inlets
    Future<void> queryTimeCorrections() async {
      for (final inlet in inletCache.values) {
        final streamName = streamKey(inlet.streamInfo);
        try {
          final timeCorrection = await inlet.getTimeCorrection(1.0);
          timeCorrections[streamName]?.add(timeCorrection);

          timingManager.recordEvent(
            'time_correction',
            description: 'Time correction for $streamName',
            metadata: {
              'streamName': streamName,
              'timeCorrection': timeCorrection,
              'queryNumber': timeCorrections[streamName]?.length ?? 0,
            },
          );
        } catch (e) {
          print('Error getting time correction for $streamName: $e');
        }
      }
    }

    // Schedule periodic sync markers
    final sendTimer = Timer.periodic(
      Duration(milliseconds: (config.stimulusIntervalMs).round()),
      (timer) async {
        syncCounter++;

        if (syncCounter >
            config.testDurationSeconds * 1000 / config.stimulusIntervalMs) {
          timer.cancel();

          // Final time correction query
          await queryTimeCorrections();

          // Final time correction statistics
          _calculateTimeCorrectionStats(timingManager, timeCorrections);

          // Complete the test
          if (!completer.isCompleted) completer.complete();
          return;
        }

        // Record local time before sending
        final localTime = DateTime.now().microsecondsSinceEpoch / 1000000;

        // Create a marker with local time and counter
        final markerData = 'SYNC_$syncCounter:$localTime';

        timingManager.recordEvent(
          'sync_marker_sent',
          description: 'Sync marker $syncCounter sent',
          metadata: {'syncCounter': syncCounter, 'localTime': localTime},
        );

        // Send the marker
        await outletCache.values.first.pushSample([markerData]);

        // Every few markers, query time correction
        if (syncCounter % 5 == 0) {
          await queryTimeCorrections();
        }
      },
    );

    // Start receiving sync markers from all streams
    for (final inlet in inletCache.values) {
      final streamName = streamKey(inlet.streamInfo);

      // Start a pull loop for this inlet
      _pullSamples(
        timingManager: timingManager,
        inlet: inlet,
        streamName: streamName,
        completer: completer,
      );
    }

    await completer.future;

    // Cancel the send timer if it's still active
    sendTimer.cancel();
  }

  @override
  Future<void> cleanupTestResources() async {
    // Clean up resources
    await cleanupLSL();

    // Reset the sync counter
    syncCounter = 0;
    timeCorrections.clear();
  }

  void _pullSamples({
    required TimingManager timingManager,
    required dynamic inlet,
    required String streamName,
    required Completer<void> completer,
  }) async {
    while (!completer.isCompleted) {
      try {
        // Pull sample with a small timeout
        final sample = await inlet.pullSample(timeout: 0.1);

        // Only process if we got a valid sample
        if (sample.isNotEmpty) {
          // Extract the marker data
          final markerData = sample[0];

          // Record the marker reception
          timingManager.recordEvent(
            'sync_marker_received',
            description: 'Sync marker received from $streamName',
            metadata: {
              'streamName': streamName,
              'markerData': markerData,
              'receiveTime': DateTime.now().microsecondsSinceEpoch / 1000000,
              'sampleTimestamp': sample.timestamp,
            },
          );

          // Parse the marker data to extract counter and send time
          if (markerData is String && markerData.startsWith('SYNC_')) {
            final parts = markerData.split(':');
            if (parts.length == 2) {
              final syncId = parts[0].substring(5); // Remove 'SYNC_'
              final sentTime = double.tryParse(parts[1]) ?? 0.0;

              // Calculate the round-trip time
              final receiveTime =
                  DateTime.now().microsecondsSinceEpoch / 1000000;
              final roundTripTime = receiveTime - sentTime;

              timingManager.recordEvent(
                'marker_round_trip',
                description:
                    'Round trip time for sync marker $syncId from $streamName',
                metadata: {
                  'streamName': streamName,
                  'syncId': syncId,
                  'sentTime': sentTime,
                  'receiveTime': receiveTime,
                  'roundTripTime': roundTripTime,
                },
              );
            }
          }
        }
      } catch (e) {
        // Handle errors gracefully
        print('Error pulling sample from $streamName: $e');
      }

      // Small delay to avoid hammering the CPU
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  void _calculateTimeCorrectionStats(
    TimingManager timingManager,
    Map<String, List<double>> timeCorrections,
  ) {
    for (final streamName in timeCorrections.keys) {
      final values = timeCorrections[streamName] ?? [];

      if (values.isEmpty) continue;

      // Calculate basic statistics
      final mean = values.reduce((a, b) => a + b) / values.length;
      final min = values.reduce(math.min);
      final max = values.reduce(math.max);

      // Calculate standard deviation
      final sumSquaredDiff = values.fold(
        0.0,
        (sum, value) => sum + math.pow(value - mean, 2),
      );
      final stdDev = math.sqrt(sumSquaredDiff / values.length);

      // Calculate stability (difference between last and first correction)
      final stabilityDiff = values.length > 1
          ? values.last - values.first
          : 0.0;

      timingManager.recordEvent(
        'time_correction_stats',
        description: 'Time correction statistics for $streamName',
        metadata: {
          'streamName': streamName,
          'mean': mean,
          'min': min,
          'max': max,
          'stdDev': stdDev,
          'count': values.length,
          'stabilityDiff': stabilityDiff,
          'values': values,
        },
      );
    }
  }

  @override
  void setTestSpecificConfig(Map<String, dynamic> config) {}

  @override
  Map<String, dynamic>? get testSpecificConfig => throw UnimplementedError();
}

class EnhancedClockSyncTest extends ClockSyncTest {
  @override
  String get name => 'Enhanced Clock Synchronization';

  @override
  String get description =>
      'Advanced clock synchronization analysis between LSL devices';

  @override
  Future<void> runTestImplementation(
    TimingManager timingManager,
    TestConfiguration config,
    Completer<void> completer,
  ) async {
    // Create a map to track time offset progression for each device
    final deviceTimeOffsets = <String, List<Map<String, dynamic>>>{};

    // For each connected device, track a series of timestamps
    for (final inlet in inletCache.values) {
      final sKey = streamKey(inlet.streamInfo);
      deviceTimeOffsets[sKey] = [];
    }

    // Send sync markers at regular intervals
    final sendTimer = Timer.periodic(
      Duration(milliseconds: (config.stimulusIntervalMs).round()),
      (timer) async {
        syncCounter++;

        if (syncCounter >
            config.testDurationSeconds * 1000 / config.stimulusIntervalMs) {
          timer.cancel();

          // Analyze time drifts and corrections
          _analyzeTimeSynchronization(timingManager, deviceTimeOffsets);

          // Complete the test
          if (!completer.isCompleted) completer.complete();
          return;
        }

        // Create timestamp references
        final localTime = DateTime.now().microsecondsSinceEpoch / 1000000;
        final lslTime = LSL.localClock();
        final systemOffset = lslTime - localTime;

        // Send sync marker with multiple time references
        final markerData = {
          'syncId': syncCounter,
          'localTime': localTime,
          'lslTime': lslTime,
          'systemOffset': systemOffset,
          'sourceId': config.sourceId,
        };

        // Encode as JSON for transmission
        final markerJson = jsonEncode(markerData);

        timingManager.recordEvent(
          'sync_marker_sent',
          description: 'Enhanced sync marker $syncCounter sent',
          metadata: markerData,
        );

        // Send the marker
        await outletCache.values.first.pushSample([markerJson]);

        // For each connected device, poll time correction
        for (final inlet in inletCache.values) {
          final streamName = streamKey(inlet.streamInfo);
          try {
            final timeCorrection = await inlet.getTimeCorrection(1.0);

            // Get the remote time
            final remoteTime = lslTime - timeCorrection;

            // Record time offset info
            deviceTimeOffsets[streamName]?.add({
              'syncId': syncCounter,
              'localTime': localTime,
              'lslTime': lslTime,
              'timeCorrection': timeCorrection,
              'remoteTime': remoteTime,
              'estimatedOffset': lslTime - remoteTime,
            });

            timingManager.recordEvent(
              'time_sync_measurement',
              description: 'Time sync measurement for $streamName',
              metadata: {
                'syncId': syncCounter,
                'streamName': streamName,
                'timeCorrection': timeCorrection,
                'remoteTime': remoteTime,
                'estimatedOffset': lslTime - remoteTime,
              },
            );
          } catch (e) {
            print('Error getting time correction for $streamName: $e');
          }
        }
      },
    );

    // Start receiving sync markers from all streams
    for (final inlet in inletCache.values) {
      final streamName = streamKey(inlet.streamInfo);
      _pullEnhancedSamples(
        timingManager: timingManager,
        inlet: inlet,
        streamName: streamName,
        deviceTimeOffsets: deviceTimeOffsets,
        completer: completer,
      );
    }

    await completer.future;
    sendTimer.cancel();
  }

  void _pullEnhancedSamples({
    required TimingManager timingManager,
    required LSLIsolatedInlet inlet,
    required String streamName,
    required Map<String, List<Map<String, dynamic>>> deviceTimeOffsets,
    required Completer<void> completer,
  }) async {
    while (!completer.isCompleted) {
      try {
        final sample = await inlet.pullSample(timeout: 0.1);

        if (sample.isNotEmpty) {
          // Extract the marker data
          final markerJson = sample[0];
          if (markerJson.toString().isEmpty) continue;

          if (markerJson is String) {
            try {
              // Parse the JSON data
              final markerData = jsonDecode(markerJson) as Map<String, dynamic>;
              final syncId = markerData['syncId'];
              final senderLocalTime = markerData['localTime'];
              final senderLslTime = markerData['lslTime'];
              final senderOffset = markerData['systemOffset'];
              final sourceId = markerData['sourceId'];

              // Local references
              final receiveLocalTime =
                  DateTime.now().microsecondsSinceEpoch / 1000000;
              final receiveLslTime = LSL.localClock();
              final localOffset = receiveLslTime - receiveLocalTime;

              // Calculate time differences
              final localTimeDiff = receiveLocalTime - senderLocalTime;
              final lslTimeDiff = receiveLslTime - senderLslTime;
              final offsetDiff = localOffset - senderOffset;

              // Record comprehensive sync data
              timingManager.recordEvent(
                'enhanced_sync_received',
                description: 'Enhanced sync marker received from $sourceId',
                metadata: {
                  'syncId': syncId,
                  'sourceId': sourceId,
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

              // Add to device offset tracking
              final deviceKey = '$streamName:$sourceId';
              if (!deviceTimeOffsets.containsKey(deviceKey)) {
                deviceTimeOffsets[deviceKey] = [];
              }

              deviceTimeOffsets[deviceKey]?.add({
                'syncId': syncId,
                'localTimeDiff': localTimeDiff,
                'lslTimeDiff': lslTimeDiff,
                'offsetDiff': offsetDiff,
                'timestamp': receiveLocalTime,
              });
            } catch (e) {
              print('Error parsing marker JSON: $e');
            }
          }
        }
      } catch (e) {
        print('Error pulling sample from $streamName: $e');
      }

      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  void _analyzeTimeSynchronization(
    TimingManager timingManager,
    Map<String, List<Map<String, dynamic>>> deviceTimeOffsets,
  ) {
    for (final deviceKey in deviceTimeOffsets.keys) {
      final offsets = deviceTimeOffsets[deviceKey];
      if (offsets == null || offsets.isEmpty) continue;

      // Calculate drift over time
      double? initialLslDiff;
      double? finalLslDiff;
      double? initialLocalDiff;
      double? finalLocalDiff;
      double? initialTime;
      double? finalTime;

      if (offsets.length > 1) {
        initialLslDiff = offsets.first['lslTimeDiff'];
        finalLslDiff = offsets.last['lslTimeDiff'];
        initialLocalDiff = offsets.first['localTimeDiff'];
        finalLocalDiff = offsets.last['localTimeDiff'];
        initialTime = offsets.first['timestamp'];
        finalTime = offsets.last['timestamp'];
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

      // Calculate statistics
      final lslTimeDiffs = offsets
          .map(
            (o) => o['lslTimeDiff'] != null
                ? o['lslTimeDiff'] as double
                : double.nan,
          )
          .toList();
      final localTimeDiffs = offsets
          .map(
            (o) => o['localTimeDiff'] != null
                ? o['localTimeDiff'] as double
                : double.nan,
          )
          .toList();
      final offsetDiffs = offsets
          .map(
            (o) => o['offsetDiff'] != null
                ? o['offsetDiff'] as double
                : double.nan,
          )
          .toList();

      final lslDiffStats = _calculateStats(lslTimeDiffs);
      final localDiffStats = _calculateStats(localTimeDiffs);
      final offsetDiffStats = _calculateStats(offsetDiffs);

      // Record the analysis
      timingManager.recordEvent(
        'clock_sync_analysis',
        description: 'Clock synchronization analysis for $deviceKey',
        metadata: {
          'deviceKey': deviceKey,
          'measurements': offsets.length,
          'lslTimeDiffStats': lslDiffStats,
          'localTimeDiffStats': localDiffStats,
          'offsetDiffStats': offsetDiffStats,
          'lslDriftRate': lslDriftRate,
          'localDriftRate': localDriftRate,
          'timeSpan': finalTime != null && initialTime != null
              ? finalTime - initialTime
              : null,
        },
      );
    }
  }

  Map<String, double> _calculateStats(List<double> values) {
    if (values.isEmpty) return {};

    final mean = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);

    // Calculate standard deviation
    final sumSquaredDiff = values.fold(
      0.0,
      (sum, value) => sum + math.pow(value - mean, 2),
    );
    final stdDev = math.sqrt(sumSquaredDiff / values.length);

    return {'mean': mean, 'min': min, 'max': max, 'stdDev': stdDev};
  }
}
