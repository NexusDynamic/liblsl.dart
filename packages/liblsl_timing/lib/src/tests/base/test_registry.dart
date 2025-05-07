import 'package:liblsl_timing/src/tests/base/timing_test.dart';
import 'package:liblsl_timing/src/tests/ui_to_lsl_test.dart';
import 'package:liblsl_timing/src/tests/stream_latency_test.dart';
import 'package:liblsl_timing/src/tests/render_timing_test.dart';
import 'package:liblsl_timing/src/tests/sample_rate_stability_test.dart';
import 'package:liblsl_timing/src/tests/clock_sync_test.dart';

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
