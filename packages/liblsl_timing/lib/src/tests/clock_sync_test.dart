import 'dart:async';
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
