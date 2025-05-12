// lib/src/coordination/device_coordinator.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import '../config/constants.dart';
import '../config/app_config.dart';
import '../data/timing_manager.dart';

class DeviceCoordinator {
  final AppConfig config;
  final TimingManager timingManager;

  // LSL resources
  LSLStreamInfo? _controlStreamInfo;
  LSLIsolatedOutlet? _controlOutlet;
  LSLIsolatedInlet? _controlInlet;

  // Coordination state
  bool _isCoordinator = false;
  bool _isInitialized = false;
  bool _isReady = false;
  bool _isTestRunning = false;
  final List<String> _connectedDevices = [];

  // Stream controller for messages
  final StreamController<String> _messageStreamController =
      StreamController<String>.broadcast();

  // Public getters
  bool get isCoordinator => _isCoordinator;
  bool get isInitialized => _isInitialized;
  bool get isReady => _isReady;
  List<String> get connectedDevices => List.unmodifiable(_connectedDevices);
  Stream<String> get messageStream => _messageStreamController.stream;

  Function(TestType)? _onNavigateToTest;

  DeviceCoordinator(this.config, this.timingManager);

  /// Initialize the coordinator and discover existing control streams
  Future<void> initialize() async {
    // Look for an existing control stream
    final streams = await LSL.resolveStreams(waitTime: 10.0, maxStreams: 100);

    final controlStreams =
        streams
            .where(
              (s) =>
                  s.streamName == StreamDefaults.controlStreamName &&
                  s.streamType == LSLContentType.markers &&
                  s.sourceId != 'Coordinator_${config.deviceId}',
            )
            .toList();
    if (kDebugMode) {
      print(controlStreams);
    }
    if (controlStreams.isEmpty) {
      // No existing coordinator, become the coordinator
      _isCoordinator = true;
      await _setupCoordinator();
    } else {
      // Join existing coordination network
      await _joinCoordination(controlStreams.first);
    }

    // Start listening for coordination messages
    _startListening();
    _isInitialized = true;

    timingManager.recordEvent(
      EventType.testStarted,
      description:
          _isCoordinator
              ? 'Initialized as coordinator'
              : 'Joined coordination network',
      metadata: {'isCoordinator': _isCoordinator},
    );
  }

  /// Set callback for navigating to the test page
  void onNavigateToTest(Function(TestType) callback) {
    _onNavigateToTest = callback;
  }

  Future<void> _setupCoordinator() async {
    // Create control stream
    _controlStreamInfo = await LSL.createStreamInfo(
      streamName: StreamDefaults.controlStreamName,
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: 'Coordinator_${config.deviceId}',
    );

    _controlOutlet = await LSL.createOutlet(
      streamInfo: _controlStreamInfo!,
      chunkSize: 0,
      maxBuffer: 360,
    );

    // Add self to connected devices
    _connectedDevices.add(config.deviceId);

    // Send coordinator announcement
    _startBroadcasting();

    _messageStreamController.add('You are the test coordinator');
  }

  Future<void> _sendDiscoveryMessage(bool isCoordinator) async {
    await _sendMessage(CoordinationMessageType.discovery, {
      'deviceId': config.deviceId,
      'deviceName': config.deviceName,
      'isCoordinator': isCoordinator,
    });
  }

  Future<void> _startBroadcasting() async {
    if (_controlOutlet == null) {
      throw Exception('Control outlet not initialized');
    }
    if (kDebugMode) {
      print('Starting broadcast');
    }
    _isTestRunning = false;

    // Broadcast discovery message every 1 second
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isInitialized || _isTestRunning) {
        timer.cancel();
        return;
      }

      _sendDiscoveryMessage(true);
    });

    _messageStreamController.add('Broadcasting discovery message');
  }

  Future<void> _joinCoordination(LSLStreamInfo controlStream) async {
    // Create inlet to the control stream
    _controlInlet = await LSL.createInlet<String>(
      streamInfo: controlStream,
      maxBufferSize: 360,
      maxChunkLength: 0,
      recover: true,
    );

    // Create outlet for sending messages
    _controlStreamInfo = await LSL.createStreamInfo(
      streamName: 'DeviceMessage',
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: config.deviceId,
    );

    _controlOutlet = await LSL.createOutlet(
      streamInfo: _controlStreamInfo!,
      chunkSize: 0,
      maxBuffer: 360,
    );

    // Send join message
    await _sendDiscoveryMessage(false);

    _messageStreamController.add('Joined test coordination network');
  }

  void _startListening() async {
    while (_isInitialized && !_messageStreamController.isClosed) {
      try {
        final sample = await _controlInlet?.pullSample(timeout: 0.1);

        if (sample != null && sample.isNotEmpty) {
          final message = sample[0] as String;
          _handleMessage(message);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error in coordination message handling: $e');
        }
      }

      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void _handleMessage(String message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message);

      final messageType = CoordinationMessageType.values[data['type'] as int];
      final payload = data['payload'] as Map<String, dynamic>?;

      if (payload == null) return;

      switch (messageType) {
        case CoordinationMessageType.discovery:
          _handleDiscoveryMessage(payload);
          break;
        case CoordinationMessageType.join:
          _handleJoinMessage(payload);
          break;
        case CoordinationMessageType.deviceList:
          _handleDeviceListMessage(payload);
          break;
        case CoordinationMessageType.ready:
          _handleReadyMessage(payload);
          break;
        case CoordinationMessageType.startTest:
          _handleStartTestMessage(payload);
          break;
        case CoordinationMessageType.stopTest:
          _handleStopTestMessage(payload);
          break;
        case CoordinationMessageType.testResult:
          _handleTestResultMessage(payload);
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing message: $e');
      }
    }
  }

  void _handleDiscoveryMessage(Map<String, dynamic> payload) {
    final deviceId = payload['deviceId'] as String?;
    final deviceName = payload['deviceName'] as String?;
    //final isMessageCoordinator = payload['isCoordinator'] as bool? ?? false;

    if (deviceId == null || deviceName == null) return;

    if (!_connectedDevices.contains(deviceId)) {
      _connectedDevices.add(deviceId);
      final notification = 'Device $deviceName ($deviceId) discovered';
      _messageStreamController.add(notification);

      timingManager.recordEvent(
        EventType.testStarted,
        description: notification,
        metadata: {'deviceId': deviceId, 'deviceName': deviceName},
      );
    }

    // If we're the coordinator, send the current device list
    if (_isCoordinator) {
      _sendMessage(CoordinationMessageType.deviceList, {
        'devices': _connectedDevices,
      });
    }
  }

  void _handleJoinMessage(Map<String, dynamic> payload) {
    final deviceId = payload['deviceId'] as String?;
    final deviceName = payload['deviceName'] as String?;

    if (deviceId == null || deviceName == null) return;

    if (!_connectedDevices.contains(deviceId)) {
      _connectedDevices.add(deviceId);
      final notification = 'Device $deviceName ($deviceId) joined';
      _messageStreamController.add(notification);

      timingManager.recordEvent(
        EventType.testStarted,
        description: notification,
        metadata: {'deviceId': deviceId, 'deviceName': deviceName},
      );

      // If we're the coordinator, send the updated device list
      if (_isCoordinator) {
        _sendMessage(CoordinationMessageType.deviceList, {
          'devices': _connectedDevices,
        });
      }
    }
  }

  void _handleDeviceListMessage(Map<String, dynamic> payload) {
    final devices = payload['devices'] as List<dynamic>?;

    if (devices == null) return;

    _connectedDevices.clear();
    _connectedDevices.addAll(devices.cast<String>());

    final notification = 'Updated device list: ${_connectedDevices.join(', ')}';
    _messageStreamController.add(notification);
  }

  void _handleReadyMessage(Map<String, dynamic> payload) {
    final deviceId = payload['deviceId'] as String?;
    final deviceName = payload['deviceName'] as String?;

    if (deviceId == null || deviceName == null) return;

    final notification = 'Device $deviceName ($deviceId) is ready';
    _messageStreamController.add(notification);

    // If coordinator, check if all devices are ready
    if (_isCoordinator && _allDevicesReady()) {
      _messageStreamController.add(
        'All devices ready, starting test in 3 seconds',
      );

      // Schedule test start
      Future.delayed(const Duration(seconds: 3), () {
        final testStartTime = DateTime.now().millisecondsSinceEpoch + 1000;
        _sendMessage(CoordinationMessageType.startTest, {
          'testType': TestType.latency.index,
          'startTimeMs': testStartTime,
          'testConfig': {
            'durationSeconds': config.testDurationSeconds,
            'sampleRate': config.sampleRate,
          },
        });
      });
    }
  }

  bool _allDevicesReady() {
    // In a real implementation, track ready state for each device
    return true;
  }

  void _handleStartTestMessage(Map<String, dynamic> payload) {
    final testTypeIndex = payload['testType'] as int?;
    final startTimeMs = payload['startTimeMs'] as int?;
    final testConfig = payload['testConfig'] as Map<String, dynamic>?;

    if (testTypeIndex == null || startTimeMs == null) return;

    final testType = TestType.values[testTypeIndex];
    final now = DateTime.now().millisecondsSinceEpoch;
    final delayMs = startTimeMs - now;

    final notification =
        'Starting ${testType.displayName} in ${delayMs > 0 ? '$delayMs ms' : 'immediately'}';
    _messageStreamController.add(notification);
    _isTestRunning = true;
    // Schedule the test start
    if (delayMs > 0) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        _startTest(testType, testConfig);
      });
    } else {
      _startTest(testType, testConfig);
    }
  }

  void _startTest(TestType testType, Map<String, dynamic>? testConfig) {
    final notification = 'TEST STARTED: ${testType.displayName}';
    _messageStreamController.add(notification);

    timingManager.recordEvent(
      EventType.testStarted,
      description: notification,
      metadata: {'testType': testType.toString(), 'config': testConfig},
    );
    _isTestRunning = true;
    // Test started event - this will be picked up by the TestController
    _onTestStart?.call(testType, testConfig);

    // Navigate to test page if callback is set
    _onNavigateToTest?.call(testType);
  }

  void _handleStopTestMessage(Map<String, dynamic> payload) {
    final testTypeIndex = payload['testType'] as int?;

    if (testTypeIndex == null) return;

    final testType = TestType.values[testTypeIndex];

    final notification = 'TEST STOPPED: ${testType.displayName}';
    _messageStreamController.add(notification);

    timingManager.recordEvent(
      EventType.testCompleted,
      description: notification,
      metadata: {'testType': testType.toString()},
    );
    _startBroadcasting();
    // Test stopped event
    _onTestStop?.call(testType);
  }

  void _handleTestResultMessage(Map<String, dynamic> payload) {
    final deviceId = payload['deviceId'] as String?;
    final deviceName = payload['deviceName'] as String?;
    final resultSummary = payload['resultSummary'] as String?;

    if (deviceId == null || resultSummary == null) return;

    final notification =
        'Test results from ${deviceName ?? deviceId}: $resultSummary';
    _messageStreamController.add(notification);
  }

  /// Send a message to other devices
  Future<void> _sendMessage(
    CoordinationMessageType type,
    Map<String, dynamic> payload,
  ) async {
    if (_controlOutlet == null) {
      throw Exception('Control outlet not initialized');
    }

    final message = jsonEncode({'type': type.index, 'payload': payload});

    await _controlOutlet!.pushSample([message]);
  }

  /// Signal that this device is ready to start the test
  Future<void> signalReady() async {
    _isReady = true;
    await _sendMessage(CoordinationMessageType.ready, {
      'deviceId': config.deviceId,
      'deviceName': config.deviceName,
    });

    _messageStreamController.add('Signaled ready');
  }

  /// Start a test on all devices (coordinator only)
  Future<void> startTest(TestType testType) async {
    if (!_isCoordinator) {
      throw Exception('Only the coordinator can start tests');
    }

    final startTimeMs = DateTime.now().millisecondsSinceEpoch + 3000;

    await _sendMessage(CoordinationMessageType.startTest, {
      'testType': testType.index,
      'startTimeMs': startTimeMs,
      'testConfig': {
        'durationSeconds': config.testDurationSeconds,
        'sampleRate': config.sampleRate,
      },
    });
    _isTestRunning = true;
    _messageStreamController.add('Starting test in 3 seconds');
  }

  /// Send test results to other devices
  Future<void> shareTestResults(String resultSummary) async {
    await _sendMessage(CoordinationMessageType.testResult, {
      'deviceId': config.deviceId,
      'deviceName': config.deviceName,
      'resultSummary': resultSummary,
    });
  }

  // Callbacks for test events
  Function(TestType, Map<String, dynamic>?)? _onTestStart;
  Function(TestType)? _onTestStop;

  /// Set callback for test start event
  void onTestStart(Function(TestType, Map<String, dynamic>?) callback) {
    _onTestStart = callback;
  }

  /// Set callback for test stop event
  void onTestStop(Function(TestType) callback) {
    _onTestStop = callback;
  }

  /// Dispose resources
  void dispose() {
    _isInitialized = false;
    _controlInlet?.destroy();
    _controlOutlet?.destroy();
    _controlStreamInfo?.destroy();

    if (!_messageStreamController.isClosed) {
      _messageStreamController.close();
    }
  }
}
