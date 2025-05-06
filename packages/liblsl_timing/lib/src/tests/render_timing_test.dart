import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/tests/test_registry.dart';

class RenderTimingTest extends TimingTest {
  @override
  String get name => 'Render Timing Test';

  @override
  String get description =>
      'Measures the visual rendering latency using a timing marker (for photodiode)';

  @override
  Map<String, dynamic> get testSpecificConfig => {
    'flashDurationMs': 100,
    'intervalBetweenFlashesMs': 500,
    'flashCount': 50,
  };

  int _flashDurationMs = 100;
  int _intervalMs = 500;
  int _flashCount = 50;

  @override
  void setTestSpecificConfig(Map<String, dynamic> config) {
    _flashDurationMs = config['flashDurationMs'] ?? 100;
    _intervalMs = config['intervalBetweenFlashesMs'] ?? 500;
    _flashCount = config['flashCount'] ?? 50;
  }

  @override
  Future<void> runTest(
    TimingManager timingManager,
    TestConfiguration config, {
    Completer<void>? completer,
  }) async {
    timingManager.reset();

    // Complete when test is done
    completer ??= Completer<void>();

    // Create a BuildContext-independent widget to show
    final testWidget = MaterialApp(
      home: Scaffold(
        body: RenderTimingTestWidget(
          timingManager: timingManager,
          flashDurationMs: _flashDurationMs,
          intervalBetweenFlashesMs: _intervalMs,
          flashCount: _flashCount,
          markerSize: config.timingMarkerSizePixels,
          onTestComplete: () {
            completer!.complete();
          },
        ),
      ),
    );

    // The actual widget will be shown by the parent test runner
    try {
      // Test operations
      await completer.future;
    } catch (e) {
      print('Error during test: $e');
      // Record error in timing manager
      timingManager.recordEvent('test_error', description: e.toString());
    }

    // Calculate metrics
    timingManager.calculateMetrics();
  }
}

class RenderTimingTestWidget extends StatefulWidget {
  final TimingManager timingManager;
  final int flashDurationMs;
  final int intervalBetweenFlashesMs;
  final int flashCount;
  final double markerSize;
  final VoidCallback onTestComplete;

  const RenderTimingTestWidget({
    super.key,
    required this.timingManager,
    required this.flashDurationMs,
    required this.intervalBetweenFlashesMs,
    required this.flashCount,
    required this.markerSize,
    required this.onTestComplete,
  });

  @override
  State<RenderTimingTestWidget> createState() => _RenderTimingTestWidgetState();
}

class _RenderTimingTestWidgetState extends State<RenderTimingTestWidget>
    with SingleTickerProviderStateMixin {
  bool _showMarker = false;
  int _flashCounter = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();

    // Add a short delay before starting
    Future.delayed(const Duration(seconds: 1), _startTest);
  }

  void _startTest() {
    _flashCounter = 0;

    // Set up a periodic timer for the flashes
    _timer = Timer.periodic(
      Duration(milliseconds: widget.intervalBetweenFlashesMs),
      (timer) {
        _flashCounter++;

        if (_flashCounter > widget.flashCount) {
          // End the test
          _timer.cancel();
          widget.onTestComplete();
          return;
        }

        // Record intent to show marker
        widget.timingManager.recordEvent(
          'marker_trigger',
          description: 'Trigger flash $_flashCounter',
          metadata: {'flashId': _flashCounter},
        );

        // Schedule frame to show marker
        WidgetsBinding.instance.scheduleFrame();

        // Record immediately before setState
        widget.timingManager.recordEvent(
          'pre_setstate',
          description: 'Before setState for flash $_flashCounter',
          metadata: {'flashId': _flashCounter},
        );

        // Show the marker
        setState(() {
          _showMarker = true;
        });

        // Record after setState
        widget.timingManager.recordEvent(
          'post_setstate',
          description: 'After setState for flash $_flashCounter',
          metadata: {'flashId': _flashCounter},
        );

        // Schedule turning off the marker
        Future.delayed(Duration(milliseconds: widget.flashDurationMs), () {
          // Record before setState (off)
          widget.timingManager.recordEvent(
            'pre_setstate_off',
            description: 'Before setState (off) for flash $_flashCounter',
            metadata: {'flashId': _flashCounter},
          );

          if (mounted) {
            setState(() {
              _showMarker = false;
            });
          }

          // Record after setState (off)
          widget.timingManager.recordEvent(
            'post_setstate_off',
            description: 'After setState (off) for flash $_flashCounter',
            metadata: {'flashId': _flashCounter},
          );
        });
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Record the build function call
    widget.timingManager.recordEvent(
      'build_called',
      description:
          'Build called for flash $_flashCounter, marker: $_showMarker',
      metadata: {'flashId': _flashCounter, 'showMarker': _showMarker},
    );

    return Container(
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Render Timing Test',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          Text(
            'Flash count: $_flashCounter / ${widget.flashCount}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          Text(
            'The black square below will flash on and off.\nA photodiode can be used to measure the latency.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 40),

          // The marker for the photodiode
          LayoutBuilder(
            builder: (context, constraints) {
              // Record when the marker is built
              widget.timingManager.recordEvent(
                'marker_build',
                description:
                    'Marker built for flash $_flashCounter, visible: $_showMarker',
                metadata: {'flashId': _flashCounter, 'showMarker': _showMarker},
              );

              return Container(
                width: widget.markerSize,
                height: widget.markerSize,
                color: _showMarker ? Colors.black : Colors.white,
              );
            },
          ),

          // We use this widget to detect when the frame is actually rendered
          RepaintBoundary(
            child: CustomPaint(
              painter: _FrameTimingPainter(
                onPaint: () {
                  // This will be called when the frame is actually painted
                  widget.timingManager.recordEvent(
                    'frame_rendered',
                    description:
                        'Frame rendered for flash $_flashCounter, marker: $_showMarker',
                    metadata: {
                      'flashId': _flashCounter,
                      'showMarker': _showMarker,
                    },
                  );
                },
              ),
              size: const Size(1, 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameTimingPainter extends CustomPainter {
  final Function() onPaint;

  _FrameTimingPainter({required this.onPaint});

  @override
  void paint(Canvas canvas, Size size) {
    // Notify when paint is called
    onPaint();

    // We don't actually draw anything visible
    final paint = Paint()..color = Colors.transparent;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_FrameTimingPainter oldDelegate) => true;
}
