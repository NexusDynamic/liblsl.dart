import 'dart:math';
import 'package:dartframe/dartframe.dart';

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

/// Sample data structure for analysis
class SampleEvent {
  final String eventType;
  final String deviceId;
  final String sourceId;
  final double lslClock;
  final int counter;
  final double? lslTimeCorrection;

  SampleEvent({
    required this.eventType,
    required this.deviceId,
    required this.sourceId,
    required this.lslClock,
    required this.counter,
    this.lslTimeCorrection,
  });
}

/// Service for analyzing LSL timing data
class TimingAnalysisService {
  static const String eventTypeSampleSent = 'EventType.sampleSent';
  static const String eventTypeSampleReceived = 'EventType.sampleReceived';

  /// Extract sample events from raw DataFrame
  List<SampleEvent> _extractSampleEvents(DataFrame data) {
    final events = <SampleEvent>[];

    final rowCount = data['event_type'].data.length;
    for (int i = 0; i < rowCount; i++) {
      final eventType = data['event_type'].data[i] as String?;
      if (eventType != eventTypeSampleSent &&
          eventType != eventTypeSampleReceived) {
        continue;
      }

      final deviceId = data['reportingDeviceId'].data[i] as String?;
      final sourceId = data['sourceId'].data[i] as String?;
      final lslClock = data['lsl_clock'].data[i] as double?;
      final counter = data['counter'].data[i] as int?;

      // Extract time correction from metadata if available
      double? lslTimeCorrection;
      try {
        final metadataStr = data['metadata'].data[i] as String?;
        if (metadataStr != null && metadataStr.contains('lslTimeCorrection')) {
          // Simple extraction - look for "lslTimeCorrection":value pattern
          final pattern = RegExp(r'"lslTimeCorrection":([^,}]+)');
          final match = pattern.firstMatch(metadataStr);
          if (match != null) {
            final correctionStr = match.group(1)?.trim();
            if (correctionStr != null && correctionStr != 'null') {
              lslTimeCorrection = double.tryParse(correctionStr);
            }
          }
        }
      } catch (e) {
        // Continue without time correction if parsing fails
      }

      if (deviceId == null ||
          sourceId == null ||
          lslClock == null ||
          counter == null) {
        continue;
      }

      events.add(
        SampleEvent(
          eventType: eventType!,
          deviceId: deviceId,
          sourceId: sourceId,
          lslClock: lslClock,
          counter: counter,
          lslTimeCorrection: lslTimeCorrection,
        ),
      );
    }

    return events;
  }

  /// Calculate inter-sample intervals for each producing device
  List<InterSampleIntervalResult> calculateInterSampleIntervals(
    DataFrame data,
  ) {
    final events = _extractSampleEvents(data);
    final results = <InterSampleIntervalResult>[];

    // Group sent events by device
    final sentEventsByDevice = <String, List<SampleEvent>>{};
    for (final event in events) {
      if (event.eventType == eventTypeSampleSent) {
        sentEventsByDevice.putIfAbsent(event.deviceId, () => []).add(event);
      }
    }

    // Calculate intervals for each device
    for (final entry in sentEventsByDevice.entries) {
      final deviceId = entry.key;
      final deviceEvents = entry.value;

      // Sort by counter to ensure proper order
      deviceEvents.sort((a, b) => a.counter.compareTo(b.counter));

      final intervals = <double>[];
      for (int i = 1; i < deviceEvents.length; i++) {
        final interval =
            (deviceEvents[i].lslClock - deviceEvents[i - 1].lslClock) *
                1000; // Convert to ms
        intervals.add(interval);
      }

      if (intervals.isNotEmpty) {
        results.add(_calculateIntervalStats(deviceId, intervals));
      }
    }

    return results;
  }

  /// Calculate latency between devices
  List<LatencyResult> calculateLatencies(DataFrame data) {
    final events = _extractSampleEvents(data);
    final results = <LatencyResult>[];

    // Group events by source and counter
    final sentEvents = <String, Map<int, SampleEvent>>{};
    final receivedEvents = <String, Map<int, List<SampleEvent>>>{};

    for (final event in events) {
      if (event.eventType == eventTypeSampleSent) {
        sentEvents.putIfAbsent(event.sourceId, () => {})[event.counter] = event;
      } else if (event.eventType == eventTypeSampleReceived) {
        receivedEvents
            .putIfAbsent(event.sourceId, () => {})
            .putIfAbsent(event.counter, () => [])
            .add(event);
      }
    }

    // Calculate latency for each source-receiver pair
    for (final sourceId in sentEvents.keys) {
      final sentByCounter = sentEvents[sourceId]!;
      final receivedByCounter = receivedEvents[sourceId] ?? {};

      // Group received events by receiving device
      final latenciesByReceiver = <String, List<double>>{};

      for (final counter in sentByCounter.keys) {
        final sentEvent = sentByCounter[counter]!;
        final receivedEventsList = receivedByCounter[counter] ?? [];

        for (final receivedEvent in receivedEventsList) {
          // Skip if it's the same device (device receiving its own sample)
          if (sentEvent.deviceId == receivedEvent.deviceId) {
            continue;
          }

          // Apply time correction if available
          // Time correction represents the offset between the clocks
          // Corrected latency = (received_time + time_correction) - sent_time
          final receivedTime = receivedEvent.lslTimeCorrection != null
              ? receivedEvent.lslClock + receivedEvent.lslTimeCorrection!
              : receivedEvent.lslClock;

          final latency =
              (receivedTime - sentEvent.lslClock) * 1000; // Convert to ms
          latenciesByReceiver
              .putIfAbsent(receivedEvent.deviceId, () => [])
              .add(latency);
        }
      }

      // Create results for each sender-receiver pair
      for (final entry in latenciesByReceiver.entries) {
        final receiverDevice = entry.key;
        final latencies = entry.value;

        if (latencies.isNotEmpty) {
          // Find the device that sent these samples
          final senderDevice = sentByCounter.values.first.deviceId;
          results.add(
            _calculateLatencyStats(senderDevice, receiverDevice, latencies),
          );
        }
      }
    }

    return results;
  }

  /// Calculate statistical measures for intervals
  InterSampleIntervalResult _calculateIntervalStats(
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
  LatencyResult _calculateLatencyStats(
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
