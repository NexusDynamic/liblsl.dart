import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

class TestCoordinator {
  final TestConfiguration config;
  final TimingManager timingManager;
  LSLStreamInfo? _controlStreamInfo;
  LSLIsolatedOutlet? _controlOutlet;
  LSLIsolatedInlet? _controlInlet;
  bool _isCoordinator = false;
  bool _isInitialized = false;
  bool _isReady = false;
  final List<String> _connectedDevices = [];
  final StreamController<String> _messageStreamController =
      StreamController<String>.broadcast();

  Stream<String> get messageStream => _messageStreamController.stream;
  bool get isCoordinator => _isCoordinator;
  List<String> get connectedDevices => List.unmodifiable(_connectedDevices);
  bool get isReady => _isReady;
  bool get isInitialized => _isInitialized;

  TestCoordinator(this.config, this.timingManager);

  /// Initialize the coordinator and discover existing control streams
  Future<void> initialize() async {
    // Look for an existing control stream
    final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);

    final controlStreams = streams
        .where(
          (s) =>
              s.streamName == 'TestCoordination' &&
              s.streamType.value == 'Control',
        )
        .toList();

    if (controlStreams.isEmpty) {
      // No existing coordinator, become the coordinator
      _isCoordinator = true;
      await _setupCoordinator();
    } else {
      // Join existing coordination network
      await _joinCoordination(controlStreams.first);
    }

    // Start listening for coordination messages
    _startListening();
    _isInitialized = true;
  }

  Future<void> _setupCoordinator() async {
    // Create control stream
    _controlStreamInfo = await LSL.createStreamInfo(
      streamName: 'TestCoordination',
      streamType: LSLContentType.custom('Control'),
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: 'Coordinator_${config.sourceId}',
    );

    _controlOutlet = await LSL.createOutlet(
      streamInfo: _controlStreamInfo!,
      chunkSize: 0,
      maxBuffer: 360,
    );

    // Add self to connected devices
    _connectedDevices.add(config.sourceId);

    // Send coordinator announcement
    await _sendMessage('COORDINATOR:${config.sourceId}');
    _messageStreamController.add('You are the test coordinator');
  }

  Future<void> _joinCoordination(LSLStreamInfo controlStream) async {
    // Create inlet to the control stream
    _controlInlet = await LSL.createInlet<String>(
      streamInfo: controlStream,
      maxBufferSize: 360,
      maxChunkLength: 0,
      recover: true,
    );

    // Announce presence to coordinator
    _controlStreamInfo = await LSL.createStreamInfo(
      streamName: 'DeviceAnnounce',
      streamType: LSLContentType.custom('Control'),
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: config.sourceId,
    );

    _controlOutlet = await LSL.createOutlet(
      streamInfo: _controlStreamInfo!,
      chunkSize: 0,
      maxBuffer: 360,
    );

    // Send join message
    await _sendMessage('JOIN:${config.sourceId}');
    _messageStreamController.add('Joined test coordination network');
  }

  void _startListening() async {
    while (true) {
      try {
        final sample = await _controlInlet?.pullSample(timeout: 0.1);

        if (sample != null && sample.isNotEmpty) {
          final message = sample[0] as String;
          _handleMessage(message);
        }
      } catch (e) {
        print('Error in coordination message handling: $e');
      }

      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void _handleMessage(String message) {
    if (message.startsWith('COORDINATOR:')) {
      final coordinatorId = message.split(':')[1];
      _messageStreamController.add('Coordinator is $coordinatorId');
    } else if (message.startsWith('JOIN:')) {
      final deviceId = message.split(':')[1];
      if (!_connectedDevices.contains(deviceId)) {
        _connectedDevices.add(deviceId);
        _messageStreamController.add('Device $deviceId joined');

        // If coordinator, send current device list
        if (_isCoordinator) {
          _sendMessage('DEVICES:${_connectedDevices.join(',')}');
        }
      }
    } else if (message.startsWith('DEVICES:')) {
      final deviceList = message.split(':')[1].split(',');
      _connectedDevices.clear();
      _connectedDevices.addAll(deviceList);
      _messageStreamController.add(
        'Updated device list: ${deviceList.join(', ')}',
      );
    } else if (message.startsWith('READY:')) {
      final deviceId = message.split(':')[1];
      _messageStreamController.add('Device $deviceId is ready');

      // If coordinator, check if all devices are ready
      if (_isCoordinator && _allDevicesReady()) {
        _sendMessage('START:${DateTime.now().millisecondsSinceEpoch + 3000}');
        _messageStreamController.add(
          'All devices ready, starting test in 3 seconds',
        );
      }
    } else if (message.startsWith('START:')) {
      final startTimeMs = int.parse(message.split(':')[1]);
      final now = DateTime.now().millisecondsSinceEpoch;
      final delayMs = startTimeMs - now;

      if (delayMs > 0) {
        _messageStreamController.add('Test starting in ${delayMs}ms');
        Future.delayed(Duration(milliseconds: delayMs), () {
          _messageStreamController.add('TEST STARTED');
          _startTest();
        });
      } else {
        _messageStreamController.add('TEST STARTED (immediately)');
        _startTest();
      }
    }
  }

  bool _allDevicesReady() {
    // In a real implementation, you'd track ready status for each device
    return true;
  }

  void _startTest() {
    // Trigger test start
    timingManager.recordEvent(
      'coordinated_test_start',
      description:
          'Coordinated test start across ${_connectedDevices.length} devices',
      metadata: {'devices': _connectedDevices},
    );

    // Additional test start logic would go here
  }

  Future<void> _sendMessage(String message) async {
    await _controlOutlet?.pushSample([message]);
  }

  /// Signal that this device is ready to start the test
  Future<void> signalReady() async {
    _isReady = true;
    await _sendMessage('READY:${config.sourceId}');
    _messageStreamController.add('Signaled ready');
  }

  /// For coordinators: manually start the test
  Future<void> startTest() async {
    if (!_isCoordinator) {
      throw Exception('Only the coordinator can manually start the test');
    }

    await _sendMessage('START:${DateTime.now().millisecondsSinceEpoch + 3000}');
    _messageStreamController.add('Starting test in 3 seconds');
  }

  void dispose() {
    _controlInlet?.destroy();
    _controlOutlet?.destroy();
    _controlStreamInfo?.destroy();
    _messageStreamController.close();
  }
}

class DeviceCoordinationPanel extends StatefulWidget {
  final TestConfiguration config;
  final TestCoordinator coordinator;
  final VoidCallback onStartTest;

  const DeviceCoordinationPanel({
    super.key,
    required this.config,
    required this.coordinator,
    required this.onStartTest,
  });

  @override
  State<DeviceCoordinationPanel> createState() =>
      _DeviceCoordinationPanelState();
}

class _DeviceCoordinationPanelState extends State<DeviceCoordinationPanel> {
  final List<String> _messages = [];
  bool _isReady = false;

  @override
  void initState() {
    super.initState();

    // Listen for coordinator messages
    widget.coordinator.messageStream.listen((message) {
      setState(() {
        _messages.add(message);

        // Auto-start test if message indicates it
        if (message == 'TEST STARTED' ||
            message == 'TEST STARTED (immediately)') {
          widget.onStartTest();
        }
      });
    });

    // Initialize the coordinator
    _initializeCoordinator();
  }

  Future<void> _initializeCoordinator() async {
    try {
      await widget.coordinator.initialize();
      setState(() {}); // Refresh UI
    } catch (e) {
      setState(() {
        _messages.add('Error initializing coordinator: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectedDevices = widget.coordinator.connectedDevices;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Coordination',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),

            // Coordinator status
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.coordinator.isCoordinator
                    ? Colors.green.withAlpha(25)
                    : Colors.blue.withAlpha(25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.coordinator.isCoordinator
                        ? Icons.hub
                        : Icons.device_hub,
                    color: widget.coordinator.isCoordinator
                        ? Colors.green
                        : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.coordinator.isCoordinator
                        ? 'Coordinator (${widget.config.sourceId})'
                        : 'Participant (${widget.config.sourceId})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.coordinator.isCoordinator
                          ? Colors.green
                          : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Connected devices
            Text(
              'Connected Devices (${connectedDevices.length}):',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: connectedDevices
                  .map(
                    (device) => Chip(
                      label: Text(device),
                      backgroundColor: device == widget.config.sourceId
                          ? Colors.green.withAlpha(25)
                          : Colors.grey.withAlpha(25),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),

            // Coordination messages
            Text(
              'Coordination Messages:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withAlpha(75)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 8,
                    ),
                    child: Text(
                      _messages[index],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isReady
                      ? null
                      : () {
                          setState(() {
                            _isReady = true;
                          });
                          widget.coordinator.signalReady();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_isReady ? 'Ready' : 'Signal Ready'),
                ),
                const SizedBox(width: 12),
                if (widget.coordinator.isCoordinator)
                  ElevatedButton(
                    onPressed: () {
                      widget.coordinator.startTest();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Start Test'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
