import 'dart:async';

import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/tests/ui_to_lsl_test.dart';
import 'package:liblsl_timing/src/tests/stream_latency_test.dart';
import 'package:liblsl_timing/src/tests/render_timing_test.dart';
import 'package:liblsl_timing/src/tests/sample_rate_stability_test.dart';
import 'package:liblsl_timing/src/tests/clock_sync_test.dart';

/// Interface for all timing tests
abstract class TimingTest {
  String get name;
  String get description;

  Future<void> runTest(
    TimingManager timingManager,
    TestConfiguration config, {
    Completer<void>? completer,
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

    try {
      await runTest(timingManager, config, completer: completer);
      if (!completer.isCompleted) {
        completer.complete();
      }
    } catch (e) {
      print('Error during test: $e');
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    // Cancel the timeout if the test completes successfully
    // or if an error occurs
    testTimeout.cancel();
  }
}

/// Registry of all available timing tests
class TestRegistry {
  static final List<TimingTest> _tests = [
    UIToLSLTest(),
    StreamLatencyTest(),
    RenderTimingTest(),
    SampleRateStabilityTest(),
    ClockSyncTest(),
  ];

  static List<TimingTest> get availableTests => List.unmodifiable(_tests);

  static TimingTest? getTest(String name) {
    try {
      return _tests.firstWhere((test) => test.name == name);
    } catch (e) {
      return null;
    }
  }
}
