import 'dart:math';
import 'package:dartframe/dartframe.dart';
import 'package:flutter/foundation.dart';

import 'efficient_timing_analysis_service.dart' as efficient;
import 'enhanced_timing_analysis_service.dart';

/// Optimized enhanced timing analysis that falls back to efficient analysis when appropriate
class OptimizedEnhancedTimingAnalysisService {
  static const String eventTypeSampleSent = 'EventType.sampleSent';
  static const String eventTypeSampleReceived = 'EventType.sampleReceived';

  final efficient.EfficientTimingAnalysisService _efficientService =
      efficient.EfficientTimingAnalysisService();

  /// Calculate inter-sample intervals (same as efficient - no time correction needed)
  List<InterSampleIntervalResult> calculateInterSampleIntervals(
    DataFrame data,
  ) {
    // Inter-sample intervals don't need time correction, so use efficient service
    final efficientResults = _efficientService.calculateInterSampleIntervals(
      data,
    );

    // Convert to enhanced format (they have the same structure)
    return efficientResults
        .map(
          (result) => InterSampleIntervalResult(
            deviceId: result.deviceId,
            intervals: result.intervals,
            mean: result.mean,
            median: result.median,
            standardDeviation: result.standardDeviation,
            min: result.min,
            max: result.max,
            count: result.count,
          ),
        )
        .toList();
  }

  /// Calculate latencies with optimized time correction handling
  List<LatencyResult> calculateLatencies(DataFrame data) {
    // Quick check: do we have meaningful time correction data?
    if (!_hasTimeCorrectionData(data)) {
      if (kDebugMode) {
        print('No time correction data found, using efficient analysis');
      }
      // No time corrections available, use efficient service
      final efficientResults = _efficientService.calculateLatencies(data);
      return efficientResults
          .map(
            (result) => LatencyResult(
              fromDevice: result.fromDevice,
              toDevice: result.toDevice,
              latencies: result.latencies,
              rawLatencies:
                  result.latencies, // Same as corrected when no correction
              mean: result.mean,
              median: result.median,
              standardDeviation: result.standardDeviation,
              min: result.min,
              max: result.max,
              count: result.count,
              timeCorrectionApplied: false,
            ),
          )
          .toList();
    }

    if (kDebugMode) {
      print('Time correction data found, using enhanced analysis');
    }

    // We have time corrections, do optimized enhanced analysis
    return _calculateLatenciesWithTimeCorrection(data);
  }

  /// Quick check if we have any meaningful time correction data
  bool _hasTimeCorrectionData(DataFrame data) {
    if (!data.columns.contains('lslTimeCorrection')) {
      return false;
    }

    // Check if we have any non-null, non-NaN time corrections
    final corrections = data['lslTimeCorrection'].data;
    for (final correction in corrections) {
      if (correction != null &&
          correction is double &&
          !correction.isNaN &&
          correction != 0.0) {
        return true;
      }
    }
    return false;
  }

  /// Optimized latency calculation with time corrections
  List<LatencyResult> _calculateLatenciesWithTimeCorrection(DataFrame data) {
    final results = <LatencyResult>[];

    // Get unique source IDs efficiently
    final uniqueSources = data['sourceId'].unique();

    for (final sourceId in uniqueSources) {
      if (sourceId == null || sourceId.isEmpty) continue;

      // Get all indices for this source efficiently
      final sourceIndices = data['sourceId'].getIndicesWhere(
        (val) => val == sourceId,
      );
      if (sourceIndices.isEmpty) continue;

      // Get sent events for this source
      final sentIndices = data['event_type'].getIndicesWhere(
        (val) => val == eventTypeSampleSent,
      );
      final sentBySourceIndices =
          sourceIndices.toSet().intersection(sentIndices.toSet()).toList();
      if (sentBySourceIndices.isEmpty) continue;

      // Extract sent data efficiently
      final sentData = _extractEventData(data, sentBySourceIndices);
      if (sentData.isEmpty) continue;

      // Get received events for this source
      final receivedIndices = data['event_type'].getIndicesWhere(
        (val) => val == eventTypeSampleReceived,
      );
      final receivedBySourceIndices =
          sourceIndices.toSet().intersection(receivedIndices.toSet()).toList();
      if (receivedBySourceIndices.isEmpty) continue;

      // Extract received data efficiently
      final receivedData = _extractEventData(data, receivedBySourceIndices);

      // Group received data by device for faster lookup
      final receivedByDevice = <String, List<Map<String, dynamic>>>{};
      for (final event in receivedData) {
        final deviceId = event['deviceId'] as String;
        receivedByDevice.putIfAbsent(deviceId, () => []).add(event);
      }

      // Calculate latencies for each receiving device
      final senderDevice = sentData.first['deviceId'] as String;

      for (final deviceId in receivedByDevice.keys) {
        if (deviceId == senderDevice) continue; // Skip self-latency

        final receivedEvents = receivedByDevice[deviceId]!;
        final latencies = <double>[];
        final rawLatencies = <double>[];
        bool hasTimeCorrection = false;

        // Create lookup map for received events by counter
        final receivedByCounter = <int, Map<String, dynamic>>{};
        for (final event in receivedEvents) {
          receivedByCounter[event['counter'] as int] = event;
        }

        // Match sent and received events
        for (final sentEvent in sentData) {
          final counter = sentEvent['counter'] as int;
          final receivedEvent = receivedByCounter[counter];

          if (receivedEvent != null) {
            final sentTime = sentEvent['lslClock'] as double;
            final receivedTime = receivedEvent['lslClock'] as double;
            final rawLatency =
                (receivedTime - sentTime) * 1000; // Convert to ms
            rawLatencies.add(rawLatency);

            // Apply time corrections if available
            double correctedLatency = rawLatency;

            final receivedCorrection =
                receivedEvent['lslTimeCorrection'] as double?;
            final sentCorrection = sentEvent['lslTimeCorrection'] as double?;

            if (receivedCorrection != null && !receivedCorrection.isNaN) {
              correctedLatency += receivedCorrection * 1000;
              hasTimeCorrection = true;
            }

            if (sentCorrection != null && !sentCorrection.isNaN) {
              correctedLatency -= sentCorrection * 1000;
              hasTimeCorrection = true;
            }

            latencies.add(correctedLatency);
          }
        }

        if (latencies.isNotEmpty) {
          results.add(
            _calculateEnhancedLatencyStats(
              senderDevice,
              deviceId,
              latencies,
              rawLatencies,
              hasTimeCorrection,
            ),
          );
        }
      }
    }

    return results;
  }

  /// Extract event data efficiently from indices
  List<Map<String, dynamic>> _extractEventData(
    DataFrame data,
    List<int> indices,
  ) {
    final events = <Map<String, dynamic>>[];

    for (final index in indices) {
      final deviceId = data['reportingDeviceId'].data[index] as String?;
      final sourceId = data['sourceId'].data[index] as String?;
      final lslClock = data['lsl_clock'].data[index] as double?;
      final counter = data['counter'].data[index] as int?;
      final lslTimeCorrection =
          data['lslTimeCorrection'].data[index] as double?;

      if (deviceId != null &&
          sourceId != null &&
          lslClock != null &&
          counter != null) {
        events.add({
          'deviceId': deviceId,
          'sourceId': sourceId,
          'lslClock': lslClock,
          'counter': counter,
          'lslTimeCorrection': lslTimeCorrection,
        });
      }
    }

    return events;
  }

  /// Calculate enhanced latency statistics
  LatencyResult _calculateEnhancedLatencyStats(
    String fromDevice,
    String toDevice,
    List<double> latencies,
    List<double> rawLatencies,
    bool timeCorrectionApplied,
  ) {
    // Remove outliers (trim 2% from each end)
    final trimmedLatencies = _trimOutliers(latencies, 0.02);
    final stats = _calculateStats(trimmedLatencies);

    return LatencyResult(
      fromDevice: fromDevice,
      toDevice: toDevice,
      latencies: trimmedLatencies,
      rawLatencies: rawLatencies,
      mean: stats['mean']!,
      median: stats['median']!,
      standardDeviation: stats['std']!,
      min: stats['min']!,
      max: stats['max']!,
      count: trimmedLatencies.length,
      timeCorrectionApplied: timeCorrectionApplied,
    );
  }

  /// Remove outliers by trimming percentage from both ends
  List<double> _trimOutliers(List<double> data, double trimPercentage) {
    final sorted = List<double>.from(data)..sort();
    final trimCount = (sorted.length * trimPercentage).round();

    if (trimCount > 0 && trimCount * 2 < sorted.length) {
      return sorted.sublist(trimCount, sorted.length - trimCount);
    }

    return sorted;
  }

  /// Calculate basic statistics for a list of values
  Map<String, double> _calculateStats(List<double> values) {
    if (values.isEmpty) {
      return {'mean': 0.0, 'median': 0.0, 'std': 0.0, 'min': 0.0, 'max': 0.0};
    }

    final sorted = List<double>.from(values)..sort();

    final mean = values.reduce((a, b) => a + b) / values.length;

    final median = sorted.length % 2 == 0
        ? (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2
        : sorted[sorted.length ~/ 2];

    final variance =
        values.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) /
            values.length;
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
