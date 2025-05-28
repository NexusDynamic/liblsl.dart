// lib/src/config/constants.dart
enum TestType { latency, synchronization, interactive }

extension TestTypeExtension on TestType {
  String get displayName {
    switch (this) {
      case TestType.latency:
        return 'Latency Test';
      case TestType.synchronization:
        return 'Clock Synchronization Test';
      case TestType.interactive:
        return 'Interactive Timing Test';
    }
  }

  String get description {
    switch (this) {
      case TestType.latency:
        return 'Measures communication time and LSL packet timing';
      case TestType.synchronization:
        return 'Analyzes clock differences and drift between devices';
      case TestType.interactive:
        return 'End-to-end timing test with user interaction and visual feedback';
    }
  }
}

enum CoordinationMessageType {
  discovery, // Device announcing itself
  join, // Device joining the network
  deviceList, // List of connected devices
  ready, // Device is ready for test
  startTest, // Command to start a test
  stopTest, // Command to stop a test
  testResult, // Test result data
}

enum EventType {
  sampleCreated,
  sampleSent,
  sampleReceived,
  testStarted,
  testCompleted,
  markerSent,
  markerReceived,
  clockCorrection,
  initialized,
  coordination,
}

// LSL Stream configuration defaults
class StreamDefaults {
  static const String streamName = 'DartTimingTest';
  static const String controlStreamName = 'TimingControl';
  static const String streamType = 'Markers';
  static const int channelCount = 1;
  static const double sampleRate = 100.0;
  static const String sourceId = 'DartLSL';
}

// Configuration keys for SharedPreferences
class ConfigKeys {
  static const String deviceName = 'device_name';
  static const String streamName = 'stream_name';
  static const String streamType = 'stream_type';
  static const String channelCount = 'channel_count';
  static const String sampleRate = 'sample_rate';
  static const String channelFormat = 'channel_format';
  static const String isProducer = 'is_producer';
  static const String isConsumer = 'is_consumer';
  static const String deviceId = 'device_id';
  static const String streamMaxWaitTimeSeconds = 'stream_max_wait_time';
  static const String streamMaxStreams = 'stream_max_streams';
  static const String testDurationSeconds = 'test_duration_seconds';
}
