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
  LSLOutlet? _controlOutlet;
  LSLInlet? _controlInlet;
  double _controllerLatency = double.nan;
  final List<LSLInlet> _participantInlets = [];
  String _coordinatorId = '';
  // Coordination state
  bool _isCoordinator = false;
  bool _isInitialized = false;
  bool _isReady = false;
  bool _isTestRunning = false;
  bool _testStarted = false;

  final List<String> _connectedDevices = [];
  final List<bool> _readyDevices = [];

  // Stream controller for messages
  final StreamController<String> _messageStreamController =
      StreamController<String>.broadcast();

  // Public getters
  bool get isTestRunning => _isTestRunning;
  bool get testStarted => _testStarted;
  bool get isCoordinator => _isCoordinator;
  bool get isInitialized => _isInitialized;
  bool get isReady => _isReady;
  String get coordinatorId => _coordinatorId;
  List<String> get connectedDevices => List.unmodifiable(_connectedDevices);
  List<bool> get readyDevices => List.unmodifiable(_readyDevices);
  double get controllerLatency => _controllerLatency;
  Stream<String> get messageStream => _messageStreamController.stream;

  Function(TestType)? _onNavigateToTest;

  DeviceCoordinator(this.config, this.timingManager);

  /// Initialize the coordinator and discover existing control streams
  Future<void> initialize() async {
    // Look for an existing control stream
    final streams = await LSL.resolveStreams(
      waitTime: config.streamMaxWaitTimeSeconds,
      maxStreams: config.streamMaxStreams,
    );

    final controlStreams = streams
        .where(
          (s) =>
              s.streamName == StreamDefaults.controlStreamName &&
              s.streamType == LSLContentType.markers &&
              s.sourceId != 'Coordinator_${config.deviceId}' &&
              !s.sourceId.startsWith('Participant_'),
        )
        .toList();
    if (kDebugMode) {
      print(controlStreams);
    }
    if (controlStreams.isEmpty) {
      // No existing coordinator, become the coordinator
      _isCoordinator = true;
      _coordinatorId = config.deviceId;
      await _setupCoordinator();
    } else {
      // Join existing coordination network
      _isCoordinator = false;
      _coordinatorId = controlStreams.first.sourceId.replaceFirst(
        'Coordinator_',
        '',
      );
      await _joinCoordination(controlStreams.first);
    }
    _isInitialized = true;
    // Start listening for coordination messages
    unawaited(_startListening());

    timingManager.recordEvent(
      EventType.coordination,
      description: _isCoordinator
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
      chunkSize: 1,
      maxBuffer: 5,
    );

    // Add self to connected devices
    _connectedDevices.add(config.deviceId);
    _readyDevices.add(false);

    // Send coordinator announcement
    unawaited(_startBroadcasting());

    _messageStreamController.add('You are the test coordinator');
  }

  Future<void> _sendDiscoveryMessage() async {
    await _sendMessage(
      _isCoordinator
          ? CoordinationMessageType.discovery
          : CoordinationMessageType.join,
      {
        'deviceId': config.deviceId,
        'deviceName': config.deviceName,
        'isCoordinator': _isCoordinator,
      },
    );
  }

  Future<void> _findParticipantStreams() async {
    // Look for participant streams
    final streams = await LSL.resolveStreams(
      waitTime: 1,
      maxStreams: config.streamMaxStreams,
    );
    if (streams.isEmpty) {
      if (kDebugMode) {
        print('No participant streams found');
      }
      return;
    }

    // Filter for participant streams
    final foundParticipantInlets = streams.where(
      (s) =>
          s.streamName == StreamDefaults.controlStreamName &&
          !s.sourceId.startsWith('Coordinator_'),
    );
    if (foundParticipantInlets.isNotEmpty) {
      // Check if we already have inlets for these streams
      for (final stream in foundParticipantInlets) {
        if (_participantInlets.any(
          (inlet) => inlet.streamInfo.sourceId == stream.sourceId,
        )) {
          continue;
        }
        if (kDebugMode) {
          print('Found new participant stream: ${stream.sourceId}');
        }
        // Create inlet for each participant stream
        final inlet = await LSL.createInlet(
          streamInfo: stream,
          maxBuffer: 5,
          chunkSize: 1,
          recover: true,
        );
        _participantInlets.add(inlet);
      }
    }
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
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isInitialized || _isTestRunning) {
        timer.cancel();
        return;
      }
      if (_isCoordinator) {
        await _findParticipantStreams();
      }
      await _sendDiscoveryMessage();
    });

    _messageStreamController.add('Broadcasting discovery message');
  }

  Future<void> _inletLatency() async {
    if (_controlInlet == null) {
      throw Exception('Control inlet not initialized');
    }
    // get the latency, timeout 200ms (this should be way more than enough
    // on any WiFi / Ethernet lan)
    _controllerLatency = await _controlInlet!.getTimeCorrection(timeout: 0.2);
    if (kDebugMode) {
      print('Inlet latency: $_controllerLatency seconds');
    }
    _messageStreamController.add(
      'Inlet latency: ${(_controllerLatency * 1000).toStringAsFixed(3)} ms',
    );
  }

  Future<void> _joinCoordination(LSLStreamInfo controlStream) async {
    // Create inlet to the control stream
    _controlInlet = await LSL.createInlet<String>(
      streamInfo: controlStream,
      maxBuffer: 5,
      chunkSize: 1,
      recover: true,
    );

    // Create outlet for sending messages
    _controlStreamInfo = await LSL.createStreamInfo(
      streamName: StreamDefaults.controlStreamName,
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: 'Participant_${config.deviceId}',
    );

    _controlOutlet = await LSL.createOutlet(
      streamInfo: _controlStreamInfo!,
      chunkSize: 1,
      maxBuffer: 5,
    );

    // Send join message
    _startBroadcasting();

    _messageStreamController.add('Joined test coordination network');
  }

  Future<void> _startListening() async {
    int pullCount = 0;
    while (_isInitialized && !_messageStreamController.isClosed) {
      // Don't listen for messages if the test is running
      if (!_isTestRunning) {
        try {
          if (!_isCoordinator) {
            final sample = await _controlInlet?.pullSample();

            if (sample != null && sample.isNotEmpty) {
              final message = sample[0] as String;
              _handleMessage(message);
            }
            pullCount++;
            if (pullCount % 20 == 0) {
              // Check inlet latency every 10 pulls
              _inletLatency();
              pullCount = 0;
            }
          } else {
            // Listen for messages from participant inlets
            for (final LSLInlet inlet in List.unmodifiable(
              _participantInlets,
            )) {
              final sample = await inlet.pullSample();
              if (sample.isNotEmpty) {
                final message = sample[0] as String;
                _handleMessage(message);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error in coordination message handling: $e');
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 50));
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
    return;
  }

  void _handleJoinMessage(Map<String, dynamic> payload) async {
    if (!_isCoordinator) return;
    final deviceId = payload['deviceId'] as String?;
    final deviceName = payload['deviceName'] as String?;

    if (deviceId == null || deviceName == null) return;

    if (!_connectedDevices.contains(deviceId)) {
      _connectedDevices.add(deviceId);
      _readyDevices.add(false);
      final notification = 'Device $deviceName ($deviceId) joined';
      _messageStreamController.add(notification);

      timingManager.recordEvent(
        EventType.coordination,
        description: notification,
      );

      // Send the updated device list to participants.
      await _sendMessage(CoordinationMessageType.deviceList, {
        'devices': _connectedDevices,
        'readyDevices': _readyDevices,
      });
    }
  }

  void _handleDeviceListMessage(Map<String, dynamic> payload) {
    if (_isCoordinator) return;
    final devices = payload['devices'] as List<dynamic>?;
    final readyDevices = payload['readyDevices'] as List<dynamic>?;

    if (kDebugMode) {
      print('Received device list: $devices');
    }
    if (devices == null) return;

    _connectedDevices.clear();
    _connectedDevices.addAll(devices.cast<String>());

    if (readyDevices != null) {
      _readyDevices.clear();
      _readyDevices.addAll(readyDevices.cast<bool>());
    }

    final notification = 'Updated device list: ${_connectedDevices.join(', ')}';
    _messageStreamController.add(notification);
  }

  void _handleReadyMessage(Map<String, dynamic> payload) async {
    if (!_isCoordinator) return;
    final deviceId = payload['deviceId'] as String?;
    final deviceName = payload['deviceName'] as String?;

    if (deviceId == null || deviceName == null) return;

    // Mark the device as ready
    final index = _connectedDevices.indexOf(deviceId);
    if (index != -1) {
      _readyDevices[index] = true;
    }

    final notification = 'Device $deviceName ($deviceId) is ready';
    _messageStreamController.add(notification);
    // Send the updated device list to participants.
    await _sendMessage(CoordinationMessageType.deviceList, {
      'devices': _connectedDevices,
      'readyDevices': _readyDevices,
    });

    // If coordinator, check if all devices are ready
    if (_isCoordinator && _allDevicesReady()) {
      _messageStreamController.add(
        'All devices ready, starting test in 5 seconds',
      );

      // Schedule test start
      Future.delayed(const Duration(seconds: 3), () async {
        final testStartTime = DateTime.now().millisecondsSinceEpoch + 2000;
        _readyDevices.fillRange(0, _connectedDevices.length, false);
        await _sendMessage(CoordinationMessageType.deviceList, {
          'devices': _connectedDevices,
          'readyDevices': _readyDevices,
        });
        _sendMessage(CoordinationMessageType.startTest, {
          'testType': TestType.latency.index,
          'startTimeMs': testStartTime,
          'testConfig': config.toMap(),
        });
        _handleStartTestMessage({
          'testType': TestType.latency.index,
          'startTimeMs': testStartTime,
          'testConfig': config.toMap(),
        });
      });
    }
  }

  bool _allDevicesReady() {
    // Check if all devices are ready (excluding the coordinator)
    return _connectedDevices.length - 1 == _readyDevices.where((r) => r).length;
  }

  void _handleStartTestMessage(Map<String, dynamic> payload) {
    final testTypeIndex = payload['testType'] as int?;
    final startTimeMs = payload['startTimeMs'] as int?;
    final testConfig = payload['testConfig'] as Map<String, dynamic>?;

    if (testTypeIndex == null || startTimeMs == null) return;
    _isReady = false;

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

  void _startTest(TestType testType, Map<String, dynamic>? testConfig) async {
    final notification = 'TEST STARTED: ${testType.displayName}';
    _testStarted = true;
    _messageStreamController.add(notification);

    timingManager.recordEvent(
      EventType.coordination,
      description: notification,
      metadata: {'testType': testType.toString(), 'config': testConfig},
    );
    _isTestRunning = true;
    // Test started event - this will be picked up by the TestController
    _onTestStart?.call(testType, testConfig);

    // Navigate to test page if callback is set
    _onNavigateToTest?.call(testType);
  }

  void _handleStopTestMessage(Map<String, dynamic> payload) async {
    final testTypeIndex = payload['testType'] as int?;

    if (testTypeIndex == null) return;
    _isTestRunning = false;
    _testStarted = false;

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
    _isReady = false;
    _readyDevices.fillRange(0, _connectedDevices.length, false);
    await _sendMessage(CoordinationMessageType.deviceList, {
      'devices': _connectedDevices,
      'readyDevices': _readyDevices,
    });

    final startTimeMs = DateTime.now().millisecondsSinceEpoch + 3000;

    await _sendMessage(CoordinationMessageType.startTest, {
      'testType': testType.index,
      'startTimeMs': startTimeMs,
      'testConfig': config.toMap(),
    });
    _isTestRunning = true;
    _messageStreamController.add('Starting test in 3 seconds');
    _handleStartTestMessage({
      'testType': testType.index,
      'startTimeMs': startTimeMs,
      'testConfig': config.toMap(),
    });
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

  void testCompleted(TestType testType) {
    _isTestRunning = false;
    _testStarted = false;
    _isReady = false;
    _messageStreamController.add('Test completed: ${testType.displayName}');
    timingManager.recordEvent(
      EventType.testCompleted,
      description: 'Test completed: ${testType.displayName}',
      metadata: {'testType': testType.toString()},
    );
    _startBroadcasting();
    _startListening();
    _onTestStop?.call(testType);
  }

  /// Dispose resources
  void dispose() {
    _isInitialized = false;
    _controlInlet?.destroy();
    _controlOutlet?.destroy();
    _controlStreamInfo?.destroy();
    for (var inlet in _participantInlets) {
      inlet.destroy();
    }

    if (!_messageStreamController.isClosed) {
      _messageStreamController.close();
    }
  }
}
