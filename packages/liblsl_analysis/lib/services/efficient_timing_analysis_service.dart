import 'dart:math';
import 'package:dartframe/dartframe.dart';
import 'package:liblsl_analysis/extensions/series_pick_indices.dart';

/// Results for inter-sample interval analysis
class InterSampleIntervalResult {
  final String deviceId;
  final List<double> intervals;
  final double mean;
  final double median;
  final double standardDeviation;
  final double min;
  final double max;
  final int count;

  InterSampleIntervalResult({
    required this.deviceId,
    required this.intervals,
    required this.mean,
    required this.median,
    required this.standardDeviation,
    required this.min,
    required this.max,
    required this.count,
  });
}

/// Results for latency analysis between devices
class LatencyResult {
  final String fromDevice;
  final String toDevice;
  final List<double> latencies;
  final double mean;
  final double median;
  final double standardDeviation;
  final double min;
  final double max;
  final int count;

  LatencyResult({
    required this.fromDevice,
    required this.toDevice,
    required this.latencies,
    required this.mean,
    required this.median,
    required this.standardDeviation,
    required this.min,
    required this.max,
    required this.count,
  });
}

/// Efficient service for analyzing LSL timing data using DartFrame patterns
class EfficientTimingAnalysisService {
  static const String eventTypeSampleSent = 'EventType.sampleSent';
  static const String eventTypeSampleReceived = 'EventType.sampleReceived';

  /// Calculate inter-sample intervals for each producing device
  List<InterSampleIntervalResult> calculateInterSampleIntervals(
    DataFrame data,
  ) {
    final results = <InterSampleIntervalResult>[];

    // Get unique reporting devices
    final uniqueReporters = data['reportingDeviceId'].unique();

    for (final deviceId in uniqueReporters) {
      if (deviceId == null || deviceId.isEmpty) continue;

      // Get indices for samples sent by this device
      final deviceIndices = data['reportingDeviceId'].getIndicesWhere(
        (val) => val == deviceId,
      );
      final sentIndices = data['event_type'].getIndicesWhere(
        (val) => val == eventTypeSampleSent,
      );

      // Find intersection of device samples that were sent
      final sentByDeviceIndices = deviceIndices
          .toSet()
          .intersection(sentIndices.toSet())
          .toList();
      if (sentByDeviceIndices.length < 2) {
        continue; // Need at least 2 samples for intervals
      }

      // Sort by index to maintain temporal order
      sentByDeviceIndices.sort();

      // Extract timestamps for these samples
      final timestamps = data['lsl_clock'].selectByIndices(sentByDeviceIndices);

      final intervals = <double>[];
      for (int i = 1; i < timestamps.data.length; i++) {
        final interval =
            ((timestamps.data[i] as double) -
                (timestamps.data[i - 1] as double)) *
            1000;
        intervals.add(interval);
      }

      if (intervals.isNotEmpty) {
        results.add(calculateIntervalStats(deviceId as String, intervals));
      }
    }

    return results;
  }

  /// Calculate latency between devices
  List<LatencyResult> calculateLatencies(DataFrame data) {
    final results = <LatencyResult>[];

    // Get unique source IDs and reporting devices
    final uniqueSources = data['sourceId'].unique();
    final uniqueReporters = data['reportingDeviceId'].unique();

    for (final sourceId in uniqueSources) {
      if (sourceId == null || sourceId.isEmpty) continue;

      // Get sent samples for this source
      final sourceIndices = data['sourceId'].getIndicesWhere(
        (val) => val == sourceId,
      );
      final sentIndices = data['event_type'].getIndicesWhere(
        (val) => val == eventTypeSampleSent,
      );
      final sentBySourceIndices = sourceIndices
          .toSet()
          .intersection(sentIndices.toSet())
          .toList();

      if (sentBySourceIndices.isEmpty) continue;

      // Get sent data
      final sentCounters = data['counter'].selectByIndices(sentBySourceIndices);
      final sentTimestamps = data['lsl_clock'].selectByIndices(
        sentBySourceIndices,
      );
      final sentDevices = data['reportingDeviceId'].selectByIndices(
        sentBySourceIndices,
      );

      // For each receiving device
      for (final receivingDeviceId in uniqueReporters) {
        if (receivingDeviceId == null || receivingDeviceId.isEmpty) continue;

        // Get the actual sender device for this source
        final senderDevice = sentDevices.data.isNotEmpty
            ? sentDevices.data.first as String
            : '';
        if (senderDevice.isEmpty) continue;

        // Get received samples for this source by this device
        final receiverIndices = data['reportingDeviceId'].getIndicesWhere(
          (val) => val == receivingDeviceId,
        );
        final receivedIndices = data['event_type'].getIndicesWhere(
          (val) => val == eventTypeSampleReceived,
        );
        final receivedByDeviceIndices = sourceIndices
            .toSet()
            .intersection(receiverIndices.toSet())
            .intersection(receivedIndices.toSet())
            .toList();

        if (receivedByDeviceIndices.isEmpty) continue;

        // Get received data
        final receivedCounters = data['counter'].selectByIndices(
          receivedByDeviceIndices,
        );
        final receivedTimestamps = data['lsl_clock'].selectByIndices(
          receivedByDeviceIndices,
        );

        // Match sent and received samples by counter
        final latencies = <double>[];

        for (int sentIdx = 0; sentIdx < sentCounters.data.length; sentIdx++) {
          final sentCounter = sentCounters.data[sentIdx] as int;
          final sentTime = sentTimestamps.data[sentIdx] as double;

          // Find matching received sample
          for (
            int recIdx = 0;
            recIdx < receivedCounters.data.length;
            recIdx++
          ) {
            final receivedCounter = receivedCounters.data[recIdx] as int;
            if (receivedCounter == sentCounter) {
              final receivedTime = receivedTimestamps.data[recIdx] as double;
              final latency = (receivedTime - sentTime) * 1000; // Convert to ms
              latencies.add(latency);
              break;
            }
          }
        }

        if (latencies.isNotEmpty) {
          results.add(
            calculateLatencyStats(
              senderDevice,
              receivingDeviceId as String,
              latencies,
            ),
          );
        }
      }
    }

    return results;
  }

  /// Calculate statistical measures for intervals
  InterSampleIntervalResult calculateIntervalStats(
    String deviceId,
    List<double> intervals,
  ) {
    // Remove outliers (trim 2% from each end)
    final trimmedIntervals = _trimOutliers(intervals, 0.02);

    final stats = _calculateStats(trimmedIntervals);

    return InterSampleIntervalResult(
      deviceId: deviceId,
      intervals: trimmedIntervals,
      mean: stats['mean']!,
      median: stats['median']!,
      standardDeviation: stats['std']!,
      min: stats['min']!,
      max: stats['max']!,
      count: trimmedIntervals.length,
    );
  }

  /// Calculate statistical measures for latencies
  LatencyResult calculateLatencyStats(
    String fromDevice,
    String toDevice,
    List<double> latencies,
  ) {
    // Remove outliers (trim 2% from each end)
    final trimmedLatencies = _trimOutliers(latencies, 0.02);

    final stats = _calculateStats(trimmedLatencies);

    return LatencyResult(
      fromDevice: fromDevice,
      toDevice: toDevice,
      latencies: trimmedLatencies,
      mean: stats['mean']!,
      median: stats['median']!,
      standardDeviation: stats['std']!,
      min: stats['min']!,
      max: stats['max']!,
      count: trimmedLatencies.length,
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
