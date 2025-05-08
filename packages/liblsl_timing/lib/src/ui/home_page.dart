// lib/src/ui/home_page.dart
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/app_config.dart';
import '../coordination/device_coordinator.dart';
import '../data/timing_manager.dart';
import '../data/data_exporter.dart';
import '../tests/test_controller.dart';
import 'results_page.dart';

class HomePage extends StatefulWidget {
  final AppConfig config;
  final TimingManager timingManager;

  const HomePage({
    super.key,
    required this.config,
    required this.timingManager,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late DeviceCoordinator _coordinator;
  late TestController _testController;
  late DataExporter _dataExporter;

  List<String> _messages = [];
  List<String> _connectedDevices = [];
  bool _isInitializing = true;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _coordinator = DeviceCoordinator(widget.config, widget.timingManager);
    _testController = TestController(
      config: widget.config,
      timingManager: widget.timingManager,
      coordinator: _coordinator,
    );
    _dataExporter = DataExporter(widget.timingManager);

    _initialize();
  }

  Future<void> _initialize() async {
    // Calibrate time base
    await widget.timingManager.calibrateTimeBase();

    // Initialize device coordinator
    await _coordinator.initialize();

    // Listen for coordinator messages
    _coordinator.messageStream.listen((message) {
      setState(() {
        _messages.add(message);
        if (_messages.length > 100) {
          _messages.removeAt(0);
        }
      });
    });

    // Listen for test status updates
    _testController.statusStream.listen((status) {
      setState(() {
        _messages.add(status);
        if (_messages.length > 100) {
          _messages.removeAt(0);
        }
      });
    });

    setState(() {
      _isInitializing = false;
      _connectedDevices = _coordinator.connectedDevices;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('LSL Timing Tester - ${widget.config.deviceName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
          IconButton(icon: const Icon(Icons.save), onPressed: _exportData),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton:
          _coordinator.isCoordinator && !_testController.isTestRunning
          ? FloatingActionButton(
              onPressed: _showTestSelection,
              child: const Icon(Icons.play_arrow),
            )
          : null,
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Connected devices section
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.blueGrey.withOpacity(0.2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connected Devices (${_connectedDevices.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                children: _connectedDevices.map((device) {
                  return Chip(
                    label: Text(device),
                    backgroundColor: device == widget.config.deviceId
                        ? Colors.green.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                  );
                }).toList(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _coordinator.isCoordinator
                        ? 'Role: Coordinator'
                        : 'Role: Participant',
                    style: TextStyle(
                      color: _coordinator.isCoordinator
                          ? Colors.green
                          : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!_isReady && !_testController.isTestRunning)
                    ElevatedButton(
                      onPressed: _signalReady,
                      child: const Text('Signal Ready'),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Messages list
        Expanded(
          child: ListView.builder(
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return ListTile(dense: true, title: Text(_messages[index]));
            },
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ResultsPage(
                        timingManager: widget.timingManager,
                        dataExporter: _dataExporter,
                      ),
                    ),
                  );
                },
                child: const Text('View Results'),
              ),
              ElevatedButton(
                onPressed: _exportData,
                child: const Text('Export Data'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _signalReady() {
    _coordinator.signalReady();
    setState(() {
      _isReady = true;
    });
  }

  void _showTestSelection() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Test'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final testType in TestType.values)
                ListTile(
                  title: Text(testType.displayName),
                  subtitle: Text(testType.description),
                  onTap: () {
                    Navigator.pop(context);
                    _startTest(testType);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _startTest(TestType testType) {
    if (_coordinator.isCoordinator) {
      _coordinator.startTest(testType);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the coordinator can start tests')),
      );
    }
  }

  void _showSettings() {
    // Show settings dialog
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Device Settings'),
          content: SingleChildScrollView(
            child: _SettingsForm(
              config: widget.config,
              onSaved: () {
                setState(() {});
                Navigator.pop(context);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportData() async {
    try {
      final eventsPath = await _dataExporter.exportEventsToCSV();
      final metricsPath = await _dataExporter.exportMetricsToCSV();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data exported to:\n$eventsPath\n$metricsPath')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export error: $e')));
    }
  }

  @override
  void dispose() {
    _coordinator.dispose();
    _testController.dispose();
    super.dispose();
  }
}

class _SettingsForm extends StatefulWidget {
  final AppConfig config;
  final VoidCallback onSaved;

  const _SettingsForm({Key? key, required this.config, required this.onSaved})
    : super(key: key);

  @override
  _SettingsFormState createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late TextEditingController _deviceNameController;
  late TextEditingController _streamNameController;
  late TextEditingController _channelCountController;
  late TextEditingController _sampleRateController;

  @override
  void initState() {
    super.initState();

    _deviceNameController = TextEditingController(
      text: widget.config.deviceName,
    );
    _streamNameController = TextEditingController(
      text: widget.config.streamName,
    );
    _channelCountController = TextEditingController(
      text: widget.config.channelCount.toString(),
    );
    _sampleRateController = TextEditingController(
      text: widget.config.sampleRate.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _deviceNameController,
          decoration: const InputDecoration(labelText: 'Device Name'),
        ),
        TextField(
          controller: _streamNameController,
          decoration: const InputDecoration(labelText: 'Stream Name'),
        ),
        TextField(
          controller: _channelCountController,
          decoration: const InputDecoration(labelText: 'Channel Count'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _sampleRateController,
          decoration: const InputDecoration(labelText: 'Sample Rate (Hz)'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Device role
        Text('Device Role:', style: Theme.of(context).textTheme.titleSmall),
        CheckboxListTile(
          title: const Text('Producer (sends data)'),
          value: widget.config.isProducer,
          onChanged: (value) {
            setState(() {
              widget.config.isProducer = value ?? true;
            });
          },
        ),
        CheckboxListTile(
          title: const Text('Consumer (receives data)'),
          value: widget.config.isConsumer,
          onChanged: (value) {
            setState(() {
              widget.config.isConsumer = value ?? true;
            });
          },
        ),

        // Test duration
        Text('Test Duration:', style: Theme.of(context).textTheme.titleSmall),
        Slider(
          value: widget.config.testDurationSeconds.toDouble(),
          min: 10,
          max: 180,
          divisions: 17,
          label: '${widget.config.testDurationSeconds} seconds',
          onChanged: (value) {
            setState(() {
              widget.config.testDurationSeconds = value.round();
            });
          },
        ),
        Text('${widget.config.testDurationSeconds} seconds'),

        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _saveConfig,
          child: const Text('Save Settings'),
        ),
      ],
    );
  }

  Future<void> _saveConfig() async {
    widget.config.deviceName = _deviceNameController.text;
    widget.config.streamName = _streamNameController.text;
    widget.config.channelCount =
        int.tryParse(_channelCountController.text) ?? 1;
    widget.config.sampleRate =
        double.tryParse(_sampleRateController.text) ?? 100.0;

    await widget.config.save();
    widget.onSaved();
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _streamNameController.dispose();
    _channelCountController.dispose();
    _sampleRateController.dispose();
    super.dispose();
  }
}
