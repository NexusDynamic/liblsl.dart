import 'package:flutter/material.dart';
import 'package:signal_core/signal_core.dart';

import '../../display/colors.dart';
import '../../display/power.dart';
import '../../model/stream_info.dart';
import '../../model/view_settings.dart';
import '../../sources/live_buffers.dart';
import '../stream_controller.dart';
import '../widgets/widgets.dart';

/// The controls to the right of a plot (or in a sheet on narrow screens),
/// in three tabs: display, channels and signal processing.
class ControlsPanel extends StatelessWidget {
  final StreamController controller;

  /// Opens the source setup (kinds, tab and channel names), labelled
  /// [sourceSetupLabel].
  final VoidCallback? onSourceSetup;
  final String sourceSetupLabel;
  final VoidCallback? onDecoderSettings;

  /// Make the current settings the defaults for new tabs of this kind.
  final Future<void> Function()? onSaveDefaults;
  final bool dark;

  const ControlsPanel({
    super.key,
    required this.controller,
    required this.dark,
    this.onSourceSetup,
    this.sourceSetupLabel = 'Source setup…',
    this.onDecoderSettings,
    this.onSaveDefaults,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context),
    );
  }

  bool get _isEvent =>
      controller.info.kind == Kind.event || controller.info.irregular;

  /// Whether channels can be decoded as Manchester triggers (not for
  /// streams whose values are text, which get no [onDecoderSettings]).
  bool get _decodable => _isEvent && onDecoderSettings != null;

  Widget _build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final tabs = [
      ('Display', _display(context)),
      ('Channels', _channels(context)),
      if (!_isEvent) ('Signal', _signal(context)),
    ];
    return DefaultTabController(
      length: tabs.length,
      // Channels first for events: that is where decoding is.
      initialIndex: _isEvent ? 1 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(_summary(c), style: theme.textTheme.bodySmall),
          ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                c.error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),
          if (onSourceSetup != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onSourceSetup,
                icon: const Icon(Icons.settings_input_component, size: 16),
                label: Text(sourceSetupLabel, overflow: TextOverflow.ellipsis),
              ),
            ),
          TabBar(tabs: [for (final (t, _) in tabs) Tab(text: t)]),
          Expanded(child: TabBarView(children: [for (final (_, w) in tabs) w])),
        ],
      ),
    );
  }

  String _summary(StreamController c) {
    final info = c.info;
    final s = c.settings;
    final rate = info.irregular ? 'irregular' : '${formatNumber(info.rate)} Hz';
    return [
      '${info.kind.label} · $rate · ${info.channelCount} channels'
          ' · ${c.lanes.length} shown',
      if (info.canReference) 'Reference: ${c.referenceSummary}',
      if (c.meanMode) 'Showing the mean of ${c.averaged.length}',
      if (!info.canReference && s.bad.isNotEmpty)
        'Bad: ${[for (final b in s.bad.toList()..sort()) info.labels[b]].join(', ')}',
    ].join('\n');
  }

  // -- display --------------------------------------------------------------

  Widget _display(BuildContext context) {
    final c = controller;
    final info = c.info;
    final s = c.settings;
    final theme = Theme.of(context);
    final unit = prettyUnit(info.unit());
    void set(ViewSettings v) => c.update(v);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Section(
          title: 'Time',
          child: LogSlider(
            value: c.windowS,
            min: minWindowS,
            max: c.live ? liveBufferS : c.maxWindowS,
            suffix: 's',
            onChanged: c.setWindow,
          ),
        ),
        if (!_isEvent)
          Section(
            title: 'Amplitude',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ScaleMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ScaleMode.fixed, label: Text('Fixed')),
                    ButtonSegment(value: ScaleMode.auto, label: Text('Auto')),
                    ButtonSegment(
                      value: ScaleMode.perChannel,
                      label: Text('Per ch.'),
                    ),
                  ],
                  selected: {s.scaleMode},
                  onSelectionChanged: (m) =>
                      set(s.copyWith(scaleMode: m.first)),
                ),
                const SizedBox(height: 6),
                if (s.scaleMode == ScaleMode.perChannel)
                  Text(
                    'Each channel is scaled to fit its lane; see the '
                    'Channels tab.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  LogSlider(
                    value: c.scaleFor(0),
                    min: 0.1,
                    max: 1e6,
                    suffix: '$unit/div',
                    onChanged: (v) =>
                        set(s.copyWith(scaleMode: ScaleMode.fixed, scale: v)),
                  ),
                SwitchListTile(
                  dense: !touchPlatform,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remove baseline'),
                  value: s.baseline,
                  onChanged: (v) => set(s.copyWith(baseline: v)),
                ),
              ],
            ),
          ),
        if (info.filterable)
          Section(
            title: 'Colour',
            initiallyOpen: false,
            child: _colour(context),
          ),
      ],
    );
  }

  Widget _colour(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final theme = Theme.of(context);
    void set(ViewSettings v) => c.update(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          dense: !touchPlatform,
          contentPadding: EdgeInsets.zero,
          title: const Text('Colour by power'),
          value: s.colour == ColourMode.power,
          onChanged: (v) => set(
            s.copyWith(colour: v! ? ColourMode.power : ColourMode.channel),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: s.powerMetric,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Measure',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final m in metrics)
              DropdownMenuItem(value: m, child: Text(metricLabel(m))),
          ],
          onChanged: (v) => set(s.copyWith(powerMetric: v)),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<PowerStyle>(
          initialValue: s.powerStyle,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Show as',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final p in PowerStyle.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (v) => set(s.copyWith(powerStyle: v)),
        ),
        if (s.colour == ColourMode.power &&
            s.powerMetric != 'rms' &&
            c.windowS > maxBandWindowS)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Zoom in to ${maxBandWindowS.toInt()} s or less for band power.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  // -- channels -------------------------------------------------------------

  Widget _channels(BuildContext context) {
    final c = controller;
    final info = c.info;
    final s = c.settings;
    final theme = Theme.of(context);
    final perChannel = s.scaleMode == ScaleMode.perChannel && !_isEvent;
    final unit = prettyUnit(info.unit());
    final rowH = touchPlatform ? 44.0 : 30.0;
    final density = touchPlatform
        ? VisualDensity.standard
        : VisualDensity.compact;
    final flagged = [
      for (var ch = 0; ch < info.channelCount; ch++)
        if (c.qualityOf(ch).flag == ChannelFlag.bad && !s.bad.contains(ch)) ch,
    ];

    Widget header(String t, {double? width, bool expand = false}) {
      final text = Text(t, style: theme.textTheme.labelSmall);
      return expand
          ? Expanded(child: text)
          : SizedBox(width: width, child: text);
    }

    Widget swatch(int ch) {
      Widget box() => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c.laneColor(ch, dark: dark),
          borderRadius: BorderRadius.circular(2),
        ),
      );
      // Power colours change with the data.
      return c.powerActive
          ? ListenableBuilder(
              listenable: c.repaint,
              builder: (context, _) => box(),
            )
          : box();
    }

    Widget flag(int ch) {
      final q = c.qualityOf(ch);
      if (q.flag == ChannelFlag.ok) return const SizedBox(width: 14);
      return Tooltip(
        message: q.reason,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(
            Icons.circle,
            size: 8,
            color: q.flag == ChannelFlag.bad ? flagBadColor : flagWarnColor,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info.badChannels) ...[
            Text(
              'Tap a channel\'s name on the plot, or tick “Bad” here, to '
              'leave it out of the average reference. Dots mark channels '
              'with a lot of line noise or an unusual amplitude.',
              style: theme.textTheme.bodySmall,
            ),
            if (flagged.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.circle, size: 10, color: flagBadColor),
                  onPressed: c.excludeFlagged,
                  label: Text(
                    'Exclude flagged (${[for (final f in flagged) info.labels[f]].join(', ')})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              header('Channel', expand: true),
              header('Show', width: 48),
              if (info.badChannels) header('Bad', width: 48),
              if (_decodable) header('Decode', width: 56),
              if (perChannel) header('Scale', width: 70),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: info.channelCount,
              itemExtent: rowH,
              itemBuilder: (context, ch) {
                final bad = s.bad.contains(ch);
                return Row(
                  children: [
                    if (info.badChannels) flag(ch),
                    swatch(ch),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: info.labels[ch],
                          children: [
                            if (info.renamed(ch))
                              TextSpan(
                                text: '  ${info.deviceLabel(ch)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.hintColor,
                                ),
                              ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          decoration: bad ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Checkbox(
                        visualDensity: density,
                        value: !s.hidden.contains(ch),
                        onChanged: (v) => c.update(
                          s.copyWith(
                            hidden: v!
                                ? ({...s.hidden}..remove(ch))
                                : {...s.hidden, ch},
                          ),
                        ),
                      ),
                    ),
                    if (info.badChannels)
                      SizedBox(
                        width: 48,
                        child: Checkbox(
                          visualDensity: density,
                          value: bad,
                          onChanged: (v) => c.setExcluded(ch, v!),
                        ),
                      ),
                    if (_decodable)
                      SizedBox(
                        width: 56,
                        child: Checkbox(
                          visualDensity: density,
                          value: s.decoded.contains(ch),
                          onChanged: (v) => c.update(
                            s.copyWith(
                              decoded: v!
                                  ? {...s.decoded, ch}
                                  : ({...s.decoded}..remove(ch)),
                            ),
                          ),
                        ),
                      ),
                    if (perChannel)
                      SizedBox(
                        width: 70,
                        child: Text(
                          '${formatNumber(c.scaleFor(ch))} $unit',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => c.update(s.copyWith(hidden: const {})),
                child: const Text('Show all'),
              ),
              TextButton(
                onPressed: () => c.update(
                  s.copyWith(
                    hidden: {for (var i = 0; i < info.channelCount; i++) i},
                  ),
                ),
                child: const Text('Hide all'),
              ),
              if (info.badChannels)
                TextButton(
                  onPressed: () => c.update(s.copyWith(bad: const {})),
                  child: const Text('Include all'),
                ),
              if (_decodable)
                TextButton(
                  onPressed: onDecoderSettings,
                  child: const Text('Decoder settings…'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // -- signal ---------------------------------------------------------------

  Widget _signal(BuildContext context) {
    final c = controller;
    final info = c.info;
    final s = c.settings;
    final theme = Theme.of(context);
    void set(ViewSettings v) => c.update(v);
    final picking = s.refMode == RefMode.channel || s.refMode == RefMode.subset;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (info.canReference)
          Section(
            title: 'Reference',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<RefMode>(
                  key: ValueKey(s.refMode),
                  initialValue: s.refMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reference to',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in RefMode.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => set(
                    s.copyWith(
                      refMode: m,
                      refChannels: m == RefMode.channel
                          ? s.refChannels.take(1).toSet()
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (s.refMode == RefMode.average)
                  Text(
                    'Channels marked bad (Channels tab, or tap a name on '
                    'the plot) are left out of the average.',
                    style: theme.textTheme.bodySmall,
                  ),
                if (picking) ...[
                  Text(
                    s.refMode == RefMode.channel
                        ? 'Pick the reference channel:'
                        : 'Pick the channels to average:',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  ChannelChips(
                    info: info,
                    selected: s.refChannels.contains,
                    onSelected: (ch) => s.refMode == RefMode.channel
                        ? c.useAsReference(ch)
                        : c.toggleInReferenceSet(ch),
                  ),
                ],
              ],
            ),
          ),
        if (info.filterable)
          Section(
            title: 'Filters',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HzField(
                  label: 'High-pass',
                  value: s.highpass,
                  presets: highpassPresets,
                  onChanged: (v) => set(s.copyWith(highpass: () => v)),
                ),
                const SizedBox(height: 10),
                HzField(
                  label: 'Notch',
                  value: s.notch,
                  presets: notchPresets,
                  onChanged: (v) => set(s.copyWith(notch: () => v)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Live data is filtered causally, recordings zero-phase.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (info.canMean)
          SwitchListTile(
            dense: !touchPlatform,
            contentPadding: EdgeInsets.zero,
            title: const Text('Show mean of channels'),
            subtitle: const Text('One trace: the mean of the good channels'),
            value: s.mean,
            onChanged: (v) => set(s.copyWith(mean: v)),
          ),
        if (onSaveDefaults != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              try {
                await onSaveDefaults!();
                messenger?.showSnackBar(
                  SnackBar(
                    content: Text(
                      'New ${info.kind.label} tabs will start with these '
                      'settings',
                    ),
                  ),
                );
              } catch (e) {
                messenger?.showSnackBar(
                  SnackBar(content: Text('Could not save: $e')),
                );
              }
            },
            label: Text('Use as defaults for new ${info.kind.label} tabs'),
          ),
          const SizedBox(height: 4),
          Text(
            'Saves the time window, scale, filters and reference. Also in '
            'Preferences.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
