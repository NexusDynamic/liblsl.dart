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
  int testDurationSeconds = 30;

  // Create a unique device ID for this session
  final String deviceId;

  AppConfig({
    this.deviceName = 'Device',
    this.streamName = StreamDefaults.streamName,
    this.streamType = LSLContentType.markers,
    this.channelCount = StreamDefaults.channelCount,
    this.sampleRate = StreamDefaults.sampleRate,
    this.channelFormat = LSLChannelFormat.float32,
    this.isProducer = true,
    this.isConsumer = true,
  }) : deviceId = '${math.Random().nextInt(10000)}_$deviceName';

  // Load from SharedPreferences
  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();

    final config = AppConfig(
      deviceName:
          prefs.getString(ConfigKeys.deviceName) ??
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
      isProducer: prefs.getBool(ConfigKeys.isProducer) ?? true,
      isConsumer: prefs.getBool(ConfigKeys.isConsumer) ?? true,
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

  @override
  String toString() {
    return 'AppConfig{deviceName: $deviceName, streamName: $streamName, deviceId: $deviceId}';
  }
}
