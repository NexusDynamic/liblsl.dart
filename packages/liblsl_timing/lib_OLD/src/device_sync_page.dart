import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/tests/base/test_coordinator.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

class DeviceSyncPage extends StatefulWidget {
  final TestConfiguration config;
  final TestCoordinator? coordinator; // Add this parameter

  const DeviceSyncPage({super.key, required this.config, this.coordinator});

  @override
  State<DeviceSyncPage> createState() => _DeviceSyncPageState();
}

class _DeviceSyncPageState extends State<DeviceSyncPage> {
  final List<LSLStreamInfo> _discoveredDevices = [];
  bool _isScanning = false;
  String _status = 'Ready to scan';
  Timer? _refreshTimer;
  TestCoordinator? _localCoordinator;

  @override
  void initState() {
    super.initState();
    _startPeriodicScan();

    // Initialize coordinator if not provided
    if (widget.coordinator == null) {
      _localCoordinator = TestCoordinator(widget.config, TimingManager());
      _localCoordinator!.initialize();
    }
  }

  TestCoordinator get coordinator => widget.coordinator ?? _localCoordinator!;

  void _startPeriodicScan() {
    // Scan for devices every 5 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _scanForDevices(),
    );

    // Initial scan
    _scanForDevices();
  }

  Future<void> _scanForDevices() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _status = 'Scanning for LSL devices...';
    });

    try {
      final streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 20);

      // Group streams by hostname
      final deviceMap = <String, List<LSLStreamInfo>>{};

      for (final stream in streams) {
        final hostname = stream.hostname ?? 'unknown';
        if (!deviceMap.containsKey(hostname)) {
          deviceMap[hostname] = [];
        }
        deviceMap[hostname]!.add(stream);
      }

      setState(() {
        _discoveredDevices.clear();
        _discoveredDevices.addAll(streams);
        _status =
            'Found ${streams.length} streams on ${deviceMap.length} devices';
      });
    } catch (e) {
      setState(() {
        _status = 'Error scanning: $e';
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _showStreamDetails(BuildContext context, LSLStreamInfo stream) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(stream.streamName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${stream.streamType.value}'),
            Text('Source ID: ${stream.sourceId}'),
            Text('Hostname: ${stream.hostname}'),
            Text('UID: ${stream.uid}'),
            Text('Channel count: ${stream.channelCount}'),
            Text('Channel format: ${stream.channelFormat}'),
            Text('Sample rate: ${stream.sampleRate} Hz'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group streams by hostname
    final deviceMap = <String, List<LSLStreamInfo>>{};

    for (final stream in _discoveredDevices) {
      final hostname = stream.hostname ?? 'unknown';
      if (!deviceMap.containsKey(hostname)) {
        deviceMap[hostname] = [];
      }
      deviceMap[hostname]!.add(stream);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Synchronization'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanForDevices,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status bar
          Container(
            color: Colors.blue.withAlpha(25),
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_status),
                if (_isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          // Device list
          Expanded(
            child: deviceMap.isEmpty
                ? const Center(
                    child: Text(
                      'No LSL devices found. Tap refresh to scan again.',
                    ),
                  )
                : ListView.builder(
                    itemCount: deviceMap.length,
                    itemBuilder: (context, index) {
                      final hostname = deviceMap.keys.elementAt(index);
                      final streams = deviceMap[hostname]!;

                      return ExpansionTile(
                        title: Text('Device: $hostname'),
                        subtitle: Text('${streams.length} streams'),
                        children: [
                          for (final stream in streams)
                            ListTile(
                              title: Text(stream.streamName),
                              subtitle: Text(
                                '${stream.streamType.value}, ${stream.channelCount} channels, ${stream.sampleRate} Hz',
                              ),
                              trailing: const Icon(Icons.info_outline),
                              onTap: () => _showStreamDetails(context, stream),
                            ),
                        ],
                      );
                    },
                  ),
          ),

          // Current device info with coordination status
          Container(
            color: Colors.green.withAlpha(25),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This Device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('ID: ${widget.config.sourceId}'),
                Text(
                  'Role: ${widget.config.isProducer ? 'Producer' : ''}${widget.config.isProducer && widget.config.isConsumer ? ' & ' : ''}${widget.config.isConsumer ? 'Consumer' : ''}',
                ),
                const SizedBox(height: 16),

                // Sync status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Clock synchronization:'),
                    Text(
                      widget.config.enableClockSync ? 'Enabled' : 'Disabled',
                      style: TextStyle(
                        color: widget.config.enableClockSync
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                // Show coordination status
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Coordination role:'),
                    Text(
                      coordinator.isInitialized
                          ? (coordinator.isCoordinator
                                ? 'Coordinator'
                                : 'Participant')
                          : 'Not initialized',
                      style: TextStyle(
                        color: coordinator.isInitialized
                            ? (coordinator.isCoordinator
                                  ? Colors.green
                                  : Colors.blue)
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                // Show connected devices
                if (coordinator.isInitialized &&
                    coordinator.connectedDevices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Connected devices: ${coordinator.connectedDevices.join(", ")}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startSyncTest,
        label: const Text('Run Sync Test'),
        icon: const Icon(Icons.sync),
      ),
    );
  }

  void _startSyncTest() {
    if (_discoveredDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No devices found for synchronization test'),
        ),
      );
      return;
    }

    // Signal readiness in the coordinator
    if (coordinator.isInitialized && !coordinator.isReady) {
      coordinator.signalReady();
    }

    // Navigate to the Enhanced Clock Sync test
    Navigator.pop(context, 'EnhancedClockSyncTest');
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    // Only dispose the local coordinator if we created it
    _localCoordinator?.dispose();
    super.dispose();
  }
}
