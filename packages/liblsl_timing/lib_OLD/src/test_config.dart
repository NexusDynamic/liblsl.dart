import 'package:liblsl/lsl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration parameters for LSL timing tests
class TestConfiguration {
  // Stream configuration
  String streamName = 'TimingTest';
  LSLContentType streamType = LSLContentType.markers;
  int channelCount = 1;
  double sampleRate = 100.0;
  LSLChannelFormat channelFormat = LSLChannelFormat.float32;
  String sourceId = 'TimingTestApp';

  // Test parameters
  int testDurationSeconds = 10;
  bool recordToFile = true;
  String outputDirectory = 'lsl_timing_results';

  // Network configuration
  bool useLocalNetworkOnly = true;

  // Testing device role
  bool isProducer = true;
  bool isConsumer = true;

  // Stimulus configuration
  double stimulusIntervalMs = 1000;

  // Optional CSV logging
  bool enableCsvExport = true;

  // Device synchronization
  bool enableClockSync = true;

  // Visual timing marker (for photodiode)
  bool showTimingMarker = true;
  double timingMarkerSizePixels = 50;

  TestConfiguration();

  Map<String, dynamic> toJson() {
    return {
      'streamName': streamName,
      'streamType': streamType.value,
      'channelCount': channelCount,
      'sampleRate': sampleRate,
      'channelFormat': channelFormat.name,
      'sourceId': sourceId,
      'testDurationSeconds': testDurationSeconds,
      'recordToFile': recordToFile,
      'outputDirectory': outputDirectory,
      'useLocalNetworkOnly': useLocalNetworkOnly,
      'isProducer': isProducer,
      'isConsumer': isConsumer,
      'stimulusIntervalMs': stimulusIntervalMs,
      'enableCsvExport': enableCsvExport,
      'enableClockSync': enableClockSync,
      'showTimingMarker': showTimingMarker,
      'timingMarkerSizePixels': timingMarkerSizePixels,
    };
  }

  // Save config to SharedPreferences
  Future<void> saveToPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Convert to JSON first
    final configJson = toJson();

    // Save each property
    for (final key in configJson.keys) {
      final value = configJson[key];

      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else {
        // For complex types, convert to string
        await prefs.setString(key, value.toString());
      }
    }
  }

  factory TestConfiguration.fromJson(Map<String, dynamic> json) {
    final config = TestConfiguration();

    config.streamName = json['streamName'] ?? 'TimingTest';
    config.streamType = LSLContentType.values.firstWhere(
      (t) => t.value == json['streamType'],
      orElse: () => LSLContentType.markers,
    );
    config.channelCount = json['channelCount'] ?? 1;
    config.sampleRate = json['sampleRate'] ?? 100.0;
    config.channelFormat = LSLChannelFormat.values.firstWhere(
      (f) => f.name == json['channelFormat'],
      orElse: () => LSLChannelFormat.float32,
    );
    config.sourceId = json['sourceId'] ?? 'TimingTestApp';
    config.testDurationSeconds = json['testDurationSeconds'] ?? 10;
    config.recordToFile = json['recordToFile'] ?? true;
    config.outputDirectory = json['outputDirectory'] ?? 'lsl_timing_results';
    config.useLocalNetworkOnly = json['useLocalNetworkOnly'] ?? true;
    config.isProducer = json['isProducer'] ?? true;
    config.isConsumer = json['isConsumer'] ?? true;
    config.stimulusIntervalMs = json['stimulusIntervalMs'] ?? 1000;
    config.enableCsvExport = json['enableCsvExport'] ?? true;
    config.enableClockSync = json['enableClockSync'] ?? true;
    config.showTimingMarker = json['showTimingMarker'] ?? true;
    config.timingMarkerSizePixels = json['timingMarkerSizePixels'] ?? 50;

    return config;
  }

  // Load config from SharedPreferences
  Future<void> loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    streamName = prefs.getString('streamName') ?? streamName;
    streamType = LSLContentType.values.firstWhere(
      (t) => t.value == prefs.getString('streamType'),
      orElse: () => streamType,
    );
    channelCount = prefs.getInt('channelCount') ?? channelCount;
    sampleRate = prefs.getDouble('sampleRate') ?? sampleRate;
    channelFormat = LSLChannelFormat.values.firstWhere(
      (f) => f.name == prefs.getString('channelFormat'),
      orElse: () => channelFormat,
    );
    sourceId = prefs.getString('sourceId') ?? sourceId;
    testDurationSeconds =
        prefs.getInt('testDurationSeconds') ?? testDurationSeconds;
    recordToFile = prefs.getBool('recordToFile') ?? recordToFile;
    outputDirectory = prefs.getString('outputDirectory') ?? outputDirectory;
    useLocalNetworkOnly =
        prefs.getBool('useLocalNetworkOnly') ?? useLocalNetworkOnly;
    isProducer = prefs.getBool('isProducer') ?? isProducer;
    isConsumer = prefs.getBool('isConsumer') ?? isConsumer;
    stimulusIntervalMs =
        prefs.getDouble('stimulusIntervalMs') ?? stimulusIntervalMs;
    enableCsvExport = prefs.getBool('enableCsvExport') ?? enableCsvExport;
    enableClockSync = prefs.getBool('enableClockSync') ?? enableClockSync;
    showTimingMarker = prefs.getBool('showTimingMarker') ?? showTimingMarker;
    timingMarkerSizePixels =
        prefs.getDouble('timingMarkerSizePixels') ?? timingMarkerSizePixels;
  }
}
