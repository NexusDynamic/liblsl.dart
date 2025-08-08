import 'dart:math';
import 'package:dartframe/dartframe.dart';

/// Time correction sample for interpolation
class TimeCorrectionSample {
  final double timestamp;
  final double correction;
  final String deviceId;
  final String sourceId;

  TimeCorrectionSample({
    required this.timestamp,
    required this.correction,
    required this.deviceId,
    required this.sourceId,
  });
}

/// Enhanced sample event with time correction context
class EnhancedSampleEvent {
  final String eventType;
  final String deviceId;
  final String sourceId;
  final double lslClock;
  final int counter;
  final double? lslTimeCorrection;
  final double? interpolatedTimeCorrection;

  EnhancedSampleEvent({
    required this.eventType,
    required this.deviceId,
    required this.sourceId,
    required this.lslClock,
    required this.counter,
    this.lslTimeCorrection,
    this.interpolatedTimeCorrection,
  });
}

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
  final List<double> rawLatencies;
  final double mean;
  final double median;
  final double standardDeviation;
  final double min;
  final double max;
  final int count;
  final bool timeCorrectionApplied;

  LatencyResult({
    required this.fromDevice,
    required this.toDevice,
    required this.latencies,
    required this.rawLatencies,
    required this.mean,
    required this.median,
    required this.standardDeviation,
    required this.min,
    required this.max,
    required this.count,
    required this.timeCorrectionApplied,
  });
}

/// Enhanced service for analyzing LSL timing data with proper time correction
class EnhancedTimingAnalysisService {
  static const String eventTypeSampleSent = 'EventType.sampleSent';
  static const String eventTypeSampleReceived = 'EventType.sampleReceived';

  /// Extract time correction samples from the data
  Map<String, List<TimeCorrectionSample>> _extractTimeCorrectionSamples(
    DataFrame data,
  ) {
    final correctionSamples = <String, List<TimeCorrectionSample>>{};

    final rowCount = data['lsl_clock'].data.length;
    for (int i = 0; i < rowCount; i++) {
      final deviceId = data['reportingDeviceId'].data[i] as String?;
      final sourceId = data['sourceId'].data[i] as String?;
      final lslClock = data['lsl_clock'].data[i] as double?;
      final lslTimeCorrection = data['lslTimeCorrection'].data[i] as double?;

      if (deviceId != null &&
          sourceId != null &&
          lslClock != null &&
          lslTimeCorrection != null &&
          !lslTimeCorrection.isNaN) {
        final key = '$deviceId-$sourceId';
        correctionSamples
            .putIfAbsent(key, () => [])
            .add(
              TimeCorrectionSample(
                timestamp: lslClock,
                correction: lslTimeCorrection,
                deviceId: deviceId,
                sourceId: sourceId,
              ),
            );
      }
    }

    // Sort each device's corrections by timestamp
    for (final list in correctionSamples.values) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return correctionSamples;
  }

  /// Interpolate time correction for a specific timestamp
  double? _interpolateTimeCorrection(
    List<TimeCorrectionSample> corrections,
    double timestamp,
  ) {
    if (corrections.isEmpty) return null;

    // If we only have one correction, use it
    if (corrections.length == 1) {
      return corrections.first.correction;
    }

    // Find the corrections that bracket this timestamp
    TimeCorrectionSample? before;
    TimeCorrectionSample? after;

    for (int i = 0; i < corrections.length; i++) {
      if (corrections[i].timestamp <= timestamp) {
        before = corrections[i];
      }
      if (corrections[i].timestamp > timestamp) {
        after = corrections[i];
        break;
      }
    }

    // If we're before all corrections, use the first one
    if (before == null && after != null) {
      return after.correction;
    }

    // If we're after all corrections, use the last one
    if (before != null && after == null) {
      return before.correction;
    }

    // If we have both, interpolate linearly
    if (before != null && after != null) {
      final timeDiff = after.timestamp - before.timestamp;
      final correctionDiff = after.correction - before.correction;
      final position = (timestamp - before.timestamp) / timeDiff;
      return before.correction + (correctionDiff * position);
    }

    return null;
  }

  /// Extract enhanced sample events with interpolated time corrections
  List<EnhancedSampleEvent> _extractEnhancedSampleEvents(DataFrame data) {
    final events = <EnhancedSampleEvent>[];
    final correctionSamples = _extractTimeCorrectionSamples(data);

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
      final lslTimeCorrection = data['lslTimeCorrection'].data[i] as double?;

      if (deviceId == null ||
          sourceId == null ||
          lslClock == null ||
          counter == null) {
        continue;
      }

      // Get interpolated time correction for this device-source pair
      final key = '$deviceId-$sourceId';
      final corrections = correctionSamples[key] ?? [];
      final interpolatedCorrection = _interpolateTimeCorrection(
        corrections,
        lslClock,
      );

      events.add(
        EnhancedSampleEvent(
          eventType: eventType!,
          deviceId: deviceId,
          sourceId: sourceId,
          lslClock: lslClock,
          counter: counter,
          lslTimeCorrection: lslTimeCorrection,
          interpolatedTimeCorrection: interpolatedCorrection,
        ),
      );
    }

    return events;
  }

  /// Calculate inter-sample intervals for each producing device
  List<InterSampleIntervalResult> calculateInterSampleIntervals(
    DataFrame data,
  ) {
    final events = _extractEnhancedSampleEvents(data);
    final results = <InterSampleIntervalResult>[];

    // Group sent events by device
    final sentEventsByDevice = <String, List<EnhancedSampleEvent>>{};
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

  /// Calculate latency between devices with proper time correction
  List<LatencyResult> calculateLatencies(DataFrame data) {
    final events = _extractEnhancedSampleEvents(data);
    final results = <LatencyResult>[];

    // Group events by source and counter
    final sentEvents = <String, Map<int, EnhancedSampleEvent>>{};
    final receivedEvents = <String, Map<int, List<EnhancedSampleEvent>>>{};

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
      final rawLatenciesByReceiver = <String, List<double>>{};
      final hasTimeCorrectionByReceiver = <String, bool>{};

      for (final counter in sentByCounter.keys) {
        final sentEvent = sentByCounter[counter]!;
        final receivedEventsList = receivedByCounter[counter] ?? [];

        for (final receivedEvent in receivedEventsList) {
          // Calculate raw latency
          final rawLatency =
              (receivedEvent.lslClock - sentEvent.lslClock) * 1000;

          // Apply time corrections if available
          double correctedLatency = rawLatency;
          bool timeCorrectionApplied = false;

          // Apply receiver time correction
          if (receivedEvent.interpolatedTimeCorrection != null) {
            correctedLatency +=
                receivedEvent.interpolatedTimeCorrection! * 1000;
            timeCorrectionApplied = true;
          }

          // Apply sender time correction (subtract because we're correcting the sent time)
          if (sentEvent.interpolatedTimeCorrection != null) {
            correctedLatency -= sentEvent.interpolatedTimeCorrection! * 1000;
            timeCorrectionApplied = true;
          }

          latenciesByReceiver
              .putIfAbsent(receivedEvent.deviceId, () => [])
              .add(correctedLatency);
          rawLatenciesByReceiver
              .putIfAbsent(receivedEvent.deviceId, () => [])
              .add(rawLatency);
          hasTimeCorrectionByReceiver[receivedEvent.deviceId] =
              timeCorrectionApplied;
        }
      }

      // Create results for each sender-receiver pair
      for (final entry in latenciesByReceiver.entries) {
        final receiverDevice = entry.key;
        final latencies = entry.value;
        final rawLatencies = rawLatenciesByReceiver[receiverDevice] ?? [];
        final timeCorrectionApplied =
            hasTimeCorrectionByReceiver[receiverDevice] ?? false;

        if (latencies.isNotEmpty) {
          // Find the device that sent these samples
          final senderDevice = sentByCounter.values.first.deviceId;
          results.add(
            _calculateLatencyStats(
              senderDevice,
              receiverDevice,
              latencies,
              rawLatencies,
              timeCorrectionApplied,
            ),
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
