import 'package:flutter/material.dart';
import 'package:signal_core/signal_core.dart';

import '../../display/colors.dart';
import '../../model/stream_info.dart';
import '../../model/view_settings.dart';
import '../../sources/live_buffers.dart';
import '../stream_controller.dart';
import '../widgets/widgets.dart';

const _windowPresets = [1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 60.0];
const _scalePresets = [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0];

/// The settings used most, as chips above the plot: time window, scale,
/// filters, reference and flagged channels. [trailing] goes at the end
/// (e.g. a button for the full controls on phones).
class QuickBar extends StatelessWidget {
  final StreamController controller;
  final Widget? trailing;

  const QuickBar({super.key, required this.controller, this.trailing});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final c = controller;
    final info = c.info;
    final s = c.settings;
    final isEvent = info.kind == Kind.event || info.irregular;
    final unit = prettyUnit(info.unit());
    final maxWindow = c.live ? liveBufferS : c.maxWindowS;
    void set(ViewSettings v) => c.update(v);

    final chips = <Widget>[
      ChipMenu<double>(
        icon: Icons.schedule,
        tooltip: 'Time window',
        label: '${formatNumber(c.windowS)} s',
        selected: c.windowS,
        choices: [
          for (final w in _windowPresets)
            if (w <= maxWindow) ('${formatNumber(w)} s', w),
        ],
        onSelected: c.setWindow,
        custom: () async {
          final v = await askValue<double>(
            context,
            title: 'Time window',
            initial: formatNumber(c.windowS),
            suffix: 's',
            parse: _positive,
          );
          if (v != null) c.setWindow(v);
        },
      ),
      if (!isEvent)
        ChipMenu<double?>(
          icon: Icons.height,
          tooltip: 'Amplitude per lane',
          label: switch (s.scaleMode) {
            ScaleMode.fixed => '${formatNumber(s.scale)} $unit',
            ScaleMode.auto => 'Auto ${formatNumber(c.scaleFor(0))} $unit',
            ScaleMode.perChannel => 'Auto per ch.',
          },
          selected: switch (s.scaleMode) {
            ScaleMode.fixed => s.scale,
            ScaleMode.auto => -1,
            ScaleMode.perChannel => -2,
          },
          choices: [
            ('Auto (shared)', -1),
            ('Auto (per channel)', -2),
            for (final v in _scalePresets) ('${formatNumber(v)} $unit', v),
          ],
          onSelected: (v) => set(switch (v) {
            -1 => s.copyWith(scaleMode: ScaleMode.auto),
            -2 => s.copyWith(scaleMode: ScaleMode.perChannel),
            _ => s.copyWith(scaleMode: ScaleMode.fixed, scale: v),
          }),
          custom: () async {
            final v = await askValue<double>(
              context,
              title: 'Amplitude per lane',
              initial: formatNumber(c.scaleFor(0)),
              suffix: unit,
              parse: _positive,
            );
            if (v != null) {
              set(s.copyWith(scaleMode: ScaleMode.fixed, scale: v));
            }
          },
        ),
      if (info.filterable) ...[
        _hzChip(
          context,
          'HP',
          'High-pass filter',
          s.highpass,
          highpassPresets,
          (v) => set(s.copyWith(highpass: () => v)),
        ),
        _hzChip(
          context,
          'Notch',
          'Notch filter (line noise)',
          s.notch,
          notchPresets,
          (v) => set(s.copyWith(notch: () => v)),
        ),
      ],
      if (info.canReference) _refChip(context),
      if (c.qualityActive) ?_flagChip(context),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: chip,
                    ),
                ],
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  static double _positive(String text) {
    final v = double.parse(text.trim().replaceAll(',', '.'));
    if (!(v > 0) || !v.isFinite) throw FormatException('Invalid', text);
    return v;
  }

  Widget _hzChip(
    BuildContext context,
    String name,
    String tooltip,
    double? value,
    List<double?> presets,
    ValueChanged<double?> onChanged,
  ) => ChipMenu<double?>(
    tooltip: tooltip,
    label: '$name ${formatHz(value)}',
    selected: value,
    choices: [for (final p in presets) (formatHz(p), p)],
    onSelected: onChanged,
    custom: () async {
      final v = await askValue<double?>(
        context,
        title: tooltip,
        initial: value == null ? '' : formatNumber(value),
        suffix: 'Hz',
        hint: 'Empty or 0 turns it off',
        parse: parseHz,
      );
      if (v != null || value != null) onChanged(v);
    },
  );

  Widget _refChip(BuildContext context) {
    final c = controller;
    final info = c.info;
    final s = c.settings;
    final label = switch (s.refMode) {
      RefMode.recorded => 'Ref: as recorded',
      RefMode.average =>
        'Ref: avg ${info.channelCount - s.bad.length}/${info.channelCount}',
      RefMode.channel || RefMode.subset => 'Ref: ${c.referenceSummary}',
    };
    return MenuAnchor(
      menuChildren: [
        for (final m in [RefMode.recorded, RefMode.average])
          MenuItemButton(
            leadingIcon: Icon(s.refMode == m ? Icons.check : null, size: 18),
            onPressed: () => c.update(s.copyWith(refMode: m)),
            child: Text(m.label),
          ),
        // A dialog rather than a submenu: a list of 32 or more channels
        // does not fit beside the menu.
        for (final m in [RefMode.channel, RefMode.subset])
          MenuItemButton(
            leadingIcon: Icon(s.refMode == m ? Icons.check : null, size: 18),
            onPressed: () => _pickReference(context, c, m),
            child: Text('${m.label}…'),
          ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: 'Reference: ${c.referenceSummary}',
        child: ActionChip(
          avatar: const Icon(Icons.adjust, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      ),
    );
  }

  /// Pick the reference channel ([RefMode.channel]) or the channels whose
  /// mean is the reference ([RefMode.subset]). Changes apply as they are
  /// made.
  static Future<void> _pickReference(
    BuildContext context,
    StreamController c,
    RefMode mode,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        mode == RefMode.channel
            ? 'Reference to one channel'
            : 'Reference to the mean of chosen channels',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => ChannelChips(
              info: c.info,
              selected: (ch) =>
                  c.settings.refMode == mode &&
                  c.settings.refChannels.contains(ch),
              onSelected: (ch) {
                if (mode == RefMode.channel) {
                  c.useAsReference(ch);
                  Navigator.pop(context);
                } else if (c.settings.refMode != RefMode.subset) {
                  // Start a new set rather than adding to one channel.
                  c.update(
                    c.settings.copyWith(
                      refMode: RefMode.subset,
                      refChannels: {ch},
                    ),
                  );
                } else {
                  c.toggleInReferenceSet(ch);
                }
              },
            ),
          ),
        ),
      ),
      actions: [
        if (mode == RefMode.subset)
          TextButton(
            onPressed: () => c.update(
              c.settings.copyWith(refMode: RefMode.recorded, refChannels: {}),
            ),
            child: const Text('Clear'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(mode == RefMode.channel ? 'Cancel' : 'Done'),
        ),
      ],
    ),
  );

  /// Channels flagged by the quality check and not yet excluded, or null
  /// when there are none.
  Widget? _flagChip(BuildContext context) {
    final c = controller;
    final info = c.info;
    final s = c.settings;
    final flagged = [
      for (var ch = 0; ch < info.channelCount; ch++)
        if (c.qualityOf(ch).flag != ChannelFlag.ok && !s.bad.contains(ch)) ch,
    ];
    if (flagged.isEmpty) return null;
    final anyBad = flagged.any((ch) => c.qualityOf(ch).flag == ChannelFlag.bad);
    return MenuAnchor(
      menuChildren: [
        for (final ch in flagged)
          MenuItemButton(
            leadingIcon: Icon(
              Icons.circle,
              size: 10,
              color: c.qualityOf(ch).flag == ChannelFlag.bad
                  ? flagBadColor
                  : flagWarnColor,
            ),
            onPressed: () => c.setExcluded(ch, true),
            child: Text(
              'Exclude ${info.labels[ch]}: ${c.qualityOf(ch).reason}',
            ),
          ),
        if (anyBad)
          MenuItemButton(
            leadingIcon: const Icon(Icons.playlist_remove, size: 18),
            onPressed: c.excludeFlagged,
            child: const Text('Exclude all bad'),
          ),
      ],
      builder: (context, menu, _) => ActionChip(
        avatar: Icon(
          Icons.circle,
          size: 12,
          color: anyBad ? flagBadColor : flagWarnColor,
        ),
        label: Text('${flagged.length} flagged'),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
