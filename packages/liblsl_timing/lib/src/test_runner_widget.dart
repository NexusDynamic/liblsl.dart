import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

class TestRunnerWidget extends StatefulWidget {
  final Widget testWidget;
  final String testName;
  final int timeoutSeconds;
  final VoidCallback onComplete;

  const TestRunnerWidget({
    super.key,
    required this.testWidget,
    required this.testName,
    required this.timeoutSeconds,
    required this.onComplete,
  });

  @override
  State<TestRunnerWidget> createState() => _TestRunnerWidgetState();
}

class _TestRunnerWidgetState extends State<TestRunnerWidget> {
  late Timer _timeoutTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.timeoutSeconds;

    // Set up countdown timer
    Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
      });
    });

    // Set up timeout
    _timeoutTimer = Timer(Duration(seconds: widget.timeoutSeconds), () {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _timeoutTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Status bar
        Container(
          color: Colors.blue.withAlpha(25),
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Running test: ${widget.testName}'),
              Text('Timeout in $_remainingSeconds seconds'),
            ],
          ),
        ),

        // Test widget
        Expanded(child: widget.testWidget),
      ],
    );
  }
}
