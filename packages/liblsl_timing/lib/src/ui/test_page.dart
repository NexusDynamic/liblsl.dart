// lib/src/ui/test_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liblsl_timing/src/tests/interactive_test.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/constants.dart';
import '../data/timing_manager.dart';
import '../tests/test_controller.dart';

class TestPage extends StatefulWidget {
  final TestType testType;
  final TestController testController;
  final TimingManager timingManager;

  const TestPage({
    super.key,
    required this.testType,
    required this.testController,
    required this.timingManager,
  });

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> with TickerProviderStateMixin {
  final List<String> _statusMessages = [];
  int _eventsCount = 0;
  bool _testCompleted = false;
  List<TimingEvent> _timingEventCache = [];
  int _eventsLastUpdated = 0;
  final Map<String, DateTime> _blackSquares = {};

  // Frame synchronization for photodiode square
  Ticker? _photodiodeTicker;
  bool _photodiodeSquareVisible = false;
  final bool _frameBasedMode = true; // Enable frame-based mode by default

  @override
  void initState() {
    super.initState();
    _eventsLastUpdated = 0;
    _timingEventCache = [];
    _testCompleted = false;
    _eventsCount = 0;
    _statusMessages.clear();

    // Listen for test status updates
    widget.testController.statusStream.listen((message) {
      if (mounted) {
        setState(() {
          _statusMessages.add(message);
          if (_statusMessages.length > 100) {
            _statusMessages.removeAt(0);
          }

          if (message.contains('completed') || message.contains('error')) {
            _testCompleted = true;
          }
        });
      }
    });

    // Listen for timing events to update counter
    widget.timingManager.eventStream.listen((EventType eventType) {
      if (mounted) {
        setState(() {
          _eventsCount++;
        });
      }
    });

    // Set up interactive test callback if needed
    if (widget.testType == TestType.interactive) {
      final test = widget.testController.currentTest;
      if (test is InteractiveTest) {
        // Pass the TickerProvider to the test after it's created
        test.tickerProvider = this;

        // Enable frame-based mode for reduced latency
        if (_frameBasedMode) {
          test.enableFrameBasedMode();
        }

        test.onMarkerReceived = (String deviceId) {
          if (_frameBasedMode) {
            // Frame-synchronized photodiode square update
            _showPhotodiodeSquareFrameSync();
          } else {
            // Traditional setState approach
            setState(() {
              _blackSquares[deviceId] = DateTime.now();
            });

            // Remove square after configured duration (20ms)
            Future.delayed(const Duration(milliseconds: 20), () {
              if (mounted) {
                setState(() {
                  _blackSquares.remove(deviceId);
                });
              }
            });
          }
        };
      }
    }

    // Ensure wakelock so the device doesn't sleep during the test,
    // this is safe to call multiple times.
    WakelockPlus.enable();
    // Start the test
    widget.testController.startTest(widget.testType);
  }

  @override
  void dispose() {
    _photodiodeTicker?.dispose();
    super.dispose();
  }

  /// Show photodiode square synchronized to frame refresh
  void _showPhotodiodeSquareFrameSync() {
    if (!mounted) return;

    // Stop any existing ticker to ensure clean state
    _photodiodeTicker?.dispose();
    _photodiodeTicker = null;

    // Reset square visibility state immediately
    setState(() {
      _photodiodeSquareVisible = true;
    });

    // Create ticker to hide after specified duration (20ms for ~1-2 frames at 60fps)
    _photodiodeTicker = createTicker((elapsed) {
      if (elapsed.inMilliseconds >= 20) {
        _photodiodeTicker?.dispose();
        _photodiodeTicker = null;
        if (mounted) {
          setState(() {
            _photodiodeSquareVisible = false;
          });
        }
      }
    });
    _photodiodeTicker?.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.testType.displayName),
        actions: [
          if (!_testCompleted)
            IconButton(icon: const Icon(Icons.stop), onPressed: _stopTest),
        ],
      ),
      body: Column(
        children: [
          // Test status indicator
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withAlpha(25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Test ${_testCompleted ? "Completed" : "Running"}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _testCompleted ? Colors.green : Colors.blue,
                  ),
                ),
                Text('Events recorded: $_eventsCount'),
              ],
            ),
          ),

          // Test-specific UI
          Expanded(child: _buildTestUI()),

          // Status messages
          Container(
            height: 150,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.withAlpha(76))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _statusMessages.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _statusMessages[index],
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Bottom controls
          if (_testCompleted)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTestUI() {
    switch (widget.testType) {
      case TestType.latency:
        return _buildLatencyTestUI();
      case TestType.synchronization:
        return _buildSyncTestUI();
      case TestType.interactive:
        return _buildInteractiveTestUI();
    }
  }

  Widget _buildInteractiveTestUI() {
    final bool renderSquare = _frameBasedMode
        ? _photodiodeSquareVisible
        : _blackSquares.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Interactive test for end-to-end timing measurements.\nPress the button to send markers.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),

        // Interactive button
        Expanded(
          child: Stack(
            children: [
              // Button in center
              Center(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _testCompleted ? null : _sendInteractiveMarker,
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        enableFeedback: !_testCompleted,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(40),
                        backgroundColor: Colors.blue,
                      ),
                      child: Text(
                        _testCompleted ? 'Wait' : 'PRESS',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Black squares for received markers
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: 100,
                  height: 100,
                  color: renderSquare ? Colors.black : Colors.transparent,
                  child: Center(
                    child: Text(
                      '',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Event counter
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey.withAlpha(51),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('Markers sent: ${_countEventType(EventType.markerSent)}'),
              Text(
                'Markers received: ${_countEventType(EventType.markerReceived)}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _sendInteractiveMarker(dynamic details) async {
    final test = widget.testController.currentTest;
    if (test is InteractiveTest) {
      if (_frameBasedMode) {
        // Send marker synchronized to next frame for minimal latency
        test.sendMarkerOnNextFrame();
      } else {
        // Send marker immediately
        test.sendMarker();
      }
      setState(() {
        _eventsCount++;
      });
    }
  }

  int _countEventType(EventType type) {
    return widget.timingManager.events.where((e) => e.eventType == type).length;
  }

  Widget _buildLatencyTestUI() {
    // Get most recent events if it has been more than 100ms since last update
    if (DateTime.now().millisecondsSinceEpoch - _eventsLastUpdated > 100) {
      _eventsLastUpdated = DateTime.now().millisecondsSinceEpoch;
      _timingEventCache = widget.timingManager.tailEvents(10).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Latency test measures the time between sending and receiving samples.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),

        // Show real-time latency indicators
        Expanded(
          child: _timingEventCache.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _timingEventCache.length,
                  itemBuilder: (context, index) {
                    final event = _timingEventCache[index];
                    return ListTile(
                      leading: Icon(
                        event.eventType == EventType.sampleSent
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        color: event.eventType == EventType.sampleSent
                            ? Colors.blue
                            : Colors.green,
                      ),
                      title: Text(
                        event.eventType.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(event.description ?? ''),
                      trailing: Text(
                        '${(event.timestamp % 10000).toStringAsFixed(3)}s',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSyncTestUI() {
    // Get most recent clock correction events
    _timingEventCache = widget.timingManager.tailEvents(10).toList();

    // Collect device IDs with clock corrections
    final deviceIds = <String>{};
    for (final event in _timingEventCache) {
      if (event.metadata?.containsKey('deviceId') == true) {
        deviceIds.add(event.metadata!['deviceId'] as String);
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Clock synchronization test measures time differences and drift between devices.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),

        // Show device sync status
        if (deviceIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Devices being synchronized:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 8,
                  children: deviceIds.map((deviceId) {
                    return Chip(
                      label: Text(deviceId),
                      backgroundColor: Colors.blue.withAlpha(51),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

        // Show sync events
        Expanded(
          child: _timingEventCache.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _timingEventCache.length,
                  itemBuilder: (context, index) {
                    final event = _timingEventCache[index];
                    IconData iconData;
                    Color iconColor;

                    switch (event.eventType) {
                      case EventType.clockCorrection:
                        iconData = Icons.sync;
                        iconColor = Colors.purple;
                        break;
                      case EventType.markerSent:
                        iconData = Icons.send;
                        iconColor = Colors.blue;
                        break;
                      case EventType.markerReceived:
                        iconData = Icons.download;
                        iconColor = Colors.green;
                        break;
                      default:
                        iconData = Icons.info;
                        iconColor = Colors.grey;
                    }

                    return ListTile(
                      leading: Icon(iconData, color: iconColor),
                      title: Text(
                        event.eventType.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        event.description ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${(event.timestamp % 10000).toStringAsFixed(3)}s',
                      ),
                      onTap: () => _showEventDetails(event),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showEventDetails(TimingEvent event) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(event.eventType.toString()),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Description: ${event.description ?? "N/A"}'),
                Text('Timestamp: ${event.timestamp}'),
                Text('LSL Clock: ${event.lslClock}'),
                const SizedBox(height: 8),
                const Text(
                  'Metadata:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (event.metadata != null)
                  ...event.metadata!.entries.map(
                    (e) => Text('${e.key}: ${e.value}'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _stopTest() {
    widget.testController.stopTest();
  }
}
