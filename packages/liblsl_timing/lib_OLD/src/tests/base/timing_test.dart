import 'dart:async';

import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

/// Interface for all timing tests
abstract class TimingTest {
  String get name;
  String get description;

  Future<void> runTest(
    TimingManager timingManager,
    TestConfiguration config, {
    Completer<void> completer,
  });

  // Optional methods for test-specific configuration
  Map<String, dynamic>? get testSpecificConfig => null;
  void setTestSpecificConfig(Map<String, dynamic> config) {}

  Future<void> runTestWithTimeout(
    TimingManager timingManager,
    TestConfiguration config, {
    Completer<void>? completer,
  }) async {
    // If a completer is not provided, create one
    completer ??= Completer<void>();
    final testTimeout = Timer(
      Duration(seconds: config.testDurationSeconds + 10),
      () {
        print(
          'Test timed out after ${config.testDurationSeconds + 10} seconds',
        );
        if (!completer!.isCompleted) {
          completer.complete();
        }
      },
    );

    await runTest(timingManager, config, completer: completer);

    // Cancel the timeout if the test completes successfully
    // or if an error occurs
    testTimeout.cancel();
  }
}

abstract class BaseTimingTest extends TimingTest {
  @override
  Future<void> runTest(
    TimingManager timingManager,
    TestConfiguration config, {
    Completer<void>? completer,
  }) async {
    // Reset timing manager at start
    timingManager.reset();

    // Complete when test is done
    completer ??= Completer<void>();

    try {
      // Set up resources
      await setupTestResources(timingManager, config);

      // Run the actual test implementation
      await runTestImplementation(timingManager, config, completer);
    } catch (e) {
      print('Error during test: $e');
      timingManager.recordEvent('test_error', description: e.toString());
    } finally {
      // Clean up resources
      await cleanupTestResources();

      // Ensure completer is completed
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    // Calculate metrics
    timingManager.calculateMetrics();
  }

  // These methods should be implemented by concrete test classes
  Future<void> setupTestResources(
    TimingManager timingManager,
    TestConfiguration config,
  );
  Future<void> runTestImplementation(
    TimingManager timingManager,
    TestConfiguration config,
    Completer<void> completer,
  );
  Future<void> cleanupTestResources();
}

mixin class UITest {}
