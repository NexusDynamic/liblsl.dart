// lib/src/tests/base_test.dart
import 'dart:async';
import '../config/app_config.dart';
import '../data/timing_manager.dart';

abstract class BaseTest {
  final AppConfig config;
  final TimingManager timingManager;

  BaseTest(this.config, this.timingManager);

  /// Test type name
  String get name;

  /// Test description
  String get description;

  /// Initialize test resources
  Future<void> setup();

  /// Run the test
  Future<void> run();

  /// Clean up resources
  Future<void> cleanup();

  /// Run the test with a timeout
  Future<void> runWithTimeout() async {
    // Reset timing manager
    timingManager.reset();

    try {
      // Set up resources
      await setup();

      // Set up timeout
      final completer = Completer<void>();
      final timeout = Timer(Duration(seconds: config.testDurationSeconds), () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      // Run the test and wait for completion or timeout
      unawaited(run());
      await completer.future;

      // Cancel the timeout
      timeout.cancel();
    } finally {
      // Clean up
      await cleanup();
    }

    // Calculate metrics
    timingManager.calculateMetrics();
  }
}

// Helper function to avoid 'unawaited Future' warning
void unawaited(Future<void> future) {}
