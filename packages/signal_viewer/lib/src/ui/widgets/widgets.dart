import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../display/scale.dart';
import '../../model/stream_info.dart';
import '../../model/view_settings.dart';

/// Whether the app runs on a touch-first platform (phones and tablets),
/// where controls need bigger targets.
bool get touchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// A foldable section of the controls panel.
class Section extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyOpen;

  const Section({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = true,
  });

  @override
  State<Section> createState() => _SectionState();
}

class _SectionState extends State<Section> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18),
                const SizedBox(width: 4),
                Text(widget.title, style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: widget.child,
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// A slider over a logarithmic range that snaps to the 1-2-5 series, with a
/// box to type any value.
class LogSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  const LogSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  @override
  State<LogSlider> createState() => _LogSliderState();
}

class _LogSliderState extends State<LogSlider> {
  late final _text = TextEditingController(text: formatNumber(widget.value));
  final _focus = FocusNode();

  @override
  void didUpdateWidget(LogSlider old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) _text.text = formatNumber(widget.value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _log(double v) => math.log(v) / math.ln10;

  void _submit(String s) {
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v != null && v > 0) {
      widget.onChanged(v.clamp(widget.min, widget.max));
    } else {
      _text.text = formatNumber(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lo = _log(widget.min),
        hi = _log(math.max(widget.max, widget.min * 1.0001));
    final pos = _log(widget.value.clamp(widget.min, widget.max)).clamp(lo, hi);
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: pos,
            min: lo,
            max: hi,
            onChanged: (p) {
              final v = niceScale(
                math.pow(10, p).toDouble(),
              ).clamp(widget.min, widget.max).toDouble();
              if (v != widget.value) widget.onChanged(v);
            },
          ),
        ),
        SizedBox(
          width: 128,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              isDense: true,
              suffixText: widget.suffix,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 8,
              ),
            ),
            onSubmitted: _submit,
            onTapOutside: (_) {
              if (_focus.hasFocus) {
                _submit(_text.text);
                _focus.unfocus();
              }
            },
          ),
        ),
      ],
    );
  }
}

/// A frequency box with presets; typed values accept "0,5", "1 Hz" or
/// "off".
class HzField extends StatefulWidget {
  final String label;
  final double? value;
  final List<double?> presets;
  final ValueChanged<double?> onChanged;

  const HzField({
    super.key,
    required this.label,
    required this.value,
    required this.presets,
    required this.onChanged,
  });

  @override
  State<HzField> createState() => _HzFieldState();
}

class _HzFieldState extends State<HzField> {
  late final _text = TextEditingController(text: formatHz(widget.value));
  final _focus = FocusNode();
  String? _error;

  @override
  void didUpdateWidget(HzField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) _text.text = formatHz(widget.value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String s) {
    try {
      final v = parseHz(s);
      setState(() => _error = null);
      _text.text = formatHz(v);
      widget.onChanged(v);
    } on FormatException {
      setState(() => _error = 'Not a frequency');
    }
  }

  /// A preset from the menu. Called directly by the menu item: a
  /// PopupMenuButton would treat the "Off" preset (null) as a cancel.
  void _pick(double? v) {
    _focus.unfocus();
    setState(() => _error = null);
    _text.text = formatHz(v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      focusNode: _focus,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        errorText: _error,
        border: const OutlineInputBorder(),
        suffixIcon: MenuAnchor(
          menuChildren: [
            for (final p in widget.presets)
              MenuItemButton(
                onPressed: () => _pick(p),
                child: Text(formatHz(p)),
              ),
          ],
          builder: (context, menu, _) => IconButton(
            icon: const Icon(Icons.arrow_drop_down),
            tooltip: 'Presets',
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          ),
        ),
      ),
      onSubmitted: _submit,
      onTapOutside: (_) {
        if (_focus.hasFocus) {
          _submit(_text.text);
          _focus.unfocus();
        }
      },
    );
  }
}

/// A chip showing a value that opens a menu of choices, e.g. "HP 0.5 Hz".
/// [custom] adds a "Custom…" entry that asks for a value.
class ChipMenu<T> extends StatelessWidget {
  final String label;
  final String? tooltip;
  final IconData? icon;
  final List<(String, T)> choices;
  final T? selected;
  final ValueChanged<T> onSelected;
  final Future<void> Function()? custom;

  /// Extra entries after the choices (e.g. actions).
  final List<Widget> extra;

  const ChipMenu({
    super.key,
    required this.label,
    required this.choices,
    required this.onSelected,
    this.selected,
    this.tooltip,
    this.icon,
    this.custom,
    this.extra = const [],
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final (text, value) in choices)
          MenuItemButton(
            leadingIcon: Icon(value == selected ? Icons.check : null, size: 18),
            onPressed: () => onSelected(value),
            child: Text(text),
          ),
        if (custom != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.edit, size: 18),
            onPressed: custom,
            child: const Text('Custom…'),
          ),
        ...extra,
      ],
      builder: (context, menu, _) => Tooltip(
        message: tooltip ?? '',
        child: ActionChip(
          avatar: icon == null ? null : Icon(icon, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      ),
    );
  }
}

/// The channels of a stream as chips to pick from, under a heading per
/// source stream when it merges several. A named channel shows its device
/// label in a tooltip.
class ChannelChips extends StatelessWidget {
  final StreamInfo info;
  final bool Function(int channel) selected;
  final ValueChanged<int> onSelected;

  const ChannelChips({
    super.key,
    required this.info,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final byPort = <int, List<int>>{};
    for (var ch = 0; ch < info.channelCount; ch++) {
      (byPort[info.channels[ch].stream] ??= []).add(ch);
    }
    Widget chip(int ch) {
      final c = FilterChip(
        label: Text(info.labels[ch]),
        selected: selected(ch),
        onSelected: (_) => onSelected(ch),
      );
      return info.renamed(ch)
          ? Tooltip(message: info.deviceLabel(ch), child: c)
          : c;
    }

    Widget wrap(List<int> chans) => Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [for (final ch in chans) chip(ch)],
    );
    if (byPort.length == 1) return wrap(byPort.values.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in byPort.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              'Port ${e.key}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          wrap(e.value),
        ],
      ],
    );
  }
}

/// Ask for a value, e.g. a custom frequency or a channel name; null if
/// cancelled. [parse] turns the text into the value or throws
/// [FormatException].
Future<T?> askValue<T>(
  BuildContext context, {
  required String title,
  required String initial,
  required T Function(String) parse,
  String? suffix,
  String? hint,
  TextInputType keyboardType = const TextInputType.numberWithOptions(
    decimal: true,
  ),
}) async {
  final result = await showDialog<(T,)>(
    context: context,
    builder: (_) => _AskValueDialog<T>(
      title: title,
      initial: initial,
      parse: parse,
      suffix: suffix,
      hint: hint,
      keyboardType: keyboardType,
    ),
  );
  return result?.$1;
}

/// Owns its text controller, so it is disposed only once the dialog has
/// finished closing.
class _AskValueDialog<T> extends StatefulWidget {
  final String title;
  final String initial;
  final T Function(String) parse;
  final String? suffix;
  final String? hint;
  final TextInputType keyboardType;

  const _AskValueDialog({
    required this.title,
    required this.initial,
    required this.parse,
    this.suffix,
    this.hint,
    required this.keyboardType,
  });

  @override
  State<_AskValueDialog<T>> createState() => _AskValueDialogState<T>();
}

class _AskValueDialogState<T> extends State<_AskValueDialog<T>> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      Navigator.pop(context, (widget.parse(_text.text),));
    } on FormatException {
      setState(() => _error = 'Not a valid value');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      keyboardType: widget.keyboardType,
      decoration: InputDecoration(
        suffixText: widget.suffix,
        helperText: widget.hint,
        helperMaxLines: 3,
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('OK')),
    ],
  );
}

/// The dashed outline and message shown while files are dragged over the
/// window.
class DropOverlay extends StatelessWidget {
  final String message;
  final bool ok;

  const DropOverlay({super.key, required this.message, this.ok = true});

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.blue : Colors.red;
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
