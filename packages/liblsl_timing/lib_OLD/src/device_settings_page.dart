import 'package:flutter/material.dart';
import 'package:liblsl_timing/src/test_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceSettingsPage extends StatefulWidget {
  final TestConfiguration config;
  final Function onConfigUpdated;

  const DeviceSettingsPage({
    super.key,
    required this.config,
    required this.onConfigUpdated,
  });

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _externalHardwareController =
      TextEditingController();

  bool _useExternalHardware = false;
  bool _usePhotodiode = false;
  bool _useFsrSensor = false;
  bool _isProducer = true;
  bool _isConsumer = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();

    _deviceNameController.text = widget.config.sourceId;
    _isProducer = widget.config.isProducer;
    _isConsumer = widget.config.isConsumer;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _useExternalHardware = prefs.getBool('useExternalHardware') ?? false;
      _usePhotodiode = prefs.getBool('usePhotodiode') ?? false;
      _useFsrSensor = prefs.getBool('useFsrSensor') ?? false;
      _externalHardwareController.text =
          prefs.getString('externalHardwareDevice') ?? 'TimingDevice';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('useExternalHardware', _useExternalHardware);
    await prefs.setBool('usePhotodiode', _usePhotodiode);
    await prefs.setBool('useFsrSensor', _useFsrSensor);
    await prefs.setString(
      'externalHardwareDevice',
      _externalHardwareController.text,
    );

    // Update the config
    widget.config.sourceId = _deviceNameController.text;
    widget.config.isProducer = _isProducer;
    widget.config.isConsumer = _isConsumer;
    widget.onConfigUpdated();
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _externalHardwareController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Identity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Device name
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(
                labelText: 'Device Name / Source ID',
                border: OutlineInputBorder(),
                helperText: 'Unique identifier for this device',
              ),
            ),
            const SizedBox(height: 24),

            // Device role
            Text('Device Role', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            CheckboxListTile(
              title: const Text('Stream Producer'),
              subtitle: const Text('This device will send LSL data'),
              value: _isProducer,
              onChanged: (value) {
                setState(() {
                  _isProducer = value ?? true;
                });
              },
            ),

            CheckboxListTile(
              title: const Text('Stream Consumer'),
              subtitle: const Text('This device will receive LSL data'),
              value: _isConsumer,
              onChanged: (value) {
                setState(() {
                  _isConsumer = value ?? true;
                });
              },
            ),

            const SizedBox(height: 24),

            // External hardware integration
            Text(
              'External Hardware',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Use External Timing Hardware'),
              subtitle: const Text(
                'Connect to external hardware for precision timing',
              ),
              value: _useExternalHardware,
              onChanged: (value) {
                setState(() {
                  _useExternalHardware = value;
                });
              },
            ),

            if (_useExternalHardware) ...[
              const SizedBox(height: 16),

              TextField(
                controller: _externalHardwareController,
                decoration: const InputDecoration(
                  labelText: 'External Hardware Device Name',
                  border: OutlineInputBorder(),
                  helperText: 'BLE device name to connect to',
                ),
              ),

              const SizedBox(height: 16),

              CheckboxListTile(
                title: const Text('Use Photodiode'),
                subtitle: const Text('Records visual stimulus timing'),
                value: _usePhotodiode,
                onChanged: (value) {
                  setState(() {
                    _usePhotodiode = value ?? false;
                  });
                },
              ),

              CheckboxListTile(
                title: const Text('Use FSR Sensor'),
                subtitle: const Text('Records touch/press timing'),
                value: _useFsrSensor,
                onChanged: (value) {
                  setState(() {
                    _useFsrSensor = value ?? false;
                  });
                },
              ),
            ],

            const SizedBox(height: 24),

            // Network settings
            Text(
              'Network Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Use Local Network Only'),
              subtitle: const Text('Limit discovery to local network'),
              value: widget.config.useLocalNetworkOnly,
              onChanged: (value) {
                setState(() {
                  widget.config.useLocalNetworkOnly = value;
                });
              },
            ),

            const SizedBox(height: 24),

            // Advanced settings
            Text(
              'Advanced Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Enable Clock Synchronization'),
              subtitle: const Text('Improves timing accuracy across devices'),
              value: widget.config.enableClockSync,
              onChanged: (value) {
                setState(() {
                  widget.config.enableClockSync = value;
                });
              },
            ),

            SwitchListTile(
              title: const Text('Show Timing Marker'),
              subtitle: const Text('Display visual marker for photodiode'),
              value: widget.config.showTimingMarker,
              onChanged: (value) {
                setState(() {
                  widget.config.showTimingMarker = value;
                });
              },
            ),

            if (widget.config.showTimingMarker) ...[
              const SizedBox(height: 16),

              Slider(
                value: widget.config.timingMarkerSizePixels,
                min: 10,
                max: 200,
                divisions: 19,
                label: '${widget.config.timingMarkerSizePixels.round()} px',
                onChanged: (value) {
                  setState(() {
                    widget.config.timingMarkerSizePixels = value;
                  });
                },
              ),

              Text(
                'Timing Marker Size: ${widget.config.timingMarkerSizePixels.round()} pixels',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
