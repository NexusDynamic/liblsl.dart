// lib/src/ui/test_page.dart
import 'package:flutter/material.dart';
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

class _TestPageState extends State<TestPage> {
  final List<String> _statusMessages = [];
  int _eventsCount = 0;
  bool _testCompleted = false;

  @override
  void initState() {
    super.initState();

    // Listen for test status updates
    widget.testController.statusStream.listen((message) {
      setState(() {
        _statusMessages.add(message);
        if (_statusMessages.length > 100) {
          _statusMessages.removeAt(0);
        }

        if (message.contains('completed') || message.contains('error')) {
          _testCompleted = true;
        }
      });
    });

    // Listen for timing events to update counter
    widget.timingManager.eventStream.listen((_) {
      setState(() {
        _eventsCount = widget.timingManager.events.length;
      });
    });

    // Start the test
    widget.testController.startTest(widget.testType);
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
    }
  }

  Widget _buildLatencyTestUI() {
    // Get most recent latency events
    final latencyEvents =
        widget.timingManager.events
            .where(
              (e) =>
                  e.eventType == EventType.sampleSent ||
                  e.eventType == EventType.sampleReceived,
            )
            .take(50)
            .toList();

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
          child:
              latencyEvents.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                    itemCount: latencyEvents.length,
                    itemBuilder: (context, index) {
                      final event = latencyEvents[index];
                      return ListTile(
                        leading: Icon(
                          event.eventType == EventType.sampleSent
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color:
                              event.eventType == EventType.sampleSent
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
    final syncEvents =
        widget.timingManager.events
            .where(
              (e) =>
                  e.eventType == EventType.clockCorrection ||
                  e.eventType == EventType.markerSent ||
                  e.eventType == EventType.markerReceived,
            )
            .take(50)
            .toList();

    // Collect device IDs with clock corrections
    final deviceIds = <String>{};
    for (final event in syncEvents) {
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
                  children:
                      deviceIds.map((deviceId) {
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
          child:
              syncEvents.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                    itemCount: syncEvents.length,
                    itemBuilder: (context, index) {
                      final event = syncEvents[index];
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
