import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// A class that manages timing measurements for LSL testing
class TimingManager {
  // Collection to store all timing events
  final List<TimingEvent> _events = [];

  // Collection to store analysis results
  Map<String, List<double>> _timingMetrics = {};

  // Stream controller for real-time updates
  final StreamController<TimingEvent> _eventStreamController =
      StreamController<TimingEvent>.broadcast();

  // Getters for external access
  List<TimingEvent> get events => List.unmodifiable(_events);
  Map<String, List<double>> get timingMetrics =>
      Map.unmodifiable(_timingMetrics);
  Stream<TimingEvent> get eventStream => _eventStreamController.stream;

  /// Adds a new timing event with the current timestamp
  Future<void> recordEvent(
    String eventType, {
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final event = TimingEvent(
      timestamp: DateTime.now().microsecondsSinceEpoch / 1000000,
      eventType: eventType,
      description: description,
      metadata: metadata,
    );

    _events.add(event);
    _eventStreamController.add(event);
  }

  /// Records an event with a specific timestamp (useful for LSL timestamps)
  void recordTimestampedEvent(
    String eventType,
    double timestamp, {
    String? description,
    Map<String, dynamic>? metadata,
  }) {
    final event = TimingEvent(
      timestamp: timestamp,
      eventType: eventType,
      description: description,
      metadata: metadata,
    );

    _events.add(event);
    _eventStreamController.add(event);
  }

  /// Records a UI event (touch, button press, etc.)
  void recordUIEvent(
    String eventType,
    PointerEvent pointerEvent, {
    String? description,
  }) {
    // Record both local time and the platform time from the pointer event
    final localTime = DateTime.now().microsecondsSinceEpoch / 1000000;
    final platformTime = pointerEvent.timeStamp.inMicroseconds / 1000000;

    final event = TimingEvent(
      timestamp: localTime,
      eventType: eventType,
      description: description,
      metadata: {
        'platformTimestamp': platformTime,
        'position': [pointerEvent.position.dx, pointerEvent.position.dy],
      },
    );

    _events.add(event);
    _eventStreamController.add(event);
  }

  /// Records a frame render event
  void recordFrameEvent(String description) {
    final event = TimingEvent(
      timestamp: DateTime.now().microsecondsSinceEpoch / 1000000,
      eventType: 'frame',
      description: description,
    );

    _events.add(event);
    _eventStreamController.add(event);
  }

  /// Resets all collected timing data
  void reset() {
    _events.clear();
    _timingMetrics.clear();
  }

  /// Calculates timing metrics between different event types
  void calculateMetrics() {
    _timingMetrics = {};

    // Example: Calculate latency between UI events and LSL sample creation
    _calculateLatencyBetweenEvents(
      'ui_to_sample',
      'ui_event',
      'sample_created',
    );

    // Calculate latency between sample creation and LSL timestamp
    _calculateLatencyBetweenEvents(
      'sample_to_lsl',
      'sample_created',
      'lsl_timestamp',
    );

    // Calculate latency between LSL timestamp and sample reception
    _calculateLatencyBetweenEvents(
      'lsl_to_receive',
      'lsl_timestamp',
      'sample_received',
    );

    // Calculate latency between sample creation and LSL reported timestamp
    _calculateLatencyBetweenEvents(
      'created_to_lsl_reported',
      'sample_created',
      'received_lsl_timestamp',
    );

    _calculateLatencyBetweenEvents(
      'recieved_to_lsl_reported',
      'sample_processed',
      'lsl_timestamp',
    );

    // Calculate end-to-end latency
    _calculateLatencyBetweenEvents(
      'end_to_end',
      'ui_event',
      'sample_processed',
    );

    // Calculate frame latency
    _calculateLatencyBetweenEvents('frame_latency', 'frame_start', 'frame_end');
  }

  void _calculateLatencyBetweenEvents(
    String metricName,
    String startEventType,
    String endEventType,
  ) {
    final latencies = <double>[];

    for (int i = 0; i < _events.length; i++) {
      final event = _events[i];
      if (event.eventType == startEventType) {
        // Find the corresponding end event
        // This is simplified - in a real app, you'd need logic to match events
        // based on sequence IDs or other metadata
        for (int j = i + 1; j < _events.length; j++) {
          final endEvent = _events[j];
          if (endEvent.eventType == endEventType) {
            final latency = endEvent.timestamp - event.timestamp;
            latencies.add(latency);
            break;
          }
        }
      }
    }

    _timingMetrics[metricName] = latencies;
  }

  /// Provides summary statistics for a specific metric
  Map<String, double> getMetricStats(String metricName) {
    final values = _timingMetrics[metricName];
    if (values == null || values.isEmpty) {
      return {'mean': 0, 'min': 0, 'max': 0, 'stdDev': 0};
    }

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

  void dispose() {
    _eventStreamController.close();
  }
}

/// Class representing a single timing event
class TimingEvent {
  final double timestamp;
  final String eventType;
  final String? description;
  final Map<String, dynamic>? metadata;

  TimingEvent({
    required this.timestamp,
    required this.eventType,
    this.description,
    this.metadata,
  });

  @override
  String toString() {
    return 'TimingEvent{timestamp: $timestamp, type: $eventType, description: $description}';
  }
}
