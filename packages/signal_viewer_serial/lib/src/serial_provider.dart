import 'package:flutter/material.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:signal_viewer/signal_viewer.dart';

import 'cyton_session.dart';
import 'serial_session.dart';

/// Streams of numbers from serial ports (e.g. an Arduino printing sensor
/// values), one tab each: native ports on desktop, WebSerial in browsers.
class SerialStreamProvider extends SourceProvider {
  final SerialPortProvider serial;

  SerialStreamProvider({SerialPortProvider? serial})
    : serial = serial ?? SerialPortProvider.platform();

  bool get supported => serial.isSupported;

  Iterable<SerialStreamSession> get sessions =>
      app.sessions.whereType<SerialStreamSession>();

  /// Open [port] and show its stream (a tab appears once its rate is
  /// known).
  Future<void> open(
    SerialPortInfo port, {
    required String name,
    int? baudRate,
    double? rate,
    String type = '',
  }) async {
    app.setStatus('Opening ${port.id}…');
    try {
      final s = await SerialStreamSession.open(
        serial,
        port,
        name: name,
        baudRate: baudRate,
        rate: rate,
        type: type,
      );
      app.addSession(s);
    } catch (e) {
      app.setError('Could not open ${port.id}: $e');
    }
  }

  /// Connect to the OpenBCI Cyton on [port] and show its streams.
  Future<void> openCyton(
    SerialPortInfo port, {
    bool useDaisy = true,
    bool ultracortex = true,
  }) async {
    app.setStatus('Connecting to the Cyton on ${port.id}…');
    try {
      final s = await CytonSession.open(
        serial,
        port,
        useDaisy: useDaisy,
        ultracortex: ultracortex,
      );
      app.addSession(s);
    } catch (e) {
      app.setError('Could not connect to the Cyton: $e');
    }
  }

  @override
  List<ViewerAction> actions(BuildContext context) => [
    if (supported) ...[
      ViewerAction(
        'Serial',
        'Open serial stream…',
        narrowLabel: 'Serial stream…',
        onPressed: () => showSerialStreamDialog(context, this),
      ),
      ViewerAction(
        'Serial',
        'Connect an OpenBCI Cyton…',
        onPressed: () =>
            showSerialStreamDialog(context, this, device: SerialDevice.cyton),
      ),
    ],
  ];

  @override
  List<Widget> welcome(BuildContext context) => [
    if (supported)
      OutlinedButton.icon(
        onPressed: () => showSerialStreamDialog(context, this),
        icon: const Icon(Icons.cable),
        label: const Text('Read a serial device…'),
      ),
  ];
}

const _bauds = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600];

/// What is on a serial port.
enum SerialDevice {
  lines('Lines of numbers'),
  cyton('OpenBCI Cyton');

  final String label;
  const SerialDevice(this.label);
}

/// Choose a serial port and how to read it.
Future<void> showSerialStreamDialog(
  BuildContext context,
  SerialStreamProvider provider, {
  SerialDevice device = SerialDevice.lines,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SerialDialog(provider, device),
);

class _SerialDialog extends StatefulWidget {
  final SerialStreamProvider provider;
  final SerialDevice device;
  const _SerialDialog(this.provider, this.device);

  @override
  State<_SerialDialog> createState() => _SerialDialogState();
}

class _SerialDialogState extends State<_SerialDialog> {
  List<SerialPortInfo> _ports = [];
  SerialPortInfo? _port;
  late SerialDevice _device = widget.device;
  bool _daisy = true;
  bool _ultracortex = true;
  int _baud = 115200;
  final _rate = TextEditingController();
  final _name = TextEditingController(text: 'Serial');
  final _type = TextEditingController();
  String? _error;

  SerialPortProvider get _serial => widget.provider.serial;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _rate.dispose();
    _name.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final ports = await _serial.listPorts();
      if (!mounted) return;
      setState(() {
        _ports = ports;
        if (_port == null || !ports.any((p) => p.id == _port!.id)) {
          _port = ports.isEmpty ? null : ports.first;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// The web only lists ports the user chose.
  Future<void> _request() async {
    final p = await _serial.requestPort();
    if (p == null) return;
    await _refresh();
    setState(
      () => _port = _ports.firstWhere((x) => x.id == p.id, orElse: () => p),
    );
  }

  Future<void> _open() async {
    final port = _port;
    if (port == null) return;
    if (_device == SerialDevice.cyton) {
      Navigator.pop(context);
      await widget.provider.openCyton(
        port,
        useDaisy: _daisy,
        ultracortex: _ultracortex,
      );
      return;
    }
    final text = _rate.text.trim();
    final rate = text.isEmpty ? null : double.tryParse(text);
    if (text.isNotEmpty && (rate == null || rate <= 0)) {
      setState(() => _error = 'The rate is a number of Hz, or empty');
      return;
    }
    Navigator.pop(context);
    await widget.provider.open(
      port,
      name: _name.text.trim().isEmpty ? 'Serial' : _name.text.trim(),
      baudRate: _baud,
      rate: rate,
      type: _type.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Open a serial stream'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<SerialDevice>(
              segments: [
                for (final d in SerialDevice.values)
                  ButtonSegment(value: d, label: Text(d.label)),
              ],
              selected: {_device},
              onSelectionChanged: (v) => setState(() => _device = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              _device == SerialDevice.cyton
                  ? "The Cyton's USB dongle (switch on GPIO_6). A Daisy is "
                        'found by itself: 16 channels at 125 Hz, or 8 at '
                        '250 Hz without one.'
                  : 'Lines of numbers, separated by commas, semicolons, tabs '
                        'or spaces, or name:value pairs (as for the Arduino '
                        'Serial Plotter). A line of names first labels the '
                        'channels.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _port?.id,
                    hint: const Text('No serial ports'),
                    items: [
                      for (final p in _ports)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.description.isEmpty
                                ? p.id
                                : '${p.description} (${p.id})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(
                      () => _port = _ports.firstWhere((p) => p.id == id),
                    ),
                  ),
                ),
                if (_serial.requiresUserSelection)
                  TextButton(onPressed: _request, child: const Text('Choose…'))
                else
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            if (_device == SerialDevice.cyton) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _daisy,
                onChanged: (v) => setState(() => _daisy = v ?? true),
                title: const Text('Use the Daisy if there is one'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _ultracortex,
                onChanged: (v) => setState(() => _ultracortex = v ?? true),
                title: const Text('UltraCortex Mark IV channel names'),
                subtitle: const Text('Fp1, Fp2, C3, C4, P7, P8, O1, O2, …'),
              ),
            ],
            if (_device == SerialDevice.lines) ...[
              Row(
                children: [
                  const Text('Baud rate '),
                  DropdownButton<int>(
                    value: _baud,
                    items: [
                      for (final b in _bauds)
                        DropdownMenuItem(value: b, child: Text('$b')),
                    ],
                    onChanged: (b) => setState(() => _baud = b ?? _baud),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _rate,
                      decoration: const InputDecoration(
                        labelText: 'Sampling rate (Hz)',
                        hintText: 'Empty: measure it',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _type,
                      decoration: const InputDecoration(
                        labelText: 'Type (optional)',
                        hintText: 'e.g. EEG, MoCap',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _port == null ? null : _open,
          child: const Text('Open'),
        ),
      ],
    );
  }
}
