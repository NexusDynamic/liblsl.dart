import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lsl_tools/lsl_tools.dart';
import 'lsl_provider.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:xml/xml.dart';

import 'lsl_session.dart';

/// Streams on the network, to open in tabs. Looks for streams while open.
Future<void> showLslStreams(BuildContext context, LslProvider app) async {
  app.startDiscovery();
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => _LslStreamsDialog(app),
    );
  } finally {
    app.stopDiscovery();
  }
}

IconData _icon(LslStreamDescription s) {
  if (s.format.isString) return Icons.label_outline;
  return switch (kindFromType(s.type)) {
    Kind.eeg || Kind.emg => Icons.show_chart,
    Kind.imu => Icons.threed_rotation,
    Kind.audio => Icons.graphic_eq,
    Kind.event => Icons.flag_outlined,
    Kind.other => Icons.stream,
  };
}

class _LslStreamsDialog extends StatelessWidget {
  final LslProvider app;
  const _LslStreamsDialog(this.app);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final streams = app.streams;
        final body = streams.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 12),
                    const Text('Looking for LSL streams…'),
                    const SizedBox(height: 8),
                    Text(
                      'Streams on other computers are found by multicast. '
                      'If your network blocks it, add their addresses as '
                      'known peers in LSL settings.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final s in streams)
                    ListTile(
                      leading: Icon(_icon(s)),
                      title: Text(s.name),
                      subtitle: Text(s.summary),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Stream info',
                            onPressed: () => showLslStreamInfo(
                              context,
                              s,
                              session: app.sessionOf(s.key),
                            ),
                            icon: const Icon(Icons.info_outline),
                          ),
                          app.isOpen(s.key)
                              ? const Chip(label: Text('Open'))
                              : app.connecting.contains(s.key)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : FilledButton.tonal(
                                  onPressed: () => app.connect(s),
                                  child: const Text('View'),
                                ),
                        ],
                      ),
                    ),
                ],
              );
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('LSL streams')),
              Text('liblsl ${lsl.version}', style: theme.textTheme.bodySmall),
            ],
          ),
          content: SizedBox(width: 560, child: body),
          actions: [
            TextButton(
              onPressed: () => showLslSettings(context, app),
              child: const Text('Settings…'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// Advanced LSL settings, with defaults that suit most uses.
Future<void> showLslSettings(BuildContext context, LslProvider app) =>
    showDialog<void>(context: context, builder: (_) => _LslSettingsDialog(app));

class _LslSettingsDialog extends StatefulWidget {
  final LslProvider app;
  const _LslSettingsDialog(this.app);

  @override
  State<_LslSettingsDialog> createState() => _LslSettingsDialogState();
}

class _LslSettingsDialogState extends State<_LslSettingsDialog> {
  late LslOptions _o = widget.app.app.prefs.lsl;

  /// Text fields are rebuilt with new values after "Restore defaults".
  int _generation = 0;

  void _restore() => setState(() {
    _o = const LslOptions();
    _generation++;
  });

  Future<void> _ok() async {
    final navigator = Navigator.of(context);
    final restart = _o.network != widget.app.app.prefs.lsl.network;
    await widget.app.setOptions(_o);
    if (restart) {
      widget.app.app.setStatus('LSL network settings apply after a restart');
    }
    navigator.pop();
  }

  Widget _number(
    String label,
    int value,
    String suffix,
    String help,
    ValueChanged<int> onChanged, {
    int min = 0,
    int max = 100000,
  }) => SizedBox(
    width: 200,
    child: TextFormField(
      key: ValueKey('$label$_generation'),
      initialValue: '$value',
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: help,
        helperMaxLines: 3,
        isDense: true,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (t) {
        final v = int.tryParse(t ?? '');
        return v == null || v < min || v > max ? '$min to $max' : null;
      },
      onChanged: (t) {
        final v = int.tryParse(t);
        if (v != null && v >= min && v <= max) onChanged(v);
      },
    ),
  );

  Widget _switch(
    String label,
    String help,
    bool value,
    ValueChanged<bool>? onChanged,
  ) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(help),
    value: value,
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = _o.inlet, out = _o.outlet, net = _o.network;
    void inlet(LslInletOptions v) => setState(() => _o = _o.copyWith(inlet: v));
    void outlet(LslOutletOptions v) =>
        setState(() => _o = _o.copyWith(outlet: v));
    void network(LslNetworkOptions v) =>
        setState(() => _o = _o.copyWith(network: v));
    Widget heading(String s, [String? help]) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s, style: theme.textTheme.titleSmall),
          if (help != null) Text(help, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The defaults suit most uses. Larger intervals and chunks use '
          'less CPU at the cost of latency.',
          style: theme.textTheme.bodySmall,
        ),
        heading('Receiving', 'Applies to streams opened afterwards.'),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _number(
              'Collect every',
              i.pullIntervalMs,
              'ms',
              'How often new samples are picked up.',
              (v) => inlet(i.copyWith(pullIntervalMs: v)),
              min: 1,
              max: 1000,
            ),
            _number(
              'Chunk size',
              i.chunkSize,
              'samples',
              'Per network packet asked of the sender; 0 lets it decide.',
              (v) => inlet(i.copyWith(chunkSize: v)),
            ),
            _number(
              'Buffer',
              i.bufferS,
              's',
              'Kept by LSL if the app falls behind.',
              (v) => inlet(i.copyWith(bufferS: v)),
              min: 1,
              max: 3600,
            ),
          ],
        ),
        _switch(
          'Synchronize clocks',
          'Put time stamps on this computer\'s clock.',
          i.clockSync,
          (v) => inlet(i.copyWith(clockSync: v)),
        ),
        _switch(
          'Remove jitter',
          'Smooth the time stamps of regular streams.',
          i.dejitter,
          (v) => inlet(i.copyWith(dejitter: v)),
        ),
        _switch(
          'Monotonic time stamps',
          'Never let time stamps go backwards (with jitter removal).',
          i.monotonize,
          i.dejitter ? (v) => inlet(i.copyWith(monotonize: v)) : null,
        ),
        _switch(
          'Reconnect',
          'Carry on when a stream that went away comes back.',
          i.recover,
          (v) => inlet(i.copyWith(recover: v)),
        ),
        heading(
          'Publishing',
          'The device over LSL and recording replays; applies when '
              'started.',
        ),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _number(
              'Push every',
              out.pushIntervalMs,
              'ms',
              'Samples are collected and sent together.',
              (v) => outlet(out.copyWith(pushIntervalMs: v)),
              min: 1,
              max: 1000,
            ),
            _number(
              'Chunk size',
              out.chunkSize,
              'samples',
              'Per network packet; 0 sends each push as it comes.',
              (v) => outlet(out.copyWith(chunkSize: v)),
            ),
            _number(
              'Buffer',
              out.bufferS,
              's',
              'Kept for a consumer that falls behind.',
              (v) => outlet(out.copyWith(bufferS: v)),
              min: 1,
              max: 3600,
            ),
          ],
        ),
        _switch(
          'Blocking zero-copy sends',
          'Less CPU for many channels, but a slow consumer holds up '
              'sending. Not used for marker streams.',
          out.syncBlocking,
          (v) => outlet(out.copyWith(syncBlocking: v)),
        ),
        _switch(
          'Loop replays',
          'Start a recording over when its replay reaches the end.',
          _o.replayLoop,
          (v) => setState(() => _o = _o.copyWith(replayLoop: v)),
        ),
        heading('Network', 'Applies after restarting hyprview.'),
        TextFormField(
          key: ValueKey('peers$_generation'),
          initialValue: net.knownPeers.join(', '),
          decoration: const InputDecoration(
            labelText: 'Known peers',
            helperText:
                'Addresses or host names to find streams on without '
                'multicast, separated by commas. Needed on every computer.',
            helperMaxLines: 2,
            isDense: true,
          ),
          onChanged: (t) => network(
            LslNetworkOptions(
              knownPeers: [
                for (final p in t.split(RegExp(r'[,\s]+')))
                  if (p.isNotEmpty) p,
              ],
              sessionId: net.sessionId,
              scope: net.scope,
              ipv6: net.ipv6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: TextFormField(
                key: ValueKey('session$_generation'),
                initialValue: net.sessionId,
                decoration: const InputDecoration(
                  labelText: 'Session id',
                  helperText: 'Only the same id sees each other.',
                  isDense: true,
                ),
                onChanged: (t) => network(
                  LslNetworkOptions(
                    knownPeers: net.knownPeers,
                    sessionId: t.trim().isEmpty ? 'default' : t.trim(),
                    scope: net.scope,
                    ipv6: net.ipv6,
                  ),
                ),
              ),
            ),
            DropdownMenu<LslScope>(
              label: const Text('Discovery reaches'),
              initialSelection: net.scope,
              key: ValueKey('scope$_generation'),
              dropdownMenuEntries: const [
                DropdownMenuEntry(
                  value: LslScope.machine,
                  label: 'This computer',
                ),
                DropdownMenuEntry(value: LslScope.link, label: 'Subnet'),
                DropdownMenuEntry(value: LslScope.site, label: 'Site'),
                DropdownMenuEntry(
                  value: LslScope.organization,
                  label: 'Organization',
                ),
                DropdownMenuEntry(value: LslScope.global, label: 'Global'),
              ],
              onSelected: (v) => network(
                LslNetworkOptions(
                  knownPeers: net.knownPeers,
                  sessionId: net.sessionId,
                  scope: v ?? net.scope,
                  ipv6: net.ipv6,
                ),
              ),
            ),
            FilterChip(
              label: const Text('IPv6'),
              selected: net.ipv6,
              onSelected: (v) => network(
                LslNetworkOptions(
                  knownPeers: net.knownPeers,
                  sessionId: net.sessionId,
                  scope: net.scope,
                  ipv6: v,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    final actions = [
      TextButton(onPressed: _restore, child: const Text('Restore defaults')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _ok, child: const Text('OK')),
    ];
    if (narrow) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('LSL settings'),
            leading: const CloseButton(),
            actions: [TextButton(onPressed: _ok, child: const Text('Save'))],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: body,
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('LSL settings'),
      content: SizedBox(width: 680, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }
}

String _pretty(String xml) {
  if (xml.isEmpty) return '';
  try {
    return XmlDocument.parse(xml).toXmlString(pretty: true, indent: '  ');
  } catch (_) {
    return xml;
  }
}

String _field(String xml, String name) {
  if (xml.isEmpty) return '';
  try {
    final info = XmlDocument.parse(xml).rootElement;
    return info.getElement(name)?.innerText.trim() ?? '';
  } catch (_) {
    return '';
  }
}

/// Everything about [stream]: its header fields, its full info XML, and
/// for a stream open in [session], the live clock offset and rates.
Future<void> showLslStreamInfo(
  BuildContext context,
  LslStreamDescription stream, {
  LslSession? session,
}) => showDialog<void>(
  context: context,
  builder: (_) => _LslStreamInfoDialog(stream, session),
);

class _LslStreamInfoDialog extends StatefulWidget {
  final LslStreamDescription stream;
  final LslSession? session;
  const _LslStreamInfoDialog(this.stream, this.session);

  @override
  State<_LslStreamInfoDialog> createState() => _LslStreamInfoDialogState();
}

class _LslStreamInfoDialogState extends State<_LslStreamInfoDialog> {
  Timer? _timer;
  double? _offset;
  String? _offsetError;

  /// Clock offsets measured while open: (LSL time, offset).
  final List<(double, double)> _offsets = [];

  @override
  void initState() {
    super.initState();
    if (widget.session != null) {
      _poll();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    }
  }

  Future<void> _poll() async {
    final s = widget.session;
    if (s == null || s.closed) return;
    try {
      final o = await s.inlet.timeCorrection();
      if (mounted) {
        setState(() {
          _offset = o;
          _offsetError = null;
          _offsets.add((lsl.clock(), o));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _offsetError = '$e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Least-squares slope of the offsets over time: how fast the sender's
  /// clock drifts against this computer's.
  double _drift() {
    final n = _offsets.length;
    final t0 = _offsets.first.$1;
    var st = 0.0, so = 0.0, stt = 0.0, sto = 0.0;
    for (final (t, o) in _offsets) {
      final x = t - t0;
      st += x;
      so += o;
      stt += x * x;
      sto += x * o;
    }
    final det = n * stt - st * st;
    return det == 0 ? 0 : (n * sto - st * so) / det;
  }

  double _range() {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final (_, o) in _offsets) {
      lo = math.min(lo, o);
      hi = math.max(hi, o);
    }
    return hi - lo;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.stream;
    final session = widget.session;
    final full = session?.inlet.fullXml ?? '';
    final xml = full.isNotEmpty ? full : s.xml;
    String num(double v, [int digits = 3]) => v.toStringAsFixed(digits);
    final created = double.tryParse(_field(xml, 'created_at'));
    final rows = <(String, String)>[
      ('Name', s.name),
      ('Type', s.type),
      ('Channels', '${s.channelCount}'),
      ('Nominal rate', s.rate > 0 ? '${num(s.rate, 2)} Hz' : 'irregular'),
      ('Format', s.format.name),
      ('Source ID', s.sourceId.isEmpty ? '—' : s.sourceId),
      ('Host', s.hostname.isEmpty ? '—' : s.hostname),
      ('UID', s.uid.isEmpty ? '—' : s.uid),
      ('Session', _field(xml, 'session_id')),
      ('Version', _field(xml, 'version')),
      if (created != null && created > 0)
        ('Created', '${num(lsl.clock() - created, 1)} s ago'),
      if (session != null) ...[
        (
          'Clock offset',
          _offsetError != null
              ? 'unavailable ($_offsetError)'
              : _offset == null
              ? 'measuring…'
              : '${num(_offset! * 1000, 3)} ms',
        ),
        (
          'Measured rate',
          session.measuredRate == null
              ? '—'
              : '${num(session.measuredRate!, 3)} Hz',
        ),
        ('Received', '${session.received} samples'),
        if (session.intervalStd != null)
          (
            'Interval jitter',
            '${num(session.intervalStd! * 1000)} ms (s.d.)'
                '${s.rate > 0 ? ' · nominal ${num(1000 / s.rate)} ms' : ''}',
          ),
        if (session.largestInterval != null)
          ('Largest interval', '${num(session.largestInterval! * 1000)} ms'),
        if (session.backwards > 0)
          ('Backwards', '${session.backwards} time stamps went back'),
        if (_offsets.length >= 2)
          (
            'Offset drift',
            '${num(_drift() * 1e6, 1)} µs/s over '
                '${num(_offsets.last.$1 - _offsets.first.$1, 0)} s '
                '(range ${num(_range() * 1000)} ms)',
          ),
        if (session.lostSampleCount > 0)
          ('Filled gaps', '${session.lostSampleCount} samples'),
      ],
    ];
    return AlertDialog(
      title: Text(s.name),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(),
                },
                children: [
                  for (final (k, v) in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 4),
                          child: Text(k, style: theme.textTheme.labelMedium),
                        ),
                        SelectableText(v),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Stream info', style: theme.textTheme.titleSmall),
              if (full.isEmpty)
                Text(
                  session == null
                      ? 'The description (desc: channels and so on) is '
                            'fetched when the stream is opened.'
                      : 'The sender gave no description.',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: theme.colorScheme.surfaceContainerHighest,
                child: SelectableText(
                  xml.isEmpty ? '(none)' : _pretty(xml),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: xml)),
          child: const Text('Copy XML'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Streams on the network to record: all are chosen at first. Null if
/// cancelled.
Future<List<LslStreamDescription>?> showLslRecordStreams(
  BuildContext context,
  LslProvider app,
) => showLslStreamPicker(
  context,
  app,
  title: 'Record LSL streams to XDF',
  note:
      'Time stamps are recorded as sent, with clock offsets, as LabRecorder '
      'does; readers (pyxdf, this viewer) synchronise them.',
  verb: 'Record',
  icon: Icons.fiber_manual_record,
);

/// Streams on the network to choose from (all at first), under [title]
/// with a [note] and [extra] settings; the button says [verb] and the
/// number chosen. Null if cancelled.
Future<List<LslStreamDescription>?> showLslStreamPicker(
  BuildContext context,
  LslProvider app, {
  required String title,
  String note = '',
  required String verb,
  IconData icon = Icons.check,
  Widget? extra,
}) async {
  app.startDiscovery();
  try {
    return await showDialog<List<LslStreamDescription>>(
      context: context,
      builder: (_) => _StreamPickerDialog(app, title, note, verb, icon, extra),
    );
  } finally {
    app.stopDiscovery();
  }
}

class _StreamPickerDialog extends StatefulWidget {
  final LslProvider app;
  final String title;
  final String note;
  final String verb;
  final IconData icon;
  final Widget? extra;
  const _StreamPickerDialog(
    this.app,
    this.title,
    this.note,
    this.verb,
    this.icon,
    this.extra,
  );

  @override
  State<_StreamPickerDialog> createState() => _StreamPickerDialogState();
}

class _StreamPickerDialogState extends State<_StreamPickerDialog> {
  /// Streams left out, by key; new ones are in.
  final Set<String> _skipped = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final streams = widget.app.streams;
        final chosen = [
          for (final s in streams)
            if (!_skipped.contains(s.key)) s,
        ];
        return AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
            width: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (widget.note.isNotEmpty)
                  Text(widget.note, style: theme.textTheme.bodySmall),
                ?widget.extra,
                if (streams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Looking for LSL streams…'),
                  ),
                for (final s in streams)
                  CheckboxListTile(
                    value: !_skipped.contains(s.key),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _skipped.remove(s.key)
                          : _skipped.add(s.key),
                    ),
                    secondary: Icon(_icon(s)),
                    title: Text(s.name),
                    subtitle: Text(s.summary),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(context, chosen),
              icon: Icon(widget.icon),
              label: Text('${widget.verb} ${chosen.length}'),
            ),
          ],
        );
      },
    );
  }
}

/// Share streams over the network: choose them, the port and a token.
Future<void> showLslShare(BuildContext context, LslProvider app) async {
  final port = TextEditingController(text: '8765');
  final token = TextEditingController();
  try {
    final chosen = await showLslStreamPicker(
      context,
      app,
      title: 'Share LSL streams over the network',
      note:
          'Other computers (on any network that reaches this one) and '
          'browsers connect with "Connect to an LSL bridge…" at '
          'ws://<this computer>:<port>.',
      verb: 'Share',
      icon: Icons.share,
      extra: Row(
        children: [
          SizedBox(
            width: 100,
            child: TextField(
              controller: port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: token,
              decoration: const InputDecoration(
                labelText: 'Token (optional)',
                helperText: 'Clients must give it to connect',
              ),
            ),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    await app.share(
      chosen,
      port: int.tryParse(port.text.trim()) ?? 8765,
      token: token.text.trim(),
    );
  } finally {
    port.dispose();
    token.dispose();
  }
}

/// Connect to an LSL bridge and view its streams.
Future<void> showLslBridge(BuildContext context, LslProvider app) =>
    showDialog<void>(context: context, builder: (_) => _BridgeDialog(app));

class _BridgeDialog extends StatefulWidget {
  final LslProvider app;
  const _BridgeDialog(this.app);

  @override
  State<_BridgeDialog> createState() => _BridgeDialogState();
}

class _BridgeDialogState extends State<_BridgeDialog> {
  final _url = TextEditingController(text: 'ws://');
  final _token = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    var text = _url.text.trim();
    if (!text.contains('://')) text = 'ws://$text';
    final url = Uri.tryParse(text);
    if (url == null || url.host.isEmpty) {
      setState(() => _error = 'Not a ws:// address');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final e = await widget.app.connectBridge(url, token: _token.text.trim());
    if (mounted) {
      setState(() {
        _connecting = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) => AlertDialog(
        title: const Text('LSL bridges'),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                        labelText: 'Bridge address',
                        hintText: 'ws://192.168.1.20:8765',
                      ),
                      onSubmitted: (_) => _connect(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _token,
                      decoration: const InputDecoration(labelText: 'Token'),
                      onSubmitted: (_) => _connect(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _connecting ? null : _connect,
                    child: const Text('Connect'),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              for (final b in widget.app.bridges) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${b.url}'
                        '${b.closed ? ' (disconnected: ${b.error})' : ''}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      'clock offset ${(b.offset * 1000).toStringAsFixed(1)} ms',
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: () => widget.app.disconnectBridge(b),
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
                for (final s in b.streams)
                  ListTile(
                    dense: true,
                    leading: Icon(_icon(s.description)),
                    title: Text(s.description.name),
                    subtitle: Text(s.description.summary),
                    trailing: widget.app.isOpen(s.description.key)
                        ? const Chip(label: Text('Open'))
                        : FilledButton.tonal(
                            onPressed: b.closed
                                ? null
                                : () => widget.app.viewBridged(b, s),
                            child: const Text('View'),
                          ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Send test streams and markers over LSL: a synthetic signal generator
/// and a marker stream to annotate a session.
Future<void> showLslTestOutlets(BuildContext context, LslProvider app) =>
    showDialog<void>(context: context, builder: (_) => _TestOutletsDialog(app));

class _TestOutletsDialog extends StatefulWidget {
  final LslProvider app;
  const _TestOutletsDialog(this.app);

  @override
  State<_TestOutletsDialog> createState() => _TestOutletsDialogState();
}

class _TestOutletsDialogState extends State<_TestOutletsDialog> {
  final _name = TextEditingController(text: 'Test signal');
  final _channels = TextEditingController(text: '8');
  final _rate = TextEditingController(text: '250');
  final _frequency = TextEditingController(text: '10');
  final _marker = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _channels, _rate, _frequency, _marker]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final channels = int.tryParse(_channels.text.trim());
    final rate = double.tryParse(_rate.text.trim());
    final frequency = double.tryParse(_frequency.text.trim());
    if (channels == null || channels < 1 || rate == null || rate <= 0) return;
    await widget.app.startGenerator(
      name: _name.text.trim().isEmpty ? 'Test signal' : _name.text.trim(),
      channels: channels,
      rate: rate,
      frequency: frequency ?? 10,
    );
  }

  Future<void> _send() async {
    final text = _marker.text.trim();
    if (text.isEmpty) return;
    await widget.app.sendMarker(text);
    _marker.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _marker.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget field(TextEditingController c, String label, {double w = 90}) =>
        SizedBox(
          width: w,
          child: TextField(
            controller: c,
            decoration: InputDecoration(isDense: true, labelText: label),
          ),
        );
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) => AlertDialog(
        title: const Text('LSL test outlets'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Signal generator', style: theme.textTheme.titleSmall),
                Text(
                  'Sine waves (channel n at n × the frequency) with noise, '
                  'in real time.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    field(_name, 'Name', w: 160),
                    field(_channels, 'Channels'),
                    field(_rate, 'Rate (Hz)'),
                    field(_frequency, 'Frequency (Hz)', w: 110),
                    FilledButton.tonal(
                      onPressed: _start,
                      child: const Text('Start'),
                    ),
                  ],
                ),
                for (final g in widget.app.generators)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.graphic_eq),
                    title: Text(g.name),
                    subtitle: Text(
                      '${g.outlet.spec.channelCount} ch · '
                      '${g.rate} Hz · ${g.sent} samples sent',
                    ),
                    trailing: TextButton(
                      onPressed: () => widget.app.stopGenerator(g),
                      child: const Text('Stop'),
                    ),
                  ),
                const Divider(height: 32),
                Text('Markers', style: theme.textTheme.titleSmall),
                Text(
                  'Sent on the stream "${widget.app.app.config.title} '
                  'markers", stamped when sent.',
                  style: theme.textTheme.bodySmall,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _marker,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Marker text',
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _send,
                      child: const Text('Send'),
                    ),
                  ],
                ),
                if (widget.app.markers != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${widget.app.markers!.sent} sent',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Forward the current tab's stream under another name, and the forwards
/// running.
Future<void> showLslForward(BuildContext context, LslProvider app) =>
    showDialog<void>(context: context, builder: (_) => _ForwardDialog(app));

class _ForwardDialog extends StatefulWidget {
  final LslProvider app;
  const _ForwardDialog(this.app);

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  late final TabEntry? _tab = widget.app.app.currentTab?.session is LslSession
      ? widget.app.app.currentTab
      : null;
  late final _name = TextEditingController(
    text: _tab == null ? '' : '${_tab.group.info.name} (forwarded)',
  );
  bool _shownOnly = false;
  bool _processed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tab = _tab;
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) => AlertDialog(
        title: const Text('Forward LSL streams'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tab != null) ...[
                  Text(
                    'Publish ${tab.group.info.name} again as a new stream, '
                    'with the time stamps it arrived with.',
                    style: theme.textTheme.bodySmall,
                  ),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _shownOnly,
                    onChanged: (v) => setState(() => _shownOnly = v ?? false),
                    title: Text(
                      'Only the ${tab.controller.lanes.length} shown channels',
                    ),
                  ),
                  if (!tab.group.info.irregular)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _processed,
                      onChanged: (v) => setState(() => _processed = v ?? false),
                      title: const Text(
                        "With this tab's reference and filters",
                      ),
                      subtitle: Text(tab.controller.referenceSummary),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () {
                        final name = _name.text.trim();
                        if (name.isEmpty) return;
                        widget.app.forward(
                          tab,
                          name: name,
                          shownOnly: _shownOnly,
                          processed: _processed,
                        );
                      },
                      child: const Text('Forward'),
                    ),
                  ),
                ],
                if (widget.app.forwards.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('Forwarding', style: theme.textTheme.titleSmall),
                  for (final f in widget.app.forwards)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.forward),
                      title: Text(f.name),
                      subtitle: Text(
                        'from ${f.session.info.name} · '
                        '${f.channels.length} ch · ${f.sent} samples',
                      ),
                      trailing: TextButton(
                        onPressed: () => widget.app.stopForward(f),
                        child: const Text('Stop'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
