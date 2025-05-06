import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/tests/test_registry.dart';

class UIToLSLTest implements TimingTest {
  @override
  String get name => 'UI to LSL Latency';

  @override
  String get description =>
      'Measures latency from UI event to LSL timestamp, including touch events and button presses';

  @override
  Future<void> runTest(
    TimingManager timingManager,
    TestConfiguration config,
  ) async {
    timingManager.reset();

    // Create outlet with the specified configuration
    final streamInfo = await LSL.createStreamInfo(
      streamName: config.streamName,
      streamType: config.streamType,
      channelCount: config.channelCount,
      sampleRate: config.sampleRate,
      channelFormat: config.channelFormat,
      sourceId: config.sourceId,
    );

    final LSLIsolatedOutlet outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: 0,
      maxBuffer: 360,
    );

    // Will be set by the UI when a button is pressed
    final completer = Completer<void>();

    // Create a BuildContext-independent widget to show
    final testWidget = MaterialApp(
      home: Scaffold(
        body: UILatencyTestWidget(
          timingManager: timingManager,
          outlet: outlet,
          testDurationSeconds: config.testDurationSeconds,
          onTestComplete: () {
            completer.complete();
          },
          showTimingMarker: config.showTimingMarker,
          markerSize: config.timingMarkerSizePixels,
        ),
      ),
    );

    // The actual widget will be shown by the parent test runner

    // Wait for the test to complete
    await completer.future;

    // Clean up
    outlet.destroy();
    streamInfo.destroy();

    // Calculate timing metrics
    timingManager.calculateMetrics();
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
        }
      });
    }

    // Create and send the sample
    final currentTime = DateTime.now().microsecondsSinceEpoch / 1000000;
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
      child: Container(
        color: Colors.white,
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
