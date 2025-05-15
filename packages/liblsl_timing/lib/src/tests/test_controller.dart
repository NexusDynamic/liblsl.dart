// lib/src/tests/test_controller.dart
import 'dart:async';
import '../config/constants.dart';
import '../config/app_config.dart';
import '../data/timing_manager.dart';
import '../coordination/device_coordinator.dart';
import 'base_test.dart';
import 'latency_test.dart';
import 'sync_test.dart';

class TestController {
  final AppConfig config;
  final TimingManager timingManager;
  final DeviceCoordinator coordinator;

  BaseTest? _currentTest;
  bool _isTestRunning = false;

  final StreamController<String> _statusStreamController =
      StreamController<String>.broadcast();

  Stream<String> get statusStream => _statusStreamController.stream;
  bool get isTestRunning => _isTestRunning;

  TestController({
    required this.config,
    required this.timingManager,
    required this.coordinator,
  }) {
    _setupCoordinationHandlers();
  }

  void _setupCoordinationHandlers() {
    coordinator.onTestStart((testType, testConfig) {
      startTest(testType, testConfig: testConfig);

      // Notify listeners that a test has started
      _statusStreamController.add('Test started: ${testType.displayName}');
    });

    coordinator.onTestStop((testType) {
      stopTest();
      _statusStreamController.add('Test stopped: ${testType.displayName}');
    });
  }

  Future<void> startTest(
    TestType testType, {
    Map<String, dynamic>? testConfig,
  }) async {
    if (_isTestRunning) {
      _statusStreamController.add('A test is already running');
      return;
    }

    _isTestRunning = true;

    // Create the appropriate test
    switch (testType) {
      case TestType.latency:
        _currentTest = LatencyTest(
          testConfig != null ? config.copyMerged(testConfig) : config,
          timingManager,
        );
        break;
      case TestType.synchronization:
        _currentTest = SynchronizationTest(
          testConfig != null ? config.copyMerged(testConfig) : config,
          timingManager,
        );
        break;
    }

    if (_currentTest == null) {
      _isTestRunning = false;
      _statusStreamController.add('Failed to create test');
      return;
    }

    _statusStreamController.add('Starting ${_currentTest!.name}...');

    try {
      // Run the test with timeout
      await _currentTest!.runWithTimeout();
      _statusStreamController.add('Test completed');
    } catch (e) {
      _statusStreamController.add('Test error: $e');
    } finally {
      _isTestRunning = false;
      _currentTest = null;
    }
  }

  void stopTest() {
    if (!_isTestRunning || _currentTest == null) {
      return;
    }

    _statusStreamController.add('Stopping test...');
    _currentTest!.cleanup();
    _isTestRunning = false;
    _currentTest = null;
  }

  void dispose() {
    stopTest();
    if (!_statusStreamController.isClosed) {
      _statusStreamController.close();
    }
  }
}
