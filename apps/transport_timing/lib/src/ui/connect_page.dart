import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../settings.dart';
import '../timing_session.dart';
import 'session_page.dart';

/// Names this device, picks the backend and joins the session.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  bool _connecting = false;
  String? _error;

  AppSettings get _settings => widget.settings;

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    await _settings.save();
    final session = TimingSession(settings: _settings);
    final connected = await session.connect();
    if (!mounted) {
      session.dispose();
      return;
    }
    if (!connected) {
      setState(() {
        _connecting = false;
        _error = session.notice;
      });
      session.dispose();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SessionPage(session: session)),
    );
    final notice = session.notice;
    session.dispose();
    if (mounted) {
      setState(() {
        _connecting = false;
        _error = notice;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsHub = _settings.backend.needsHub;
    return Scaffold(
      appBar: AppBar(title: const Text('Transport Timing')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (kDebugMode)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Debug build: timings are not representative. '
                      'Measure with a release build.',
                    ),
                  ),
                ),
              TextFormField(
                initialValue: _settings.deviceName,
                decoration: const InputDecoration(labelText: 'Device name'),
                onChanged: (v) =>
                    setState(() => _settings.deviceName = v.trim()),
              ),
              TextFormField(
                initialValue: _settings.sessionName,
                decoration: const InputDecoration(
                  labelText: 'Session',
                  helperText: 'Devices with the same session find each other',
                ),
                onChanged: (v) =>
                    setState(() => _settings.sessionName = v.trim()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Backend>(
                initialValue: _settings.backend,
                decoration: const InputDecoration(labelText: 'Backend'),
                items: [
                  for (final backend in Backend.values)
                    DropdownMenuItem(
                      value: backend,
                      child: Text(backend.label),
                    ),
                ],
                onChanged: (v) => setState(() => _settings.backend = v!),
              ),
              if (_settings.backend == Backend.lsl)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Event-driven receive'),
                  subtitle: const Text(
                    'Wait inside liblsl for each sample instead of polling',
                  ),
                  value: _settings.eventDrivenLsl,
                  onChanged: (v) =>
                      setState(() => _settings.eventDrivenLsl = v),
                ),
              if (needsHub) ...[
                TextFormField(
                  initialValue: _settings.hubUrl,
                  decoration: const InputDecoration(
                    labelText: 'Hub URL',
                    helperText: 'dart run peer_coordinator:hub',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (v) => _settings.hubUrl = v.trim(),
                ),
                TextFormField(
                  initialValue: _settings.hubSecret,
                  decoration: const InputDecoration(labelText: 'Hub secret'),
                  obscureText: true,
                  onChanged: (v) => _settings.hubSecret = v,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    _connecting ||
                        _settings.deviceName.isEmpty ||
                        _settings.sessionName.isEmpty
                    ? null
                    : _connect,
                child: Text(_connecting ? 'Connecting…' : 'Connect'),
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
