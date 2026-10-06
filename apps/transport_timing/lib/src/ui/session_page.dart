import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../settings.dart';
import '../timing_session.dart';

/// The session once joined: who is in it, the run in progress, and the
/// results so far. The coordinator also sets up and starts runs here.
class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.session});

  final TimingSession session;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  RunConfig _config = const RunConfig(runId: '');

  TimingSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.status.addListener(_onStatus);
  }

  @override
  void dispose() {
    _session.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    if (_session.status.value == SessionStatus.ended && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final r in _session.results.value) XFile(r.path)],
        subject: 'Transport timing logs',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _session.roster,
        _session.isCoordinator,
        _session.run,
        _session.results,
      ]),
      builder: (context, _) {
        final run = _session.run.value;
        if (run != null && run.config.test == TestKind.interactive) {
          return _InteractiveView(session: _session, run: run);
        }
        final results = _session.results.value;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              '${_session.settings.sessionName} · '
              '${_session.isCoordinator.value ? 'coordinator' : 'participant'}',
            ),
            leading: IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Leave',
              onPressed: run == null ? _session.leave : null,
            ),
            actions: [
              if (results.isNotEmpty)
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Share logs',
                    onPressed: () => _share(context),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final member in _session.roster.value)
                    Chip(
                      avatar: Icon(
                        member.isCoordinator ? Icons.hub : Icons.devices,
                        size: 18,
                      ),
                      label: Text(
                        member.isSelf ? '${member.name} (this)' : member.name,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (run != null)
                Card(
                  child: ListTile(
                    leading: const CircularProgressIndicator(),
                    title: Text(run.config.summary),
                    subtitle: Text(
                      run.queued == 0
                          ? run.status
                          : '${run.status} · ${run.queued} more queued',
                    ),
                  ),
                )
              else if (_session.isCoordinator.value)
                _RunForm(
                  config: _config,
                  onChanged: (config) => setState(() => _config = config),
                  onStart: () => _session.startRuns([
                    _config.copyWith(runId: RunConfig.newRunId()),
                  ]),
                  onSweep: () =>
                      _session.startRuns(RunConfig.rawLslSweep(_config)),
                )
              else
                const Card(
                  child: ListTile(
                    title: Text('Waiting for the coordinator to start a run'),
                  ),
                ),
              const SizedBox(height: 16),
              for (final result in results.reversed)
                Card(
                  child: ExpansionTile(
                    title: Text(result.config.summary),
                    subtitle: Text(result.path),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          result.report,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The coordinator's settings for the next run.
class _RunForm extends StatelessWidget {
  const _RunForm({
    required this.config,
    required this.onChanged,
    required this.onStart,
    required this.onSweep,
  });

  final RunConfig config;
  final ValueChanged<RunConfig> onChanged;
  final VoidCallback onStart;
  final VoidCallback onSweep;

  Widget _choice<T>(
    String label,
    T value,
    Map<T, String> options,
    RunConfig Function(T) apply,
  ) => DropdownButtonFormField<T>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final entry in options.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: (v) => onChanged(apply(v as T)),
  );

  @override
  Widget build(BuildContext context) {
    final latency = config.test == TestKind.latency;
    final raw = latency && config.path == DataPath.rawLsl;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _choice('Test', config.test, const {
              TestKind.latency: 'Latency',
              TestKind.interactive: 'Interactive (touch to flash)',
            }, (v) => config.copyWith(test: v)),
            _choice('Duration', config.durationSeconds, const {
              10: '10 s',
              30: '30 s',
              60: '1 min',
              180: '3 min',
              600: '10 min',
            }, (v) => config.copyWith(durationSeconds: v)),
            if (latency) ...[
              _choice('Samples through', config.path, const {
                DataPath.stream: 'The session\'s backend (coordinator stream)',
                DataPath.rawLsl: 'Raw LSL (liblsl directly)',
              }, (v) => config.copyWith(path: v)),
              _choice('Rate', config.sampleRate.round(), const {
                10: '10 Hz',
                100: '100 Hz',
                250: '250 Hz',
                500: '500 Hz',
                1000: '1000 Hz',
              }, (v) => config.copyWith(sampleRate: v.toDouble())),
              _choice('Channels', config.channels, const {
                1: '1',
                8: '8',
                32: '32',
                128: '128',
              }, (v) => config.copyWith(channels: v)),
            ],
            if (latency && !raw)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Precise polling'),
                subtitle: const Text(
                  'LSL backend: busy-wait instead of timers',
                ),
                value: config.precisePolling,
                onChanged: (v) => onChanged(config.copyWith(precisePolling: v)),
              ),
            if (raw) ...[
              _choice('Receive', config.receiveMode, {
                for (final mode in ReceiveMode.values) mode: mode.label,
              }, (v) => config.copyWith(receiveMode: v)),
              if (config.receiveMode == ReceiveMode.polled)
                _choice('Poll interval', config.pollIntervalMicros, const {
                  1000: '1 ms',
                  2000: '2 ms',
                  5000: '5 ms',
                  10000: '10 ms',
                  16667: '16.7 ms (60 Hz)',
                }, (v) => config.copyWith(pollIntervalMicros: v)),
              _choice('Send', config.sendMode, {
                for (final mode in SendMode.values) mode: mode.label,
              }, (v) => config.copyWith(sendMode: v)),
              if (config.sendMode != SendMode.syncBlocking)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Push through'),
                  subtitle: const Text('Send each sample at once'),
                  value: config.pushthrough,
                  onChanged: (v) => onChanged(config.copyWith(pushthrough: v)),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: onStart, child: const Text('Start run')),
            if (latency)
              TextButton(
                onPressed: onSweep,
                child: Text(
                  'Sweep raw LSL modes '
                  '(${ReceiveMode.values.length * SendMode.values.length} runs)',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An interactive run: touching the screen sends a sample, and every sample
/// received, this device's own included, flashes the square. A photodiode
/// on the square and a force sensor on the screen time the whole path from
/// outside.
class _InteractiveView extends StatefulWidget {
  const _InteractiveView({required this.session, required this.run});

  final TimingSession session;
  final ActiveRun run;

  @override
  State<_InteractiveView> createState() => _InteractiveViewState();
}

class _InteractiveViewState extends State<_InteractiveView> {
  bool _lit = false;
  Timer? _off;

  @override
  void initState() {
    super.initState();
    widget.session.flash.addListener(_onFlash);
  }

  @override
  void dispose() {
    widget.session.flash.removeListener(_onFlash);
    _off?.cancel();
    super.dispose();
  }

  void _onFlash() {
    setState(() => _lit = true);
    _off?.cancel();
    _off = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _lit = false);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    // Pointer down, not a tap: a tap is only recognised on release.
    body: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.session.touch(),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 240,
              height: 240,
              color: _lit ? Colors.black : Colors.white,
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Text(
              'Touch anywhere · ${widget.run.status}',
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    ),
  );
}
