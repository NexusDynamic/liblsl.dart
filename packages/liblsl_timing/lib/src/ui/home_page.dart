// lib/src/ui/home_page.dart
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liblsl_timing/src/ui/test_page.dart';
import 'package:network_info_plus/network_info_plus.dart';
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

  final List<String> _messages = [];
  List<String> _connectedDevices = [];
  List<bool> _readyDevices = [];
  bool _isInitializing = true;
  bool _isReady = false;
  String _wifiIp = '';

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
    _getWifiIp();
    _initialize();
  }

  Future<void> _getWifiIp() async {
    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (kDebugMode) {
        print('NetworkInfo: $info');
      }
      if (wifiIp != null) {
        setState(() {
          _wifiIp = wifiIp;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error getting WiFi IP: $e')));
      }
    }
  }

  Future<void> _initialize() async {
    // Calibrate time base
    await widget.timingManager.calibrateTimeBase();

    // Initialize device coordinator
    _coordinator.initialize().then((_) {
      // Listen for coordinator messages
      _coordinator.messageStream.listen((message) {
        setState(() {
          _readyDevices = _coordinator.readyDevices;
          _connectedDevices = _coordinator.connectedDevices;

          _messages.add(message);
          if (_messages.length > 100) {
            _messages.removeAt(0);
          }
        });
      });

      _coordinator.onNavigateToTest((testType) {
        // Only navigate if we're not the coordinator (coordinator already navigates in _startTest)

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TestPage(
              testType: testType,
              testController: _testController,
              timingManager: widget.timingManager,
            ),
          ),
        );
      });

      // Update connected devices when the list might have changed
      _readyDevices = _coordinator.readyDevices;
      _connectedDevices = _coordinator.connectedDevices;

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
        _readyDevices = _coordinator.readyDevices;
        _connectedDevices = _coordinator.connectedDevices;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${'TITLE'.tr()} - ${widget.config.deviceName} ($_wifiIp)'),
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
          color: Colors.blueGrey.withAlpha(51),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${'CONN_DEV'.tr()} (${_connectedDevices.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                children: _connectedDevices.mapIndexed((index, device) {
                  final isReady = _readyDevices[index];
                  return Chip(
                    label: Text(device),
                    deleteIcon: isReady
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.remove_circle, color: Colors.red),
                    onDeleted: () {},
                    backgroundColor: device == widget.config.deviceId
                        ? _coordinator.isCoordinator
                              ? Colors.blue.withAlpha(76)
                              : Colors.green.withAlpha(76)
                        : device == _coordinator.coordinatorId
                        ? Colors.blue.withAlpha(76)
                        : Colors.grey.withAlpha(76),
                  );
                }).toList(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _coordinator.isCoordinator
                        ? '${'ROLE'.tr()}: ${'ROLE_COORD'.tr()}'
                        : '${'ROLE'.tr()}: ${'ROLE_PART'.tr()}',
                    style: TextStyle(
                      color: _coordinator.isCoordinator
                          ? Colors.blue
                          : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!_isReady && !_testController.isTestRunning)
                    ElevatedButton(
                      onPressed: _signalReady,
                      child: Text('SIG_READY'.tr()),
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
                child: Text('RESULTS_VIEW'.tr()),
              ),
              ElevatedButton(
                onPressed: _exportData,
                child: Text('DATA_EXPORT'.tr()),
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
              child: Text('CANCEL'.tr()),
            ),
          ],
        );
      },
    );
  }

  void _startTest(TestType testType) {
    if (_coordinator.isCoordinator) {
      _coordinator.startTest(testType);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TestPage(
            testType: testType,
            testController: _testController,
            timingManager: widget.timingManager,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('START_COORD_ONLY')));
    }
  }

  void _showSettings() {
    // Show settings dialog
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('SETTINGS_DEV'.tr()),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'EXPORTED_TO'.tr()}:\n$eventsPath\n$metricsPath'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${'ERR_EXPORT'.tr()}: $e')));
      }
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

  const _SettingsForm({required this.config, required this.onSaved});

  @override
  _SettingsFormState createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late TextEditingController _deviceNameController;
  late TextEditingController _deviceIdController;
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
    _deviceIdController = TextEditingController(text: widget.config.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Langage selection
        DropdownButton(
          value: context.locale,
          items: context.supportedLocales.map((locale) {
            return DropdownMenuItem(
              value: locale,
              child: Text(locale.languageCode.toUpperCase()),
            );
          }).toList(),
          onChanged: (locale) {
            if (locale != null) {
              context.setLocale(locale);
            }
          },
        ),
        TextField(
          controller: _deviceNameController,
          decoration: InputDecoration(labelText: 'DEV_NAME'.tr()),
        ),
        TextField(
          controller: _deviceIdController,
          decoration: InputDecoration(labelText: 'DEV_ID'.tr()),
          enabled: true,
        ),
        TextField(
          controller: _streamNameController,
          decoration: InputDecoration(labelText: 'STREAM_NAME'.tr()),
        ),
        TextField(
          controller: _channelCountController,
          decoration: InputDecoration(labelText: 'CHANNEL_COUNT'.tr()),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _sampleRateController,
          decoration: InputDecoration(labelText: 'SAMPLE_RATE_HZ'.tr()),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Device role
        Text('DEV_ROLE'.tr(), style: Theme.of(context).textTheme.titleSmall),
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
        // Stream settings
        Text('Stream Settings:', style: Theme.of(context).textTheme.titleSmall),
        Text('Max Wait Time (seconds):'),
        Slider(
          value: widget.config.streamMaxWaitTimeSeconds.toDouble(),
          min: 1,
          max: 60,
          divisions: 59,
          label: '${widget.config.streamMaxWaitTimeSeconds} seconds',
          onChanged: (value) {
            setState(() {
              widget.config.streamMaxWaitTimeSeconds = value;
            });
          },
        ),

        Text('${widget.config.streamMaxWaitTimeSeconds} seconds'),
        Text('Max Streams:'),
        Slider(
          value: widget.config.streamMaxStreams.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          label: '${widget.config.streamMaxStreams} streams',
          onChanged: (value) {
            setState(() {
              widget.config.streamMaxStreams = value.round();
            });
          },
        ),

        Text('${widget.config.streamMaxStreams} streams'),

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
    widget.config.deviceId = _deviceIdController.text;
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
    _deviceIdController.dispose();
    _streamNameController.dispose();
    _channelCountController.dispose();
    _sampleRateController.dispose();
    super.dispose();
  }
}
