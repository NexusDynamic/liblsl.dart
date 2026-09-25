import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../display/manchester.dart';
import '../../model/groups.dart';
import '../../model/stream_info.dart';
import '../../model/view_settings.dart';
import '../../settings/prefs.dart';
import '../../viewer/source.dart';
import '../app_state.dart';
import '../widgets/widgets.dart';

/// Narrower than this, dialogs use the whole screen and rows stack.
const narrowWidth = 760.0;

/// Preferences: appearance, what new tabs start with, and memory.
Future<void> showPreferences(BuildContext context, Preferences prefs) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PreferencesDialog(prefs),
    );

class _PreferencesDialog extends StatefulWidget {
  final Preferences prefs;
  const _PreferencesDialog(this.prefs);

  @override
  State<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<_PreferencesDialog> {
  late ThemeMode _theme = widget.prefs.themeMode;
  late double _lineWidth = widget.prefs.lineWidth;
  late bool _antialias = widget.prefs.antialias;
  late int _cacheMb = widget.prefs.cacheMb;
  late Map<Kind, KindDefaults> _defaults = Map.of(widget.prefs.defaults);

  void _restore() => setState(() {
    _theme = ThemeMode.system;
    _lineWidth = 1;
    _antialias = true;
    _cacheMb = Preferences.defaultCacheMb;
    _defaults = Map.of(KindDefaults.factory);
  });

  Future<void> _ok() async {
    final p = widget.prefs
      ..themeMode = _theme
      ..lineWidth = _lineWidth
      ..antialias = _antialias
      ..cacheMb = _cacheMb
      ..defaults = _defaults;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await p.save();
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not save preferences: $e')),
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Appearance', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {_theme},
              onSelectionChanged: (s) => setState(() => _theme = s.first),
            ),
            SizedBox(
              width: 240,
              child: Row(
                children: [
                  const Text('Line width'),
                  Expanded(
                    child: Slider(
                      value: _lineWidth,
                      min: 0.5,
                      max: 3,
                      divisions: 5,
                      label: '${_lineWidth.toStringAsFixed(1)} px',
                      onChanged: (v) => setState(() => _lineWidth = v),
                    ),
                  ),
                ],
              ),
            ),
            FilterChip(
              label: const Text('Antialiasing'),
              selected: _antialias,
              onSelected: (v) => setState(() => _antialias = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('New tabs start with', style: theme.textTheme.titleSmall),
        Text(
          'Or use “Use as defaults” in a tab\'s Signal controls.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final kind in [Kind.eeg, Kind.emg, Kind.imu, Kind.other])
          _kindCard(kind),
        const SizedBox(height: 16),
        Text('Memory', style: theme.textTheme.titleSmall),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Decoded data cache per recording'),
            DropdownButton<int>(
              value: _cacheMb,
              items: [
                for (final mb in {
                  64,
                  128,
                  256,
                  512,
                  1024,
                  2048,
                  _cacheMb,
                }.toList()..sort())
                  DropdownMenuItem(value: mb, child: Text('$mb MB')),
              ],
              onChanged: (v) => setState(() => _cacheMb = v!),
            ),
          ],
        ),
        Text(
          'Applies to recordings opened afterwards.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
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
            title: const Text('Preferences'),
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
      title: const Text('Preferences'),
      content: SizedBox(width: 720, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }

  Widget _kindCard(Kind kind) {
    final d = _defaults[kind]!;
    void set(KindDefaults v) => setState(() => _defaults[kind] = v);
    final filterable = kind == Kind.eeg || kind == Kind.emg;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                kind.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: formatNumber(d.windowS),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Window',
                  suffixText: 's',
                  isDense: true,
                ),
                onChanged: (v) {
                  final x = double.tryParse(v.replaceAll(',', '.'));
                  if (x != null && x >= 0.5) set(d.copyWith(windowS: x));
                },
              ),
            ),
            DropdownButton<ScaleMode>(
              value: d.scaleMode,
              items: [
                for (final m in ScaleMode.values)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (m) => set(d.copyWith(scaleMode: m)),
            ),
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: formatNumber(d.scale),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Scale',
                  isDense: true,
                ),
                onChanged: (v) {
                  final x = double.tryParse(v.replaceAll(',', '.'));
                  if (x != null && x > 0) set(d.copyWith(scale: x));
                },
              ),
            ),
            if (filterable) ...[
              SizedBox(
                width: 130,
                child: HzField(
                  label: 'High-pass',
                  value: d.highpass,
                  presets: highpassPresets,
                  onChanged: (v) => set(d.copyWith(highpass: () => v)),
                ),
              ),
              SizedBox(
                width: 120,
                child: HzField(
                  label: 'Notch',
                  value: d.notch,
                  presets: notchPresets,
                  onChanged: (v) => set(d.copyWith(notch: () => v)),
                ),
              ),
              DropdownButton<RefMode>(
                value: d.refMode,
                items: [
                  for (final m in RefMode.values)
                    DropdownMenuItem(
                      value: m,
                      child: Text(switch (m) {
                        RefMode.recorded => 'Ref: as recorded',
                        RefMode.average => 'Ref: average',
                        _ =>
                          'Ref: ${d.refLabels.isEmpty ? m.label : d.refLabels.join(' + ')}',
                      }),
                    ),
                ],
                onChanged: (m) => set(d.copyWith(refMode: m)),
              ),
              if ((d.refMode == RefMode.channel ||
                      d.refMode == RefMode.subset) &&
                  d.refLabels.isEmpty)
                const Text(
                  'Choose the channels in a tab and use “Use as defaults”.',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The source setup of [streams]: kind, tab name and channel names of
/// each, starting from [current]. [groupable] says whether a stream's tab
/// name merges it with others (streams of one clock, e.g. a device's
/// ports); the others keep a tab each. Null if cancelled.
Future<Map<String, SourceAssignment>?> showSourceSetup(
  BuildContext context,
  List<StreamInfo> streams,
  Map<String, SourceAssignment> current, {
  String title = 'Source setup',
  bool Function(String key)? groupable,
}) => showDialog<Map<String, SourceAssignment>>(
  context: context,
  builder: (_) =>
      _SourceSetupDialog(streams, current, title, groupable ?? (_) => true),
);

class _SourceSetupDialog extends StatefulWidget {
  final List<StreamInfo> streams;
  final Map<String, SourceAssignment> current;
  final String title;
  final bool Function(String key) groupable;
  const _SourceSetupDialog(
    this.streams,
    this.current,
    this.title,
    this.groupable,
  );

  @override
  State<_SourceSetupDialog> createState() => _SourceSetupDialogState();
}

class _SourceSetupDialogState extends State<_SourceSetupDialog> {
  late final Map<String, SourceAssignment> _a = {
    for (final p in widget.streams)
      p.key: widget.current[p.key] ?? SourceAssignment.defaultFor(p),
  };
  late final Map<String, TextEditingController> _names = {
    for (final e in _a.entries)
      e.key: TextEditingController(text: e.value.group),
  };

  @override
  void dispose() {
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The sources' kinds and tab names. Channel names stay: they are not
  /// the source's to reset.
  void _reset() => setState(() {
    for (final p in widget.streams) {
      final d = SourceAssignment.defaultFor(p);
      _a[p.key] = d.copyWith(names: _a[p.key]!.names);
      _names[p.key]!.text = d.group;
    }
  });

  Future<void> _editNames(StreamInfo p) async {
    final names = await showChannelNames(context, p, _a[p.key]!.names);
    if (names != null) {
      setState(() => _a[p.key] = _a[p.key]!.copyWith(names: names));
    }
  }

  @override
  Widget build(BuildContext context) {
    final streams = [...widget.streams]
      ..sort((a, b) {
        final i = streamIndex(a) - streamIndex(b);
        return i != 0 ? i : a.name.compareTo(b.name);
      });
    final merged = [
      for (final p in widget.streams)
        if (widget.groupable(p.key)) p,
    ];
    final groups = [
      ...buildGroups(merged, _a),
      ...buildGroups(
        [
          for (final p in widget.streams)
            if (!widget.groupable(p.key)) p,
        ],
        _a,
        groupable: false,
      ),
    ];
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    Widget kind(StreamInfo p) => DropdownButton<Kind>(
      value: _a[p.key]!.kind,
      isDense: !narrow,
      items: [
        for (final k in Kind.values)
          DropdownMenuItem(value: k, child: Text(k.label)),
      ],
      onChanged: (k) =>
          setState(() => _a[p.key] = _a[p.key]!.copyWith(kind: k)),
    );
    Widget name(StreamInfo p) => !widget.groupable(p.key)
        ? Text('—', style: theme.textTheme.bodySmall)
        : TextField(
            controller: _names[p.key],
            decoration: InputDecoration(
              isDense: true,
              labelText: narrow ? 'Tab name' : null,
            ),
            onChanged: (v) => setState(
              () => _a[p.key] = _a[p.key]!.copyWith(
                group: v.trim().isEmpty ? p.name : v.trim(),
              ),
            ),
          );
    Widget names(StreamInfo p) {
      final n = _a[p.key]!.names.length;
      return TextButton(
        onPressed: () => _editNames(p),
        child: Text(
          n > 0
              ? '$n/${p.channelCount} named'
              : (narrow ? 'Channel names…' : 'Name…'),
        ),
      );
    }

    String detected(StreamInfo p) =>
        '${p.kind.label} · '
        '${p.irregular ? 'irregular' : '${formatNumber(p.rate)} Hz'}';
    return AlertDialog(
      title: Text(widget.title),
      insetPadding: narrow
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (narrow)
                for (final p in streams)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p.name} · ${detected(p)} · '
                            '${p.channelCount} ch',
                            style: theme.textTheme.labelLarge,
                          ),
                          Row(
                            children: [
                              kind(p),
                              const SizedBox(width: 12),
                              Expanded(child: name(p)),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: names(p),
                          ),
                        ],
                      ),
                    ),
                  )
              else
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.2),
                    1: FlexColumnWidth(1.4),
                    2: FixedColumnWidth(70),
                    3: FixedColumnWidth(120),
                    4: FlexColumnWidth(),
                    5: FixedColumnWidth(110),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        for (final h in [
                          'Stream',
                          'Detected',
                          'Channels',
                          'Signal type',
                          'Tab name',
                          'Channel names',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(h, style: theme.textTheme.labelMedium),
                          ),
                      ],
                    ),
                    for (final p in streams)
                      TableRow(
                        children: [
                          Text(p.name, overflow: TextOverflow.ellipsis),
                          Text(detected(p)),
                          Text('${p.channelCount}'),
                          kind(p),
                          name(p),
                          names(p),
                        ],
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Text('Tabs', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final g in groups)
                Text(
                  '• ${g.info.name} — ${g.info.channelCount} channels',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Reset to source')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _a),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Names for the channels of [stream] (e.g. cap positions), by channel
/// index; null if cancelled.
Future<Map<int, String>?> showChannelNames(
  BuildContext context,
  StreamInfo stream,
  Map<int, String> names,
) => showDialog<Map<int, String>>(
  context: context,
  builder: (_) => _ChannelNamesDialog(stream, names),
);

class _ChannelNamesDialog extends StatefulWidget {
  final StreamInfo stream;
  final Map<int, String> names;
  const _ChannelNamesDialog(this.stream, this.names);

  @override
  State<_ChannelNamesDialog> createState() => _ChannelNamesDialogState();
}

class _ChannelNamesDialogState extends State<_ChannelNamesDialog> {
  late final List<TextEditingController> _fields = [
    for (var c = 0; c < widget.stream.channelCount; c++)
      TextEditingController(text: widget.names[c] ?? ''),
  ];
  final _list = TextEditingController();

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    _list.dispose();
    super.dispose();
  }

  /// Fill the fields in order from a pasted list: separated by commas,
  /// semicolons, tabs or new lines (e.g. a spreadsheet column).
  void _fill() {
    final names = _list.text
        .split(RegExp(r'[,;\t\n\r]+'))
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.length < 2 && _list.text.trim().contains(' ')) {
      names
        ..clear()
        ..addAll(_list.text.trim().split(RegExp(r'\s+')));
    }
    setState(() {
      for (var c = 0; c < _fields.length && c < names.length; c++) {
        _fields[c].text = names[c];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.stream;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Channel names · ${p.name}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Names replace the source\'s labels (shown next to them) on '
                '${p.name} of every device and recording. Leave a name '
                'empty to keep the source\'s label.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _list,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Paste a list',
                        hintText: 'Fp1, Fp2, F3, …',
                      ),
                      onSubmitted: (_) => _fill(),
                    ),
                  ),
                  TextButton(onPressed: _fill, child: const Text('Fill')),
                ],
              ),
              const SizedBox(height: 8),
              for (var c = 0; c < _fields.length; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          p.deviceLabel(c),
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _fields[c],
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            for (final f in _fields) {
              f.clear();
            }
          }),
          child: const Text('Clear all'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            for (var c = 0; c < _fields.length; c++)
              if (_fields[c].text.trim().isNotEmpty) c: _fields[c].text.trim(),
          }),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Tabs to show below another (from [tabs], [current] ticked). Null if
/// cancelled.
Future<List<TabEntry>?> showTabPicker(
  BuildContext context,
  List<TabEntry> tabs,
  List<TabEntry> current,
) => showDialog<List<TabEntry>>(
  context: context,
  builder: (_) => _TabPickerDialog(tabs, current),
);

class _TabPickerDialog extends StatefulWidget {
  final List<TabEntry> tabs;
  final List<TabEntry> current;
  const _TabPickerDialog(this.tabs, this.current);

  @override
  State<_TabPickerDialog> createState() => _TabPickerDialogState();
}

class _TabPickerDialogState extends State<_TabPickerDialog> {
  late final Set<TabEntry> _chosen = {...widget.current};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Show tabs below'),
    content: SizedBox(
      width: 480,
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'They share the time axis of this tab: zooming or scrolling '
            'any of them moves all.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final t in widget.tabs)
            CheckboxListTile(
              value: _chosen.contains(t),
              onChanged: (v) => setState(
                () => v == true ? _chosen.add(t) : _chosen.remove(t),
              ),
              title: Text(t.title),
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
        onPressed: () => Navigator.pop(context, [
          for (final t in widget.tabs)
            if (_chosen.contains(t)) t,
        ]),
        child: const Text('OK'),
      ),
    ],
  );
}

/// Manchester decoder settings.
Future<ManchesterSettings?> showDecoderSettings(
  BuildContext context,
  ManchesterSettings current,
) => showDialog<ManchesterSettings>(
  context: context,
  builder: (context) {
    var clock = current.clockHz;
    var order = current.order;
    var preamble = current.preamble;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Decoder settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: TextFormField(
                initialValue: formatNumber(clock),
                decoration: const InputDecoration(
                  labelText: 'Bit clock',
                  suffixText: 'Hz',
                ),
                onChanged: (v) {
                  final x = double.tryParse(v.replaceAll(',', '.'));
                  if (x != null && x >= 0.5 && x <= 1000) clock = x;
                },
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<BitOrder>(
              segments: const [
                ButtonSegment(value: BitOrder.lsb, label: Text('LSB first')),
                ButtonSegment(value: BitOrder.msb, label: Text('MSB first')),
              ],
              selected: {order},
              onSelectionChanged: (s) => setState(() => order = s.first),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preamble (a 0 bit before the data)'),
              value: preamble,
              onChanged: (v) => setState(() => preamble = v!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              ManchesterSettings(
                clockHz: clock,
                order: order,
                preamble: preamble,
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  },
);

const _help = [
  ('Wheel', 'Amplitude scale (1-2-5 steps)'),
  ('Ctrl + wheel, pinch', 'Time window'),
  ('Shift + wheel, sideways scroll, drag', 'Scroll through time'),
  ('Click or tap a channel name', 'Exclude it (bad channel) or include it'),
  (
    'Right-click or long-press a trace',
    'Hide it, exclude it, or reference to it',
  ),
  ('Click or drag the overview', 'Jump to that part of the recording'),
  ('← / →', 'Scroll by a tenth of the window'),
  ('Page Up / Page Down', 'Scroll by a whole window'),
  ('Home / End', 'Start / end of the recording'),
  ('+ / −', 'Shorter / longer time window'),
  ('Ctrl+O', 'Open recording'),
  ('F5', 'Refresh device list'),
  ('Ctrl+B', 'Show or hide the controls panel'),
  ('Ctrl+Page Up / Page Down', 'Previous / next tab'),
  ('Ctrl+W', 'Close tab'),
];

void showHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Keyboard and mouse'),
    content: SizedBox(
      width: 520,
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        children: [
          for (final (k, v) in _help)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 6),
                  child: Text(
                    k,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(v),
              ],
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

Future<void> showAbout(BuildContext context, ViewerConfig config) async {
  // The build's --build-name, which CI takes from the tag (pubspec otherwise).
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  showAboutDialog(
    context: context,
    applicationName: config.title,
    applicationVersion: info.version,
    applicationLegalese: config.legalese,
  );
}
