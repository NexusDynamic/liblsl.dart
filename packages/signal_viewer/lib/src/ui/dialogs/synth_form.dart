import 'package:flutter/material.dart';
import 'package:signal_core/signal_core.dart';

import '../../model/view_settings.dart';
import '../../sources/synthetic.dart';

/// Fields for a synthetic signal: preset, channels, rate, sizes, seed,
/// markers and simulated dropouts (and jitter, if [jitter]). Calls
/// [onChanged] with the options, or null while a field is invalid.
class SynthForm extends StatefulWidget {
  final SynthOptions initial;
  final ValueChanged<SynthOptions?> onChanged;

  /// Whether to offer jitter in the time stamps (for a stream sent over a
  /// network; a stream shown directly is placed on its grid).
  final bool jitter;

  const SynthForm({
    super.key,
    required this.initial,
    required this.onChanged,
    this.jitter = false,
  });

  @override
  State<SynthForm> createState() => _SynthFormState();
}

class _SynthFormState extends State<SynthForm> {
  late SynthPreset _preset = widget.initial.spec.preset;
  late double _line = widget.initial.spec.lineFrequency;
  late bool _markers = widget.initial.markers != null;
  late bool _atEvents = widget.initial.markers?.atEvents ?? true;

  late final _channels = _text(widget.initial.spec.channels.toDouble());
  late final _rate = _text(widget.initial.spec.rate);
  late final _frequency = _text(widget.initial.spec.frequency);
  late final _amplitude = _text(widget.initial.spec.amplitude);
  late final _seed = _text(widget.initial.spec.seed.toDouble());
  late final _every = _text(widget.initial.markers?.every ?? 1);
  late final _dropouts = _text(widget.initial.impairments.dropoutRate);
  late final _dropoutS = _text(widget.initial.impairments.dropoutS);
  late final _jitterMs = _text(widget.initial.impairments.jitterS * 1000);

  TextEditingController _text(double v) =>
      TextEditingController(text: formatNumber(v))..addListener(_changed);

  List<TextEditingController> get _all => [
    _channels,
    _rate,
    _frequency,
    _amplitude,
    _seed,
    _every,
    _dropouts,
    _dropoutS,
    _jitterMs,
  ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c, {double min = 0}) {
    final v = double.tryParse(c.text.trim());
    return v == null || v < min || !v.isFinite ? null : v;
  }

  SynthOptions? get _value {
    final channels = _num(_channels, min: 1);
    final rate = _num(_rate);
    final frequency = _num(_frequency);
    final amplitude = _num(_amplitude);
    final seed = _num(_seed);
    final every = _num(_every);
    final dropouts = _num(_dropouts);
    final dropoutS = _num(_dropoutS);
    final jitterMs = widget.jitter ? _num(_jitterMs) : 0.0;
    if (channels == null ||
        channels > 4096 ||
        rate == null ||
        rate <= 0 ||
        frequency == null ||
        amplitude == null ||
        seed == null ||
        (_markers && every == null) ||
        dropouts == null ||
        dropoutS == null ||
        jitterMs == null) {
      return null;
    }
    return SynthOptions(
      spec: SynthSpec(
        preset: _preset,
        channels: channels.round(),
        rate: rate,
        frequency: frequency,
        amplitude: amplitude,
        noise: amplitude / 10,
        lineFrequency: _line,
        seed: seed.round(),
      ),
      markers: _markers
          ? MarkerSchedule(
              every: every! > 0 ? every : null,
              atEvents: _atEvents,
            )
          : null,
      impairments: Impairments(
        dropoutRate: dropouts,
        dropoutS: dropoutS,
        jitterS: jitterMs / 1000,
      ),
    );
  }

  void _changed() => widget.onChanged(_value);

  void _set(VoidCallback f) {
    setState(f);
    _changed();
  }

  bool get _usesFrequency => switch (_preset) {
    SynthPreset.sines || SynthPreset.testPattern || SynthPreset.stress => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget field(
      TextEditingController c,
      String label, {
      double w = 100,
      bool enabled = true,
    }) => SizedBox(
      width: w,
      child: TextField(
        controller: c,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(isDense: true, labelText: label),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<SynthPreset>(
          initialValue: _preset,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Signal',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final p in SynthPreset.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (p) => _set(() => _preset = p ?? _preset),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(_preset.description, style: theme.textTheme.bodySmall),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            field(_channels, 'Channels', w: 80),
            field(_rate, 'Rate (Hz)'),
            field(
              _frequency,
              'Frequency (Hz)',
              w: 110,
              enabled: _usesFrequency,
            ),
            field(_amplitude, 'Size (µV)', w: 80),
            field(_seed, 'Seed', w: 70),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 50, label: Text('50 Hz')),
                ButtonSegment(value: 60, label: Text('60 Hz')),
              ],
              selected: {_line},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _set(() => _line = v.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('Markers'),
              selected: _markers,
              onSelected: (v) => _set(() => _markers = v),
            ),
            if (_markers) ...[
              field(_every, 'Every (s, 0 for none)', w: 140),
              FilterChip(
                label: const Text('At events'),
                tooltip:
                    'A marker at each blink, spike, alpha burst or '
                    'impulse',
                selected: _atEvents,
                onSelected: (v) => _set(() => _atEvents = v),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            field(_dropouts, 'Dropouts per s', w: 110),
            field(_dropoutS, 'Dropout length (s)', w: 130),
            if (widget.jitter) field(_jitterMs, 'Jitter (ms)', w: 90),
          ],
        ),
      ],
    );
  }
}
