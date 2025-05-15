// lib/src/data/timing_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:liblsl_timing/src/config/app_config.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter/widgets.dart';
import 'package:liblsl/lsl.dart';
import '../config/constants.dart';

class TimingEvent {
  final double timestamp;
  final EventType eventType;
  final String? description;
  final Map<String, dynamic>? metadata;
  final String eventId;
  final double eventTimestamp = DateTime.now().microsecondsSinceEpoch / 1000000;

  TimingEvent({
    required this.timestamp,
    required this.eventType,
    this.description,
    this.metadata,
    String? eventId,
  }) : eventId = eventId ?? _generateEventId();

  static String _generateEventId() {
    return 'evt_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'eventTimestamp': eventTimestamp,
      'timestamp': timestamp,
      'eventType': eventType.toString(),
      'description': description,
      'metadata': metadata,
      'eventId': eventId,
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class TimingManager {
  // Collection to store all timing events
  final List<TimingEvent> _events = [];

  final _lock = Lock();

  // Metrics calculated from events
  final Map<String, List<double>> _metrics = {};

  // Stream controller for real-time updates
  final StreamController<TimingEvent> _eventStreamController =
      StreamController<TimingEvent>.broadcast();

  AppConfig config;

  // Base time offset to align LSL and Flutter times
  double _timeBaseOffset = 0.0;
  bool _timeBaseCalibrated = false;

  // Getters for external access
  List<TimingEvent> get events => List.unmodifiable(_events);
  Map<String, List<double>> get metrics => Map.unmodifiable(_metrics);
  Stream<TimingEvent> get eventStream => _eventStreamController.stream;

  /// Initialize the timing manager
  TimingManager(this.config);

  /// Calibrate time base between LSL and Flutter
  /// In theory, this should be the same, but with a potentially different time
  /// scale.
  Future<void> calibrateTimeBase() async {
    const measurements = 10;
    double totalOffset = 0.0;

    for (int i = 0; i < measurements; i++) {
      final flutterTime = DateTime.now().microsecondsSinceEpoch / 1000000;
      final lslTime = LSL.localClock();
      totalOffset += (lslTime - flutterTime);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _timeBaseOffset = totalOffset / measurements;
    _timeBaseCalibrated = true;

    recordEvent(
      EventType.clockCorrection,
      description: 'Time base calibrated between Flutter and LSL',
      metadata: {'offset': _timeBaseOffset},
    );
  }

  Map<String, dynamic> _injectMetadata(Map<String, dynamic>? metadata) {
    final injectedMetadata = metadata ?? {};
    injectedMetadata['reportingDeviceId'] = config.deviceId;
    injectedMetadata['reportingDeviceName'] = config.deviceName;
    return injectedMetadata;
  }

  /// Record a new timing event with the current timestamp
  Future<TimingEvent> recordEvent(
    EventType eventType, {
    String? description,
    Map<String, dynamic>? metadata,
    String? eventId,
  }) async {
    final event = TimingEvent(
      timestamp: DateTime.now().microsecondsSinceEpoch / 1000000,
      eventType: eventType,
      description: description,
      metadata: _injectMetadata(metadata),
      eventId: eventId,
    );
    await _lock.synchronized(() {
      _events.add(event);
    });
    _eventStreamController.add(event);
    return event;
  }

  /// Record an event with a specific timestamp
  Future<TimingEvent> recordTimestampedEvent(
    EventType eventType,
    double timestamp, {
    String? description,
    Map<String, dynamic>? metadata,
    String? eventId,
  }) async {
    final event = TimingEvent(
      timestamp: timestamp,
      eventType: eventType,
      description: description,
      metadata: _injectMetadata(metadata),
      eventId: eventId,
    );
    await _lock.synchronized(() {
      _events.add(event);
    });
    _eventStreamController.add(event);
    return event;
  }

  /// Record UI events
  void recordUIEvent(
    PointerEvent pointerEvent, {
    String? description,
    String? eventId,
  }) async {
    final localTime = DateTime.now().microsecondsSinceEpoch / 1000000;
    final platformTime = pointerEvent.timeStamp.inMicroseconds / 1000000;
    final Map<String, dynamic> metadata = {
      'platformTimestamp': platformTime,
      'position': [pointerEvent.position.dx, pointerEvent.position.dy],
    };

    final event = TimingEvent(
      timestamp: localTime,
      eventType: EventType.sampleCreated,
      description: description ?? 'UI Event',
      metadata: _injectMetadata(metadata),
      eventId: eventId,
    );
    await _lock.synchronized(() {
      _events.add(event);
    });
    _eventStreamController.add(event);
  }

  /// Reset all collected timing data
  void reset() async {
    await _lock.synchronized(() {
      _events.clear();
    });
    _metrics.clear();
  }

  /// Calculate timing metrics between different event types
  void calculateMetrics() {
    _metrics.clear();

    // Calculate latency between event types
    _calculateLatencyBetweenEvents(
      'sample_to_receive',
      EventType.sampleSent,
      EventType.sampleReceived,
    );

    // Calculate time corrections
    _calculateTimeCorrectionStats();
  }

  void _calculateLatencyBetweenEvents(
    String metricName,
    EventType startEventType,
    EventType endEventType, {
    bool matchById = true,
  }) {
    final latencies = <double>[];

    // Group events by sampleId if matching by ID
    if (matchById) {
      final startEvents = <String, TimingEvent>{};

      for (final event in events) {
        final sampleId = event.metadata?['sampleId'] as String?;
        if (sampleId == null) continue;

        if (event.eventType == startEventType) {
          startEvents[sampleId] = event;
        } else if (event.eventType == endEventType &&
            startEvents.containsKey(sampleId)) {
          final startEvent = startEvents[sampleId]!;
          final latency = event.timestamp - startEvent.timestamp;
          latencies.add(latency);
        }
      }
    } else {
      final evts = events;
      // Simple sequential matching
      for (int i = 0; i < evts.length; i++) {
        final event = evts[i];
        if (event.eventType == startEventType) {
          // Find the next matching end event
          for (int j = i + 1; j < evts.length; j++) {
            final endEvent = evts[j];
            if (endEvent.eventType == endEventType) {
              final latency = endEvent.timestamp - event.timestamp;
              latencies.add(latency);
              break;
            }
          }
        }
      }
    }

    _metrics[metricName] = latencies;
  }

  void _calculateTimeCorrectionStats() {
    // Filter events for time correction data
    final correctionEvents = events
        .where((e) => e.eventType == EventType.clockCorrection)
        .toList();

    if (correctionEvents.isEmpty) return;

    // Extract correction values per device
    final deviceCorrections = <String, List<double>>{};

    for (final event in correctionEvents) {
      final deviceId = event.metadata?['deviceId'] as String?;
      final correction = event.metadata?['correction'] as double?;

      if (deviceId != null && correction != null) {
        deviceCorrections.putIfAbsent(deviceId, () => []).add(correction);
      }
    }

    // Calculate statistics for each device
    for (final deviceId in deviceCorrections.keys) {
      final corrections = deviceCorrections[deviceId]!;

      if (corrections.isEmpty) continue;

      final mean = corrections.reduce((a, b) => a + b) / corrections.length;
      final min = corrections.reduce(math.min);
      final max = corrections.reduce(math.max);

      // Calculate standard deviation
      final sumSquaredDiff = corrections.fold(
        0.0,
        (sum, value) => sum + math.pow(value - mean, 2),
      );
      final stdDev = math.sqrt(sumSquaredDiff / corrections.length);

      // Store statistics in the metrics
      _metrics['clock_correction_${deviceId}_mean'] = [mean];
      _metrics['clock_correction_${deviceId}_min'] = [min];
      _metrics['clock_correction_${deviceId}_max'] = [max];
      _metrics['clock_correction_${deviceId}_stddev'] = [stdDev];
    }
  }

  /// Get statistics for a metric
  Map<String, double> getMetricStats(String metricName) {
    final values = _metrics[metricName];
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

  /// Convert Flutter time to LSL equivalent time
  double flutterTimeToLSLTime(double flutterTime) {
    if (!_timeBaseCalibrated) {
      throw Exception(
        'Time base not calibrated. Call calibrateTimeBase() first.',
      );
    }
    return flutterTime + _timeBaseOffset;
  }

  /// Convert LSL time to Flutter equivalent time
  double lslTimeToFlutterTime(double lslTime) {
    if (!_timeBaseCalibrated) {
      throw Exception(
        'Time base not calibrated. Call calibrateTimeBase() first.',
      );
    }
    return lslTime - _timeBaseOffset;
  }

  void dispose() {
    _eventStreamController.close();
  }
}
