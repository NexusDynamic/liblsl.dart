import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/tests/base/timing_test.dart';

class UIToLSLTest extends BaseTimingTest {
  @override
  String get name => 'UI to LSL Latency';

  @override
  String get description =>
      'Measures latency from UI event to LSL timestamp, including touch events and button presses';

  @override
  Future<void> setupTestResources(
    TimingManager timingManager,
    TestConfiguration config,
  ) async {
    // Reset the timing manager
    timingManager.reset();
  }

  @override
  Future<void> runTestImplementation(
    TimingManager timingManager,
    TestConfiguration config,
    Completer<void> completer,
  ) async {
    await completer.future;
  }

  @override
  Future<void> cleanupTestResources() async {
    // No specific cleanup needed for this test
  }

  Widget createTestWidget({
    required TimingManager timingManager,
    required LSLIsolatedOutlet outlet,
    required int testDurationSeconds,
    required VoidCallback onTestComplete,
    required bool showTimingMarker,
    required double markerSize,
  }) {
    return UILatencyTestWidget(
      timingManager: timingManager,
      outlet: outlet,
      testDurationSeconds: testDurationSeconds,
      onTestComplete: onTestComplete,
      showTimingMarker: showTimingMarker,
      markerSize: markerSize,
    );
  }

  @override
  void setTestSpecificConfig(Map<String, dynamic> config) {}

  @override
  Map<String, dynamic>? get testSpecificConfig => throw UnimplementedError();
}

class UILatencyTestWidget extends StatefulWidget {
  final TimingManager timingManager;
  final LSLIsolatedOutlet outlet;
  final int testDurationSeconds;
  final VoidCallback onTestComplete;
  final bool showTimingMarker;
  final double markerSize;

  const UILatencyTestWidget({
    super.key,
    required this.timingManager,
    required this.outlet,
    required this.testDurationSeconds,
    required this.onTestComplete,
    this.showTimingMarker = true,
    this.markerSize = 50,
  });

  @override
  State<UILatencyTestWidget> createState() => _UILatencyTestWidgetState();
}

class _UILatencyTestWidgetState extends State<UILatencyTestWidget>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int _secondsRemaining = 0;
  bool _isTestRunning = false;
  bool _showMarker = false;

  // Used to track the number of taps for identification
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.testDurationSeconds;

    // Add a short delay before starting
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _isTestRunning = true;
      });

      _startTest();
    });
  }

  void _startTest() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsRemaining--;

        if (_secondsRemaining <= 0) {
          _timer.cancel();
          _isTestRunning = false;
          widget.onTestComplete();
        }
      });
    });
  }

  void _handleTap(PointerEvent event) {
    if (!_isTestRunning) return;

    _tapCount++;

    // Record the UI event
    widget.timingManager.recordUIEvent(
      'ui_event',
      event,
      description: 'Tap $_tapCount',
    );

    // Show the visual marker (if enabled)
    if (widget.showTimingMarker) {
      setState(() {
        _showMarker = true;
      });
      WidgetsBinding.instance.scheduleFrame();

      // Record the frame start time
      widget.timingManager.recordEvent(
        'frame_start',
        description: 'Start frame render for marker $_tapCount',
      );

      // Schedule turning off the marker after a short time
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _showMarker = false;
          });
          WidgetsBinding.instance.scheduleFrame();
        }
      });
    }

    widget.timingManager.recordEvent(
      'sample_created',
      description: 'Sample created for tap $_tapCount',
      metadata: {'tapCount': _tapCount},
    );

    // Push a sample to the LSL outlet
    widget.outlet.pushSample([_tapCount.toDouble()]).then((_) {
      widget.timingManager.recordEvent(
        'sample_sent',
        description: 'Sample sent for tap $_tapCount',
        metadata: {'tapCount': _tapCount},
      );

      // Record the LSL timestamp (equivalent to what would be used by LSL)
      widget.timingManager.recordTimestampedEvent(
        'lsl_timestamp',
        LSL.localClock(),
        description: 'LSL timestamp for tap $_tapCount',
        metadata: {'tapCount': _tapCount},
      );
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleTap,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Tap anywhere on the screen',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            Text(
              'Time remaining: $_secondsRemaining seconds',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Text(
              'Taps: $_tapCount',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 40),

            // Visual timing marker (for photodiode)
            if (widget.showTimingMarker)
              Container(
                width: widget.markerSize,
                height: widget.markerSize,
                color: _showMarker ? Colors.black : Colors.white,
              ),
          ],
        ),
      ),
    );
  }
}
