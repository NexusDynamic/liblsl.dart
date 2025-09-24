import 'dart:math';
import 'package:dartframe/dartframe.dart';
import 'package:flutter/foundation.dart';

import 'enhanced_timing_analysis_service.dart';

/// Ultra-fast enhanced timing analysis - single-pass processing for massive datasets
class UltraFastEnhancedTimingAnalysisService {
  static const String eventTypeSampleSent = 'EventType.sampleSent';
  static const String eventTypeSampleReceived = 'EventType.sampleReceived';

  /// Calculate inter-sample intervals using single-pass processing - MUCH faster
  List<InterSampleIntervalResult> calculateInterSampleIntervals(
    DataFrame data,
  ) {
    if (kDebugMode) {
      print('🔄 Starting ULTRA-FAST inter-sample interval calculation...');
      print('📊 Data size: ${data['reportingDeviceId'].data.length} rows');
    }

    final deviceTimestamps = <String, List<double>>{};

    // Cache data arrays once - CRITICAL optimization!
    if (kDebugMode) {
      print('📦 Caching data arrays...');
    }
    final eventTypeData = data['event_type'].data;
    final deviceIdData = data['reportingDeviceId'].data;
    final timestampData = data['lsl_clock'].data;
    final rowCount = eventTypeData.length;

    if (kDebugMode) {
      print('⚡ Single-pass extraction of sent events...');
    }

    // Single pass through data - much faster than multiple DataFrame operations
    for (int i = 0; i < rowCount; i++) {
      // Progress for very large datasets
      if (kDebugMode && i % 20000 == 0 && i > 0) {
        // ignore: avoid_print
        print('  ⏳ Processed $i of $rowCount rows...');
      }

      final eventType = eventTypeData[i] as String?;
      if (eventType != eventTypeSampleSent) continue;

      final deviceId = deviceIdData[i] as String?;
      final timestamp = timestampData[i] as double?;

      if (deviceId != null && timestamp != null) {
        deviceTimestamps.putIfAbsent(deviceId, () => <double>[]).add(timestamp);
      }
    }

    if (kDebugMode) {
      print('📱 Found ${deviceTimestamps.length} devices with sent events');
    }

    final results = <InterSampleIntervalResult>[];

    // Calculate intervals for each device
    for (final entry in deviceTimestamps.entries) {
      final deviceId = entry.key;
      final timestamps = entry.value;

      if (timestamps.length < 2) continue;

      // Sort timestamps to ensure proper order
      timestamps.sort();

      // Calculate intervals
      final intervals = <double>[];
      for (int i = 1; i < timestamps.length; i++) {
        intervals.add((timestamps[i] - timestamps[i - 1]) * 1000);
      }

      if (intervals.isNotEmpty) {
        results.add(_calculateIntervalStats(deviceId, intervals));
        if (kDebugMode) {
          print('✅ Device $deviceId: ${intervals.length} intervals calculated');
        }
      }
    }

    if (kDebugMode) {
      print(
        '🎉 Inter-sample intervals complete: ${results.length} device results',
      );
    }

    return results;
  }

  /// Ultra-fast latency calculation - single pass through data
  List<LatencyResult> calculateLatencies(DataFrame data) {
    if (kDebugMode) {
      print('🚀 Starting ultra-fast enhanced latency analysis...');
      print('📊 Data size: ${data['event_type'].data.length} rows');
    }

    // Check for time corrections
    final startTime = DateTime.now();
    final hasTimeCorrections = _hasTimeCorrectionData(data);

    if (kDebugMode) {
      print(
        '⚡ Time correction check: ${hasTimeCorrections ? 'ENABLED' : 'DISABLED'} (${DateTime.now().difference(startTime).inMilliseconds}ms)',
      );
    }

    // Single-pass data extraction - MUCH faster
    final extractStart = DateTime.now();
    final eventData = _extractAllEventsInSinglePass(data, hasTimeCorrections);

    if (kDebugMode) {
      print(
        '📦 Event extraction complete: ${eventData.sent.length} sent, ${eventData.received.length} received (${DateTime.now().difference(extractStart).inMilliseconds}ms)',
      );
    }

    // Group data efficiently
    final groupStart = DateTime.now();
    final groupedData = _groupEventDataEfficiently(eventData);

    if (kDebugMode) {
      print(
        '🗂️ Data grouping complete: ${groupedData.keys.length} sources (${DateTime.now().difference(groupStart).inMilliseconds}ms)',
      );

      // Show source breakdown
      for (final entry in groupedData.entries) {
        final sourceId = entry.key;
        final group = entry.value;
        print(
          '  📡 Source $sourceId: ${group.sentEvents.length} sent, ${group.receivedEvents.length} receiving devices',
        );
      }
    }

    // Calculate latencies efficiently
    final calcStart = DateTime.now();
    final results = _calculateLatenciesFromGroupedData(
      groupedData,
      hasTimeCorrections,
    );

    if (kDebugMode) {
      print(
        '🎯 Latency calculation complete: ${results.length} device pairs (${DateTime.now().difference(calcStart).inMilliseconds}ms)',
      );
      print(
        '🏁 Total enhanced analysis time: ${DateTime.now().difference(startTime).inMilliseconds}ms',
      );
    }

    return results;
  }

  /// Check if we have meaningful time correction data
  bool _hasTimeCorrectionData(DataFrame data) {
    if (!data.columns.contains('lslTimeCorrection')) return false;

    // Quick sample check - only check first 100 rows for speed
    final corrections = data['lslTimeCorrection'].data;
    final sampleSize = min<int>(100, corrections.length);

    for (int i = 0; i < sampleSize; i++) {
      final correction = corrections[i];
      if (correction != null &&
          correction is double &&
          !correction.isNaN &&
          correction != 0.0) {
        return true;
      }
    }
    return false;
  }

  /// Single-pass extraction of all events - MUCH faster than multiple passes
  _EventData _extractAllEventsInSinglePass(
    DataFrame data,
    bool includeTimeCorrections,
  ) {
    final sentEvents = <_Event>[];
    final receivedEvents = <_Event>[];

    // Cache data arrays once - CRITICAL optimization!
    if (kDebugMode) {
      print('📦 Caching latency data arrays...');
    }
    final eventTypeData = data['event_type'].data;
    final deviceIdData = data['reportingDeviceId'].data;
    final sourceIdData = data['sourceId'].data;
    final lslClockData = data['lsl_clock'].data;
    final counterData = data['counter'].data;
    final timeCorrectionData =
        includeTimeCorrections ? data['lslTimeCorrection'].data : null;
    final rowCount = eventTypeData.length;

    if (kDebugMode) {
      print(
        '🔍 Starting single-pass event extraction through $rowCount rows...',
      );
    }

    var processedRows = 0;
    var skippedRows = 0;

    for (int i = 0; i < rowCount; i++) {
      final eventType = eventTypeData[i] as String?;

      if (eventType != eventTypeSampleSent &&
          eventType != eventTypeSampleReceived) {
        skippedRows++;
        continue;
      }

      final deviceId = deviceIdData[i] as String?;
      final sourceId = sourceIdData[i] as String?;
      final lslClock = lslClockData[i] as double?;
      final counter = counterData[i] as int?;

      if (deviceId == null ||
          sourceId == null ||
          lslClock == null ||
          counter == null) {
        skippedRows++;
        continue;
      }

      processedRows++;

      // Progress logging for very large datasets
      if (kDebugMode) {
        if (processedRows % 50000 == 0) {
          print(
            '🔄 Processed $processedRows events, skipped $skippedRows rows so far...',
          );
        }
      }

      double? timeCorrection;
      if (includeTimeCorrections && timeCorrectionData != null) {
        final correction = timeCorrectionData[i] as double?;
        if (correction != null && !correction.isNaN) {
          timeCorrection = correction;
        }
      }

      final event = _Event(
        deviceId: deviceId,
        sourceId: sourceId,
        lslClock: lslClock,
        counter: counter,
        timeCorrection: timeCorrection,
      );

      if (eventType == eventTypeSampleSent) {
        sentEvents.add(event);
      } else {
        receivedEvents.add(event);
      }
    }

    if (kDebugMode) {
      print('✅ Event extraction summary:');
      print('  📤 Sent events: ${sentEvents.length}');
      print('  📥 Received events: ${receivedEvents.length}');
      print('  ✋ Skipped rows: $skippedRows');
      print('  📊 Total processed: $processedRows');
    }

    return _EventData(sent: sentEvents, received: receivedEvents);
  }

  /// Group events efficiently for fast lookup
  _GroupedEventData _groupEventDataEfficiently(_EventData eventData) {
    final groupedData = <String, _SourceEventGroup>{};

    if (kDebugMode) {
      print(
        '🗂️ Grouping ${eventData.sent.length} sent and ${eventData.received.length} received events...',
      );
    }

    // Group sent events by source
    for (final event in eventData.sent) {
      final group = groupedData.putIfAbsent(
        event.sourceId,
        () => _SourceEventGroup(
          sourceId: event.sourceId,
          senderDevice: event.deviceId,
          sentEvents: <int, _Event>{},
          receivedEvents: <String, Map<int, _Event>>{},
        ),
      );
      group.sentEvents[event.counter] = event;
    }

    // Group received events by source and device
    for (final event in eventData.received) {
      final group = groupedData[event.sourceId];
      if (group != null) {
        final deviceEvents = group.receivedEvents.putIfAbsent(
          event.deviceId,
          () => <int, _Event>{},
        );
        deviceEvents[event.counter] = event;
      }
    }

    if (kDebugMode) {
      print('✅ Grouping complete: ${groupedData.length} source groups created');
    }

    return groupedData;
  }

  /// Calculate latencies from pre-grouped data - very fast
  List<LatencyResult> _calculateLatenciesFromGroupedData(
    _GroupedEventData groupedData,
    bool hasTimeCorrections,
  ) {
    final results = <LatencyResult>[];

    if (kDebugMode) {
      print(
        '🎯 Starting latency calculations for ${groupedData.length} sources...',
      );
    }

    for (final group in groupedData.values) {
      for (final deviceId in group.receivedEvents.keys) {
        // Include self-latency (device receiving its own samples)

        final receivedEvents = group.receivedEvents[deviceId]!;
        final latencies = <double>[];
        final rawLatencies = <double>[];
        bool appliedTimeCorrection = false;

        // Fast matching using pre-indexed data
        for (final entry in group.sentEvents.entries) {
          final counter = entry.key;
          final sentEvent = entry.value;
          final receivedEvent = receivedEvents[counter];

          if (receivedEvent != null) {
            final rawLatency =
                (receivedEvent.lslClock - sentEvent.lslClock) * 1000;
            rawLatencies.add(rawLatency);

            // Apply time corrections if available
            double correctedLatency = rawLatency;

            if (hasTimeCorrections) {
              // Time correction logic: The lslTimeCorrection represents the clock offset
              // that needs to be applied to align timestamps between devices
              //
              // Formula: corrected_latency = (received_time_corrected - sent_time_corrected)
              // where corrected_time = original_time + time_correction

              final double sentTimeCorrection = 0.0;
              double receivedTimeCorrection =
                  receivedEvent.timeCorrection ?? 0.0;

              if (sentTimeCorrection != 0.0 || receivedTimeCorrection != 0.0) {
                // Apply corrections to align both timestamps to a common reference
                double correctedSentTime =
                    sentEvent.lslClock + sentTimeCorrection;
                double correctedReceivedTime =
                    receivedEvent.lslClock - receivedTimeCorrection;
                correctedLatency -= receivedEvent.timeCorrection! * 1000;
                appliedTimeCorrection = true;

                if (kDebugMode && latencies.length < 3) {
                  // ignore: avoid_print
                  print('  🔧 Time correction applied:');
                  // ignore: avoid_print
                  print(
                    '    📤 Sent: ${sentEvent.lslClock.toStringAsFixed(6)} + ${sentTimeCorrection.toStringAsFixed(6)} = ${correctedSentTime.toStringAsFixed(6)}',
                  );
                  // ignore: avoid_print
                  print(
                    '    📥 Received: ${receivedEvent.lslClock.toStringAsFixed(6)} + ${receivedTimeCorrection.toStringAsFixed(6)} = ${correctedReceivedTime.toStringAsFixed(6)}',
                  );
                  // ignore: avoid_print
                  print(
                    '    ⏱️ Raw latency: ${rawLatency.toStringAsFixed(2)}ms → Corrected: ${correctedLatency.toStringAsFixed(2)}ms',
                  );
                }
              }
            }

            latencies.add(correctedLatency);
          }
        }

        if (latencies.isNotEmpty) {
          results.add(
            _calculateLatencyStats(
              group.senderDevice,
              deviceId,
              latencies,
              rawLatencies,
              appliedTimeCorrection,
            ),
          );

          if (kDebugMode) {
            print(
              '  ✅ ${group.senderDevice} → $deviceId: ${latencies.length} latency measurements (${appliedTimeCorrection ? 'time-corrected' : 'raw'})',
            );
          }
        }
      }
    }

    if (kDebugMode) {
      print(
        '🎉 Latency calculations complete: ${results.length} device pair results',
      );
    }

    return results;
  }

  /// Calculate interval statistics
  InterSampleIntervalResult _calculateIntervalStats(
    String deviceId,
    List<double> intervals,
  ) {
    final trimmed = _trimOutliers(intervals, 0.02);
    final stats = _calculateStats(trimmed);

    return InterSampleIntervalResult(
      deviceId: deviceId,
      intervals: trimmed,
      mean: stats['mean']!,
      median: stats['median']!,
      standardDeviation: stats['std']!,
      min: stats['min']!,
      max: stats['max']!,
      count: trimmed.length,
    );
  }

  /// Calculate latency statistics
  LatencyResult _calculateLatencyStats(
    String fromDevice,
    String toDevice,
    List<double> latencies,
    List<double> rawLatencies,
    bool timeCorrectionApplied,
  ) {
    final trimmed = _trimOutliers(latencies, 0.02);
    final stats = _calculateStats(trimmed);

    return LatencyResult(
      fromDevice: fromDevice,
      toDevice: toDevice,
      latencies: trimmed,
      rawLatencies: rawLatencies,
      mean: stats['mean']!,
      median: stats['median']!,
      standardDeviation: stats['std']!,
      min: stats['min']!,
      max: stats['max']!,
      count: trimmed.length,
      timeCorrectionApplied: timeCorrectionApplied,
    );
  }

  /// Remove outliers efficiently
  List<double> _trimOutliers(List<double> data, double trimPercentage) {
    if (data.length < 10) return data; // Skip trimming for small datasets

    final sorted = List<double>.from(data)..sort();
    final trimCount = (sorted.length * trimPercentage).round();

    if (trimCount > 0 && trimCount * 2 < sorted.length) {
      return sorted.sublist(trimCount, sorted.length - trimCount);
    }

    return sorted;
  }

  /// Calculate statistics efficiently
  Map<String, double> _calculateStats(List<double> values) {
    if (values.isEmpty) {
      return {'mean': 0.0, 'median': 0.0, 'std': 0.0, 'min': 0.0, 'max': 0.0};
    }

    final sorted = List<double>.from(values)..sort();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final median = sorted.length % 2 == 0
        ? (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2
        : sorted[sorted.length ~/ 2];

    // Fast variance calculation
    double sumSquares = 0;
    for (final value in values) {
      final diff = value - mean;
      sumSquares += diff * diff;
    }
    final variance = sumSquares / values.length;
    final standardDeviation = sqrt(variance);

    return {
      'mean': mean,
      'median': median,
      'std': standardDeviation,
      'min': sorted.first,
      'max': sorted.last,
    };
  }
}

/// Efficient event data structure
class _Event {
  final String deviceId;
  final String sourceId;
  final double lslClock;
  final int counter;
  final double? timeCorrection;

  const _Event({
    required this.deviceId,
    required this.sourceId,
    required this.lslClock,
    required this.counter,
    this.timeCorrection,
  });
}

/// Container for all extracted events
class _EventData {
  final List<_Event> sent;
  final List<_Event> received;

  const _EventData({required this.sent, required this.received});
}

/// Grouped events by source for efficient processing
class _SourceEventGroup {
  final String sourceId;
  final String senderDevice;
  final Map<int, _Event> sentEvents; // counter -> event
  final Map<String, Map<int, _Event>>
      receivedEvents; // deviceId -> (counter -> event)

  _SourceEventGroup({
    required this.sourceId,
    required this.senderDevice,
    required this.sentEvents,
    required this.receivedEvents,
  });
}

typedef _GroupedEventData = Map<String, _SourceEventGroup>;
