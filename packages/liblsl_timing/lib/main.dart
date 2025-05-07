import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:liblsl_timing/src/tests/clock_sync_test.dart';
import 'package:liblsl_timing/src/tests/render_timing_test.dart';
import 'package:liblsl_timing/src/tests/sample_rate_stability_test.dart';
import 'package:liblsl_timing/src/tests/stream_latency_test.dart';
import 'package:liblsl_timing/src/tests/ui_to_lsl_test.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/visualization/results_view.dart';
import 'package:liblsl_timing/src/tests/test_registry.dart';
import 'package:liblsl_timing/src/device_settings_page.dart';
import 'package:liblsl_timing/src/device_sync_page.dart';
import 'package:liblsl_timing/src/test_report_page.dart';
import 'package:liblsl_timing/src/utils/external_hardware_manager.dart';
import 'package:liblsl_timing/src/utils/list_map_indexed.dart';

void main() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    WidgetsFlutterBinding.ensureInitialized();
    final MethodChannel rtNetworkingChannel = MethodChannel(
      'com.zeyus.liblsl_timing/Networking',
    );
    try {
      rtNetworkingChannel.invokeMethod('acquireMulticastLock');
      print('Acquired multicast lock');
    } on PlatformException catch (e) {
      print('Failed to acquire multicast lock: ${e.message}');
    }
  }
  runApp(const LSLTimingApp());
}

class LSLTimingApp extends StatelessWidget {
  const LSLTimingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LSL Timing Tests',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TimingTestHome(),
    );
  }
}

class TimingTestHome extends StatefulWidget {
  const TimingTestHome({super.key});

  @override
  State<TimingTestHome> createState() => _TimingTestHomeState();
}

class _TimingTestHomeState extends State<TimingTestHome> {
  final TimingManager _timingManager = TimingManager();
  final TestConfiguration _config = TestConfiguration();
  final ExternalHardwareManager _hardwareManager = ExternalHardwareManager(
    TimingManager(),
  );

  bool _isRunningTest = false;
  String _currentTestName = "";
  Widget? _currentTestWidget;
  final List<bool> _isExpanded = [];

  @override
  void initState() {
    super.initState();
    _initializeLSL();
    _isExpanded.addAll([
      true, // Configuration panel
      false, // Test selection
      false, // Results visualization
    ]);
  }

  Future<void> _initializeLSL() async {
    // Initialize LSL library
    print('LSL Library Version: ${LSL.version}');
    print('LSL Library Info: ${LSL.libraryInfo()}');

    // Initialize hardware manager
    await _hardwareManager.initialize();
  }

  void _startTest(String testName) async {
    setState(() {
      _isRunningTest = true;
      _currentTestName = testName;
      _currentTestWidget = null;
    });

    final test = TestRegistry.getTest(testName);
    if (test != null) {
      // Create a completer that will be passed to the test
      final testCompleter = Completer<void>();

      try {
        // For UI tests, we need to create and display the widget
        if (test is UIToLSLTest) {
          // Create outlet and other resources
          final streamInfo = await LSL.createStreamInfo(
            streamName: _config.streamName,
            streamType: _config.streamType,
            channelCount: _config.channelCount,
            sampleRate: _config.sampleRate,
            channelFormat: _config.channelFormat,
            sourceId: _config.sourceId,
          );

          final outlet = await LSL.createOutlet(
            streamInfo: streamInfo,
            chunkSize: 0,
            maxBuffer: 360,
          );

          // Create and display the test widget
          setState(() {
            _currentTestWidget = UILatencyTestWidget(
              timingManager: _timingManager,
              outlet: outlet,
              testDurationSeconds: _config.testDurationSeconds,
              onTestComplete: () {
                if (!testCompleter.isCompleted) testCompleter.complete();
              },
              showTimingMarker: _config.showTimingMarker,
              markerSize: _config.timingMarkerSizePixels,
            );
          });

          // Run the test with the completer
          test
              .runTestWithTimeout(
                _timingManager,
                _config,
                completer: testCompleter,
              )
              .then((_) async {
                if (!testCompleter.isCompleted) testCompleter.complete();
                setState(() {
                  _isRunningTest = false;
                  _currentTestWidget = null;
                });
                WidgetsBinding.instance.scheduleFrame();
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TestReportPage(
                        timingManager: _timingManager,
                        testName: testName,
                      ),
                    ),
                  );
                }
              });

          // Clean up resources
          outlet.destroy();
          streamInfo.destroy();
        } else if (test is RenderTimingTest) {
          // Similar approach for RenderTimingTest
          setState(() {
            _currentTestWidget = RenderTimingTestWidget(
              timingManager: _timingManager,
              flashDurationMs: 100,
              intervalBetweenFlashesMs: 500,
              flashCount: 50,
              markerSize: _config.timingMarkerSizePixels,
              onTestComplete: () {
                if (!testCompleter.isCompleted) testCompleter.complete();
              },
            );
          });

          test
              .runTestWithTimeout(
                _timingManager,
                _config,
                completer: testCompleter,
              )
              .then((_) async {
                if (!testCompleter.isCompleted) testCompleter.complete();
                setState(() {
                  _isRunningTest = false;
                  _currentTestWidget = null;
                });
                WidgetsBinding.instance.scheduleFrame();
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TestReportPage(
                        timingManager: _timingManager,
                        testName: testName,
                      ),
                    ),
                  );
                }
              });
        } else {
          // For non-UI tests, show a simple progress indicator
          setState(() {
            _currentTestWidget = Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text('Running test: $_currentTestName'),
                  const SizedBox(height: 10),
                  Text('Please wait...'),
                ],
              ),
            );
          });

          // Run the test with timeout
          test
              .runTestWithTimeout(
                _timingManager,
                _config,
                completer: testCompleter,
              )
              .then((_) async {
                if (!testCompleter.isCompleted) testCompleter.complete();
                setState(() {
                  _isRunningTest = false;
                  _currentTestWidget = null;
                });
                WidgetsBinding.instance.scheduleFrame();
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TestReportPage(
                        timingManager: _timingManager,
                        testName: testName,
                      ),
                    ),
                  );
                }
              });
        }
      } catch (e) {
        print('Error running test: $e');
        setState(() {
          _isRunningTest = false;
          _currentTestWidget = null;
        });
        WidgetsBinding.instance.scheduleFrame();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Test failed: $e')));
        }
      }
    } else {
      setState(() {
        _isRunningTest = false;
        _currentTestWidget = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Test "$testName" not found')));
      }
    }
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LSL Timing Tests'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DeviceSyncPage(config: _config),
                ),
              );

              if (result != null && result == 'ClockSyncTest') {
                _startTest('Clock Synchronization');
              }
            },
            tooltip: 'Device Synchronization',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DeviceSettingsPage(
                    config: _config,
                    onConfigUpdated: () {
                      setState(() {});
                    },
                  ),
                ),
              );
            },
            tooltip: 'Device Settings',
          ),
        ],
      ),
      body: _isRunningTest ? _buildRunningTestView() : _buildMainTestView(),
    );
  }

  Widget _buildRunningTestView() {
    return _currentTestWidget != null
        ? _currentTestWidget!
        : Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Running test: $_currentTestName',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
              ],
            ),
          );
  }

  Widget _buildMainTestView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: ExpansionPanelList(
        expansionCallback: (int index, bool isExpanded) {
          setState(() {
            _isExpanded[index] = isExpanded;
          });
        },
        children: [
          // Configuration panel
          ExpansionPanel(
            isExpanded: _isExpanded[0],
            canTapOnHeader: true,
            headerBuilder: (BuildContext context, bool isExpanded) {
              return ListTile(
                title: Text(
                  'Configuration',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              );
            },
            body: ConfigurationPanel(
              config: _config,
              onConfigChanged: () {
                setState(() {});
              },
            ),
          ),

          // Test selection
          ExpansionPanel(
            isExpanded: _isExpanded[1],
            canTapOnHeader: true,
            headerBuilder: (BuildContext context, bool isExpanded) {
              return ListTile(
                title: Text(
                  'Test Selection',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              );
            },
            body: TestSelectionPanel(onTestSelected: _startTest),
          ),
          // Results visualization (shows last run)
          ExpansionPanel(
            isExpanded: _isExpanded[2],
            canTapOnHeader: true,
            headerBuilder: (BuildContext context, bool isExpanded) {
              return ListTile(
                title: Text(
                  'Results Visualization',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              );
            },
            body: ResultsView(timingManager: _timingManager),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hardwareManager.dispose();
    super.dispose();
  }
}

class TestSelectionPanel extends StatelessWidget {
  final Function(String) onTestSelected;

  const TestSelectionPanel({super.key, required this.onTestSelected});

  @override
  Widget build(BuildContext context) {
    final tests = TestRegistry.availableTests;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Tests',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),

            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8.0,
              runSpacing: 8.0,
              children: tests
                  .map<Widget>(
                    (test) => Tooltip(
                      message: test.description,
                      child: ElevatedButton(
                        onPressed: () => onTestSelected(test.name),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                        child: Text(test.name),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class ConfigurationPanel extends StatelessWidget {
  final TestConfiguration config;
  final VoidCallback onConfigChanged;

  const ConfigurationPanel({
    super.key,
    required this.config,
    required this.onConfigChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Test Configuration',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Config'),
                  onPressed: onConfigChanged,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNumberInput(
                  context,
                  'Sample Rate (Hz)',
                  config.sampleRate.toString(),
                  (value) {
                    config.sampleRate = double.tryParse(value) ?? 100.0;
                    onConfigChanged();
                  },
                ),
                _buildNumberInput(
                  context,
                  'Number of Channels',
                  config.channelCount.toString(),
                  (value) {
                    config.channelCount = int.tryParse(value) ?? 1;
                    onConfigChanged();
                  },
                ),
                _buildDropdown(
                  context,
                  'Stream Type',
                  LSLContentType.values.map((t) => t.value).toList(),
                  config.streamType.value,
                  (value) {
                    config.streamType = LSLContentType.values.firstWhere(
                      (t) => t.value == value,
                      orElse: () => LSLContentType.eeg,
                    );
                    onConfigChanged();
                  },
                ),
                _buildDropdown(
                  context,
                  'Channel Format',
                  LSLChannelFormat.values.map((f) => f.name).toList(),
                  config.channelFormat.name,
                  (value) {
                    config.channelFormat = LSLChannelFormat.values.firstWhere(
                      (f) => f.name == value,
                      orElse: () => LSLChannelFormat.float32,
                    );
                    onConfigChanged();
                  },
                ),
                _buildNumberInput(
                  context,
                  'Test Duration (sec)',
                  config.testDurationSeconds.toString(),
                  (value) {
                    config.testDurationSeconds = int.tryParse(value) ?? 10;
                    onConfigChanged();
                  },
                ),

                const Divider(),

                // Device role indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Chip(
                      label: const Text('Producer'),
                      backgroundColor: config.isProducer
                          ? Colors.green.withAlpha(50)
                          : Colors.grey.withAlpha(50),
                      avatar: Icon(
                        Icons.upload,
                        color: config.isProducer ? Colors.green : Colors.grey,
                      ),
                    ),
                    Chip(
                      label: const Text('Consumer'),
                      backgroundColor: config.isConsumer
                          ? Colors.blue.withAlpha(50)
                          : Colors.grey.withAlpha(50),
                      avatar: Icon(
                        Icons.download,
                        color: config.isConsumer ? Colors.blue : Colors.grey,
                      ),
                    ),
                    Chip(
                      label: const Text('Timing Marker'),
                      backgroundColor: config.showTimingMarker
                          ? Colors.purple.withAlpha(50)
                          : Colors.grey.withAlpha(50),
                      avatar: Icon(
                        Icons.circle,
                        color: config.showTimingMarker
                            ? Colors.purple
                            : Colors.grey,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput(
    BuildContext context,
    String label,
    String value,
    Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(label)),
          Flexible(
            child: SizedBox(
              height: 25,
              child: TextField(
                scrollPadding: const EdgeInsets.all(2),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.2,
                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                ),
                controller: TextEditingController(text: value),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 1,
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    BuildContext context,
    String label,
    List<String> options,
    String value,
    Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(label)),

          Flexible(
            child: SizedBox(
              height: 25,
              child: DropdownButtonFormField<String>(
                value: value,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.2,
                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                ),
                padding: const EdgeInsets.all(0),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 1,
                  ),
                ),
                items: options.map((String option) {
                  return DropdownMenuItem<String>(
                    value: option,
                    child: Text(
                      option,
                      strutStyle: StrutStyle(
                        forceStrutHeight: true,
                        height: 1.2,
                        fontSize: Theme.of(
                          context,
                        ).textTheme.bodySmall?.fontSize,
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.2,
                        fontSize: Theme.of(
                          context,
                        ).textTheme.bodySmall?.fontSize,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    onChanged(newValue);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
