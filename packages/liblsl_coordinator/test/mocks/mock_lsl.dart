import 'dart:async';
import 'dart:math' as math;
import 'package:liblsl/lsl.dart';

/// Mock LSL implementation for testing purposes
/// This allows testing coordination logic without requiring actual LSL infrastructure
class MockLSL {
  static final Map<String, MockLSLStreamInfo> _registeredStreams = {};
  static final Map<String, MockLSLOutlet> _outlets = {};
  static final Map<String, MockLSLInlet> _inlets = {};
  static double _mockTime = 0.0;

  /// Reset all mock state - call this in test setUp
  static void reset() {
    _registeredStreams.clear();
    _outlets.clear();
    _inlets.clear();
    _mockTime = 0.0;
  }

  /// Advance mock time (useful for time-based testing)
  static void advanceTime(double seconds) {
    _mockTime += seconds;
  }

  /// Get current mock LSL time
  static double localClock() => _mockTime;

  /// Register a mock stream
  static void registerStream(MockLSLStreamInfo streamInfo) {
    _registeredStreams[streamInfo.sourceId] = streamInfo;
  }

  /// Simulate stream discovery
  static List<MockLSLStreamInfo> resolveStreams({
    String? streamName,
    String? streamType,
    double waitTime = 1.0,
    int maxStreams = 100,
  }) {
    return _registeredStreams.values.where((stream) {
      if (streamName != null && stream.streamName != streamName) return false;
      if (streamType != null && stream.streamType != streamType) return false;
      return true;
    }).take(maxStreams).toList();
  }

  /// Create a mock outlet
  static MockLSLOutlet createOutlet(MockLSLStreamInfo streamInfo) {
    final outlet = MockLSLOutlet(streamInfo);
    _outlets[streamInfo.sourceId] = outlet;
    registerStream(streamInfo);
    return outlet;
  }

  /// Create a mock inlet
  static MockLSLInlet createInlet(MockLSLStreamInfo streamInfo) {
    final inlet = MockLSLInlet(streamInfo);
    _inlets[streamInfo.sourceId] = inlet;
    return inlet;
  }

  /// Simulate data flow from outlet to inlets
  static void _distributeData(String sourceId, List<dynamic> data, double timestamp) {
    for (final inlet in _inlets.values) {
      if (inlet.streamInfo.sourceId != sourceId && inlet.isActive) {
        inlet._receiveSample(data, timestamp);
      }
    }
  }
}

/// Mock stream info
class MockLSLStreamInfo {
  final String streamName;
  final String streamType;
  final int channelCount;
  final double sampleRate;
  final LSLChannelFormat channelFormat;
  final String sourceId;
  final Map<String, String> metadata;

  MockLSLStreamInfo({
    required this.streamName,
    required this.streamType,
    required this.channelCount,
    required this.sampleRate,
    required this.channelFormat,
    required this.sourceId,
    this.metadata = const {},
  });

  factory MockLSLStreamInfo.fromRealStreamInfo(LSLStreamInfo real) {
    return MockLSLStreamInfo(
      streamName: real.streamName,
      streamType: real.streamType.toString(),
      channelCount: real.channelCount,
      sampleRate: real.sampleRate,
      channelFormat: real.channelFormat,
      sourceId: real.sourceId,
    );
  }
}

/// Mock outlet for sending data
class MockLSLOutlet {
  final MockLSLStreamInfo streamInfo;
  bool _isActive = false;
  int _samplesSent = 0;

  MockLSLOutlet(this.streamInfo);

  bool get isActive => _isActive;
  int get samplesSent => _samplesSent;

  Future<void> create() async {
    _isActive = true;
    await Future.delayed(const Duration(milliseconds: 10)); // Simulate creation delay
  }

  Future<void> destroy() async {
    _isActive = false;
    MockLSL._outlets.remove(streamInfo.sourceId);
  }

  /// Send a sample
  void pushSample(List<dynamic> data) {
    if (!_isActive) throw StateError('Outlet not active');
    
    final timestamp = MockLSL.localClock();
    _samplesSent++;
    
    // Distribute to all inlets
    MockLSL._distributeData(streamInfo.sourceId, data, timestamp);
  }

  /// Synchronous version
  void pushSampleSync(List<dynamic> data) {
    pushSample(data);
  }
}

/// Mock inlet for receiving data
class MockLSLInlet {
  final MockLSLStreamInfo streamInfo;
  bool _isActive = false;
  final List<MockLSLSample> _sampleBuffer = [];
  double _timeCorrection = 0.0;
  int _samplesReceived = 0;

  MockLSLInlet(this.streamInfo);

  bool get isActive => _isActive;
  int get samplesReceived => _samplesReceived;

  Future<void> create() async {
    _isActive = true;
    await Future.delayed(const Duration(milliseconds: 10)); // Simulate creation delay
  }

  Future<void> destroy() async {
    _isActive = false;
    MockLSL._inlets.remove(streamInfo.sourceId);
  }

  /// Internal method to receive samples from outlets
  void _receiveSample(List<dynamic> data, double timestamp) {
    if (_isActive) {
      _sampleBuffer.add(MockLSLSample(data, timestamp));
      _samplesReceived++;
      
      // Limit buffer size to prevent memory issues
      if (_sampleBuffer.length > 1000) {
        _sampleBuffer.removeAt(0);
      }
    }
  }

  /// Pull a sample (async)
  Future<MockLSLSample> pullSample({double timeout = 1.0}) async {
    if (!_isActive) throw StateError('Inlet not active');
    
    final startTime = MockLSL.localClock();
    while (MockLSL.localClock() - startTime < timeout) {
      if (_sampleBuffer.isNotEmpty) {
        return _sampleBuffer.removeAt(0);
      }
      await Future.delayed(const Duration(milliseconds: 1));
    }
    
    return MockLSLSample.empty();
  }

  /// Pull a sample (sync)
  MockLSLSample pullSampleSync({double timeout = 0.0}) {
    if (!_isActive) throw StateError('Inlet not active');
    
    if (_sampleBuffer.isNotEmpty) {
      return _sampleBuffer.removeAt(0);
    }
    
    return MockLSLSample.empty();
  }

  /// Get time correction
  Future<double> getTimeCorrection({double timeout = 1.0}) async {
    // Simulate some computation time
    await Future.delayed(const Duration(milliseconds: 5));
    return _timeCorrection;
  }

  /// Get time correction (sync)
  double getTimeCorrectionSync({double timeout = 0.01}) {
    return _timeCorrection;
  }

  /// Set mock time correction for testing
  void setMockTimeCorrection(double correction) {
    _timeCorrection = correction;
  }
}

/// Mock sample
class MockLSLSample {
  final List<dynamic> data;
  final double timestamp;

  MockLSLSample(this.data, this.timestamp);

  factory MockLSLSample.empty() => MockLSLSample([], 0.0);

  bool get isEmpty => data.isEmpty;
  bool get isNotEmpty => data.isNotEmpty;

  /// Access data by index
  dynamic operator [](int index) => data[index];

  /// Get data length
  int get length => data.length;
}

/// Utility class for creating mock test scenarios
class MockLSLTestScenario {
  final List<MockLSLOutlet> outlets = [];
  final List<MockLSLInlet> inlets = [];

  /// Create a producer-consumer scenario
  static Future<MockLSLTestScenario> createProducerConsumer({
    required String streamName,
    required int producerCount,
    required int consumerCount,
    LSLChannelFormat channelFormat = LSLChannelFormat.int32,
    int channelCount = 1,
  }) async {
    final scenario = MockLSLTestScenario();
    
    // Create producers (outlets)
    for (int i = 0; i < producerCount; i++) {
      final streamInfo = MockLSLStreamInfo(
        streamName: streamName,
        streamType: 'test',
        channelCount: channelCount,
        sampleRate: 100.0,
        channelFormat: channelFormat,
        sourceId: 'producer_$i',
      );
      
      final outlet = MockLSL.createOutlet(streamInfo);
      await outlet.create();
      scenario.outlets.add(outlet);
    }
    
    // Create consumers (inlets)
    for (int i = 0; i < consumerCount; i++) {
      // Consumers typically connect to existing streams
      final streamInfo = MockLSLStreamInfo(
        streamName: streamName,
        streamType: 'test',
        channelCount: channelCount,
        sampleRate: 100.0,
        channelFormat: channelFormat,
        sourceId: 'consumer_$i',
      );
      
      final inlet = MockLSL.createInlet(streamInfo);
      await inlet.create();
      scenario.inlets.add(inlet);
    }
    
    return scenario;
  }

  /// Send test data from all producers
  void sendTestData() {
    for (int i = 0; i < outlets.length; i++) {
      final outlet = outlets[i];
      outlet.pushSample([i * 100 + math.Random().nextInt(100)]);
    }
  }

  /// Dispose all resources
  Future<void> dispose() async {
    for (final outlet in outlets) {
      await outlet.destroy();
    }
    for (final inlet in inlets) {
      await inlet.destroy();
    }
    outlets.clear();
    inlets.clear();
  }
}