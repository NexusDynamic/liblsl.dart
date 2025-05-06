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

  Future<void> runTest(TimingManager timingManager, TestConfiguration config);

  // Optional methods for test-specific configuration
  Map<String, dynamic>? get testSpecificConfig => null;
  void setTestSpecificConfig(Map<String, dynamic> config) {}
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
