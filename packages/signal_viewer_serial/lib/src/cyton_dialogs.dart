import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:signal_viewer/signal_viewer.dart';

import 'cyton_session.dart';

const _inputLabels = {
  CytonInput.normal: 'Normal',
  CytonInput.shorted: 'Shorted',
  CytonInput.biasMeasure: 'Bias measure',
  CytonInput.mvdd: 'Supply (MVDD)',
  CytonInput.temperature: 'Temperature',
  CytonInput.testSignal: 'Test signal',
  CytonInput.biasDrp: 'Bias drive P',
  CytonInput.biasDrn: 'Bias drive N',
};

String _roleLabel(Kind k) => k == Kind.other ? 'Other' : k.label;

/// A dialog that runs board commands one at a time, showing the last
/// error.
mixin _Busy<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<R?> run<R>(Future<R> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      return await f();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget errorText(BuildContext context) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
}

// -- board settings -----------------------------------------------------------

/// The channels of [session]'s board (role, on, gain, input, bias, SRB2,
/// SRB1) and its test signals. Changes go to the board at once.
Future<void> showCytonSettings(BuildContext context, CytonSession session) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SettingsDialog(session),
    );

class _SettingsDialog extends StatefulWidget {
  final CytonSession session;
  const _SettingsDialog(this.session);

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog>
    with _Busy<_SettingsDialog> {
  CytonSession get s => widget.session;
  CytonBoard get board => s.board;

  Future<void> _set(int ch, CytonChannelSettings v) =>
      run(() => s.configure(ch, v));

  /// EMG channels are bipolar (no SRB2), EEG ones referenced to SRB2.
  Future<void> _role(int ch, Kind role) async {
    s.setRole(ch, role);
    final c = board.channels[ch - 1];
    if (role == Kind.emg && c.srb2) await _set(ch, c.copyWith(srb2: false));
    if (role == Kind.eeg && !c.srb2) await _set(ch, c.copyWith(srb2: true));
    setState(() {});
  }

  Widget _check(bool value, ValueChanged<bool> onChanged) => Checkbox(
    value: value,
    visualDensity: VisualDensity.compact,
    onChanged: busy ? null : (v) => onChanged(v ?? value),
  );

  Widget _dropdown<V>(
    V value,
    Map<V, String> items,
    ValueChanged<V> onChanged,
  ) => DropdownButton<V>(
    value: value,
    isDense: true,
    underline: const SizedBox.shrink(),
    items: [
      for (final e in items.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: busy ? null : (v) => v == null ? null : onChanged(v),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = theme.textTheme.labelMedium;
    final testOn = board.testSignal != null;
    TableRow row(int ch) {
      final c = board.channels[ch - 1];
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('$ch  ${s.labels[ch - 1]}'),
          ),
          _dropdown(s.roles[ch - 1], {
            for (final r in cytonRoles) r: _roleLabel(r),
          }, (r) => _role(ch, r)),
          _check(c.enabled, (v) => run(() => s.setEnabled(ch, v))),
          _dropdown(c.gain, {
            for (final g in cytonGains) g: '×$g',
          }, (g) => _set(ch, c.copyWith(gain: g))),
          _dropdown(
            c.input,
            _inputLabels,
            (i) => _set(ch, c.copyWith(input: i)),
          ),
          _check(c.bias, (v) => _set(ch, c.copyWith(bias: v))),
          _check(c.srb2, (v) => _set(ch, c.copyWith(srb2: v))),
          _check(c.srb1, (v) => _set(ch, c.copyWith(srb1: v))),
        ],
      );
    }

    Widget head(String text, String tip) => Tooltip(
      message: tip,
      child: Text(text, style: header),
    );

    return AlertDialog(
      title: const Text('Cyton settings'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Changes are sent to the board at once. EMG channels are '
                'set bipolar (without SRB2) and appear in a tab of their '
                'own.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: [
                    TableRow(
                      children: [
                        head('Channel', 'Number and name'),
                        head('Use', 'Which tab the channel is shown in'),
                        head('On', 'Powered up (off reads 0)'),
                        head('Gain', 'Amplifier gain'),
                        head('Input', 'What the channel measures'),
                        head('Bias', 'Included in the bias (driven ground)'),
                        head('SRB2', 'Referenced to SRB2 (usual for EEG)'),
                        head('SRB1', 'Referenced to SRB1 (common to all)'),
                      ],
                    ),
                    for (var ch = 1; ch <= board.channelCount; ch++) row(ch),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text('Test signal'),
                  DropdownButton<CytonTestSignal?>(
                    value: board.testSignal,
                    items: [
                      const DropdownMenuItem(child: Text('None')),
                      for (final t in CytonTestSignal.values)
                        DropdownMenuItem(value: t, child: Text(t.label)),
                    ],
                    onChanged: busy
                        ? null
                        : (t) => run(() => s.setTestSignal(t)),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => run(s.resetChannels),
                    child: const Text('Reset to defaults'),
                  ),
                ],
              ),
              if (testOn)
                Text(
                  'All channels show the test signal; None restores their '
                  'settings.',
                  style: theme.textTheme.bodySmall,
                ),
              errorText(context),
              const SizedBox(height: 8),
              Text(
                board.info
                    .replaceAll(r'$$$', '')
                    .trim()
                    .split('\n')
                    .where((l) => l.isNotEmpty)
                    .join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (busy)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// -- SD card ------------------------------------------------------------------

/// Start logging to the SD card: for how long, at which rate. Returns the
/// board's reply, or null if cancelled.
Future<String?> showCytonSdDialog(BuildContext context, CytonSession session) =>
    showDialog<String>(context: context, builder: (_) => _SdDialog(session));

class _SdDialog extends StatefulWidget {
  final CytonSession session;
  const _SdDialog(this.session);

  @override
  State<_SdDialog> createState() => _SdDialogState();
}

class _SdDialogState extends State<_SdDialog> with _Busy<_SdDialog> {
  final _minutes = TextEditingController(text: '60');
  CytonSampleRate _rate = CytonSampleRate.hz250;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  (CytonSdDuration?, String) get _block {
    final m = double.tryParse(_minutes.text.trim());
    if (m == null || m <= 0) return (null, 'Minutes: a number above 0');
    try {
      final d = CytonSdDuration.forMinutes(m, _rate);
      final room = d.minutes * 250 / _rate.hz;
      return (
        d,
        'Reserves room for ${room < 60 ? '${room.toStringAsFixed(0)} min' : '${(room / 60).toStringAsFixed(room < 600 ? 1 : 0)} h'} '
            'at ${_rate.hz} Hz (command ${d.code})',
      );
    } on ArgumentError catch (e) {
      return (null, '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (block, note) = _block;
    return AlertDialog(
      title: const Text('Record to the SD card'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The board writes its samples to the card while it streams. '
              'At 250 Hz the samples are also shown here; at higher rates '
              'the board does not stream, and only the card has them. '
              'Stop the recording from the Cyton menu.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minutes,
                    decoration: const InputDecoration(
                      labelText: 'Longest duration (minutes)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<CytonSampleRate>(
                  value: _rate,
                  items: [
                    for (final r in CytonSampleRate.values)
                      DropdownMenuItem(value: r, child: Text('${r.hz} Hz')),
                  ],
                  onChanged: (r) => setState(() => _rate = r ?? _rate),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note,
              style: block == null
                  ? TextStyle(color: theme.colorScheme.error)
                  : theme.textTheme.bodySmall,
            ),
            errorText(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy || block == null
              ? null
              : () async {
                  final reply = await run(
                    () => widget.session.startSd(block, _rate),
                  );
                  if (reply != null && context.mounted) {
                    Navigator.pop(context, reply);
                  }
                },
          child: const Text('Start'),
        ),
      ],
    );
  }
}

// -- impedance ----------------------------------------------------------------

/// Measure the impedance of the electrodes, one channel after another.
Future<void> showCytonImpedance(BuildContext context, CytonSession session) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ImpedanceDialog(session),
    );

class _ImpedanceDialog extends StatefulWidget {
  final CytonSession session;
  const _ImpedanceDialog(this.session);

  @override
  State<_ImpedanceDialog> createState() => _ImpedanceDialogState();
}

class _ImpedanceDialogState extends State<_ImpedanceDialog>
    with _Busy<_ImpedanceDialog> {
  final _ohms = <int, double>{};
  CytonLeadOff _pin = CytonLeadOff.n;
  int? _measuring;

  CytonSession get s => widget.session;

  Future<void> _measure(Iterable<int> channels) async {
    final list = channels.toList();
    setState(() {
      for (final c in list) {
        _ohms.remove(c);
      }
      _measuring = list.first;
    });
    await run(
      () => s.measureImpedances(
        list,
        pin: _pin,
        onChannel: (c, ohms) {
          if (!mounted) return;
          final i = list.indexOf(c);
          setState(() {
            _ohms[c] = ohms;
            _measuring = i + 1 < list.length ? list[i + 1] : null;
          });
        },
      ),
    );
    if (mounted) setState(() => _measuring = null);
  }

  Color? _color(double ohms, ColorScheme scheme) => ohms < 10e3
      ? Colors.green.shade600
      : ohms < 50e3
      ? Colors.orange.shade700
      : scheme.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = s.board.channelCount;
    final ready = s.live;
    return AlertDialog(
      title: const Text('Electrode impedance'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A small current (6 nA at 31.25 Hz) is passed through one '
                'electrode at a time, for about 2.5 s each; the channel is '
                'set to gain 1 meanwhile. Below 10 kΩ is good. N is the '
                'bottom pin, where the electrodes go when they are '
                'referenced to SRB2; P is the top pin.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<CytonLeadOff>(
                segments: const [
                  ButtonSegment(value: CytonLeadOff.n, label: Text('N pins')),
                  ButtonSegment(value: CytonLeadOff.p, label: Text('P pins')),
                ],
                selected: {_pin},
                onSelectionChanged: busy
                    ? null
                    : (v) => setState(() {
                        _pin = v.first;
                        _ohms.clear();
                      }),
              ),
              if (!ready)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The board must be streaming at 250 Hz.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              for (var ch = 1; ch <= n; ch++)
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text('$ch  ${s.labels[ch - 1]}'),
                    ),
                    Expanded(
                      child: _measuring == ch
                          ? const LinearProgressIndicator()
                          : _ohms[ch] == null
                          ? const Text('–')
                          : Text(
                              '${(_ohms[ch]! / 1000).toStringAsFixed(1)} kΩ',
                              style: TextStyle(
                                color: _color(_ohms[ch]!, theme.colorScheme),
                              ),
                            ),
                    ),
                    IconButton(
                      tooltip: 'Measure this channel',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy || !ready ? null : () => _measure([ch]),
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                  ],
                ),
              errorText(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: busy || !ready
              ? null
              : () => _measure([for (var c = 1; c <= n; c++) c]),
          child: const Text('Measure all'),
        ),
      ],
    );
  }
}

// -- markers ------------------------------------------------------------------

/// Send markers to the board (in the marker board mode): a key pressed
/// while the dialog is open, or a value from 128 to 239.
Future<void> showCytonMarkers(BuildContext context, CytonSession session) =>
    showDialog<void>(context: context, builder: (_) => _MarkerDialog(session));

class _MarkerDialog extends StatefulWidget {
  final CytonSession session;
  const _MarkerDialog(this.session);

  @override
  State<_MarkerDialog> createState() => _MarkerDialogState();
}

class _MarkerDialogState extends State<_MarkerDialog>
    with _Busy<_MarkerDialog> {
  final _sent = <int>[];
  final _value = TextEditingController(text: '128');
  final _focus = FocusNode();

  @override
  void dispose() {
    _value.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send(int value) async {
    await run(() => widget.session.marker(value));
    if (error == null && mounted) setState(() => _sent.add(value));
  }

  void _key(KeyEvent e) {
    final c = e.character;
    if (e is! KeyDownEvent || c == null || c.length != 1) return;
    final v = c.codeUnitAt(0);
    if (cytonMarkerIsSafe(v)) {
      _send(v);
    } else if (v > 0x20 && v < 0x7F) {
      setState(
        () => error = '$c is a board command; use $cytonSafeMarkerChars',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = int.tryParse(_value.text.trim());
    final valid = v != null && v >= 128 && v <= 239;
    return AlertDialog(
      title: const Text('Markers'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A marker goes into the samples (the markers tab, and an SD '
              'card recording). Only values that the board cannot take for '
              'commands are sent: 128 to 239, or the keys '
              '$cytonSafeMarkerChars. Markers sent just after streaming '
              'starts can be lost.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            KeyboardListener(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _key,
              child: Text(
                'Press a key to send it…',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _value,
                    decoration: const InputDecoration(labelText: 'Value'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => valid ? _send(v) : null,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: valid && !busy ? () => _send(v) : null,
                  child: const Text('Send'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _sent.isEmpty
                  ? 'None sent yet'
                  : 'Sent ${_sent.length}: '
                        '${_sent.reversed.take(20).map(cytonMarkerLabel).join(' ')}',
              style: theme.textTheme.bodySmall,
            ),
            errorText(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// The first open Cyton of [app], if any.
CytonSession? cytonOf(AppState app) {
  final current = app.currentTab?.session;
  if (current is CytonSession && !current.closed) return current;
  for (final s in app.sessions) {
    if (s is CytonSession && !s.closed) return s;
  }
  return null;
}
