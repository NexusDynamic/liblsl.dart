// lib/src/config/app_config.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liblsl/lsl.dart';
import 'constants.dart';
import 'dart:math' as math;

class AppConfig {
  // Stream configuration
  String deviceName;
  String streamName;
  LSLContentType streamType;
  int channelCount;
  double sampleRate;
  LSLChannelFormat channelFormat;

  // Role configuration
  bool isProducer;
  bool isConsumer;

  // Test configuration
  int testDurationSeconds;

  // Stream configuration
  double streamMaxWaitTimeSeconds;
  int streamMaxStreams;

  // Create a unique device ID for this session
  String deviceId;

  AppConfig({
    this.deviceName = 'Device',
    this.streamName = StreamDefaults.streamName,
    this.streamType = LSLContentType.markers,
    this.channelCount = StreamDefaults.channelCount,
    this.sampleRate = StreamDefaults.sampleRate,
    this.channelFormat = LSLChannelFormat.float32,
    this.isProducer = true,
    this.isConsumer = true,
    this.deviceId = '',
    this.testDurationSeconds = 10,
    this.streamMaxWaitTimeSeconds = 5.0,
    this.streamMaxStreams = 10,
  });

  AppConfig copyMerged(
    Map<String, dynamic> overrides, {
    bool excludeDeviceSpecific = false,
  }) {
    return AppConfig(
      deviceName:
          overrides[ConfigKeys.deviceName] != null && !excludeDeviceSpecific
              ? overrides[ConfigKeys.deviceName]
              : deviceName,
      streamName: overrides[ConfigKeys.streamName] ?? streamName,
      streamType: overrides[ConfigKeys.streamType] != null
          ? _getStreamType(overrides[ConfigKeys.streamType])
          : streamType,
      channelCount: overrides[ConfigKeys.channelCount] ?? channelCount,
      sampleRate: overrides[ConfigKeys.sampleRate] ?? sampleRate,
      channelFormat: overrides[ConfigKeys.channelFormat] != null
          ? _getChannelFormat(overrides[ConfigKeys.channelFormat])
          : channelFormat,
      isProducer:
          overrides[ConfigKeys.isProducer] != null && !excludeDeviceSpecific
              ? overrides[ConfigKeys.isProducer]
              : isProducer,
      isConsumer:
          overrides[ConfigKeys.isConsumer] != null && !excludeDeviceSpecific
              ? overrides[ConfigKeys.isConsumer]
              : isConsumer,
      deviceId: overrides[ConfigKeys.deviceId] != null && !excludeDeviceSpecific
          ? overrides[ConfigKeys.deviceId]
          : deviceId,
      testDurationSeconds:
          overrides[ConfigKeys.testDurationSeconds] ?? testDurationSeconds,
      streamMaxWaitTimeSeconds:
          overrides[ConfigKeys.streamMaxWaitTimeSeconds] ??
              streamMaxWaitTimeSeconds,
      streamMaxStreams:
          overrides[ConfigKeys.streamMaxStreams] ?? streamMaxStreams,
    );
  }

  // Load from SharedPreferences
  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();

    final config = AppConfig(
      deviceName: prefs.getString(ConfigKeys.deviceName) ??
          'Device_${math.Random().nextInt(100)}',
      streamName:
          prefs.getString(ConfigKeys.streamName) ?? StreamDefaults.streamName,
      streamType: _getStreamType(prefs.getString(ConfigKeys.streamType)),
      channelCount:
          prefs.getInt(ConfigKeys.channelCount) ?? StreamDefaults.channelCount,
      sampleRate:
          prefs.getDouble(ConfigKeys.sampleRate) ?? StreamDefaults.sampleRate,
      channelFormat: _getChannelFormat(
        prefs.getString(ConfigKeys.channelFormat),
      ),
      deviceId: prefs.getString(ConfigKeys.deviceId) ??
          '${math.Random().nextInt(1000)}_DID',
      isProducer: prefs.getBool(ConfigKeys.isProducer) ?? true,
      isConsumer: prefs.getBool(ConfigKeys.isConsumer) ?? true,
      testDurationSeconds: prefs.getInt(ConfigKeys.testDurationSeconds) ?? 30,
      streamMaxWaitTimeSeconds:
          prefs.getDouble(ConfigKeys.streamMaxWaitTimeSeconds) ?? 5.0,
      streamMaxStreams: prefs.getInt(ConfigKeys.streamMaxStreams) ?? 15,
    );

    return config;
  }

  // Save to SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(ConfigKeys.deviceName, deviceName);
    await prefs.setString(ConfigKeys.streamName, streamName);
    await prefs.setString(ConfigKeys.streamType, streamType.value);
    await prefs.setInt(ConfigKeys.channelCount, channelCount);
    await prefs.setDouble(ConfigKeys.sampleRate, sampleRate);
    await prefs.setString(ConfigKeys.channelFormat, channelFormat.name);
    await prefs.setBool(ConfigKeys.isProducer, isProducer);
    await prefs.setBool(ConfigKeys.isConsumer, isConsumer);
    await prefs.setString(ConfigKeys.deviceId, deviceId);
    await prefs.setInt(ConfigKeys.testDurationSeconds, testDurationSeconds);
    await prefs.setDouble(
      ConfigKeys.streamMaxWaitTimeSeconds,
      streamMaxWaitTimeSeconds,
    );
    await prefs.setInt(ConfigKeys.streamMaxStreams, streamMaxStreams);
  }

  // Helper methods for conversion
  static LSLContentType _getStreamType(String? value) {
    if (value == null) return LSLContentType.markers;

    try {
      return LSLContentType.values.firstWhere(
        (type) => type.value == value,
        orElse: () => LSLContentType.markers,
      );
    } catch (_) {
      return LSLContentType.markers;
    }
  }

  static LSLChannelFormat _getChannelFormat(String? value) {
    if (value == null) return LSLChannelFormat.float32;

    try {
      return LSLChannelFormat.values.firstWhere(
        (format) => format.name == value,
        orElse: () => LSLChannelFormat.float32,
      );
    } catch (_) {
      return LSLChannelFormat.float32;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      ConfigKeys.deviceName: deviceName,
      ConfigKeys.streamName: streamName,
      ConfigKeys.streamType: streamType.value,
      ConfigKeys.channelCount: channelCount,
      ConfigKeys.sampleRate: sampleRate,
      ConfigKeys.channelFormat: channelFormat.name,
      ConfigKeys.isProducer: isProducer,
      ConfigKeys.isConsumer: isConsumer,
      ConfigKeys.deviceId: deviceId,
      ConfigKeys.testDurationSeconds: testDurationSeconds,
      ConfigKeys.streamMaxWaitTimeSeconds: streamMaxWaitTimeSeconds,
      ConfigKeys.streamMaxStreams: streamMaxStreams,
    };
  }

  @override
  String toString() {
    return 'AppConfig{'
        'deviceName: $deviceName, '
        'streamName: $streamName, '
        'deviceId: $deviceId, '
        'streamType: $streamType, '
        'channelCount: $channelCount, '
        'sampleRate: $sampleRate, '
        'channelFormat: $channelFormat, '
        'isProducer: $isProducer, '
        'isConsumer: $isConsumer, '
        'testDurationSeconds: $testDurationSeconds, '
        'streamMaxWaitTimeSeconds: $streamMaxWaitTimeSeconds, '
        'streamMaxStreams: $streamMaxStreams'
        '}';
  }
}
