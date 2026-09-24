import 'dart:math' as math;

import 'stream_info.dart';

enum ScaleMode {
  fixed('Fixed'),
  auto('Auto (shared)'),
  perChannel('Auto (per channel)');

  final String label;
  const ScaleMode(this.label);
}

enum ColourMode { channel, power }

enum PowerStyle {
  trace('Trace colour'),
  heatmap('Lane heatmap'),
  both('Both');

  final String label;
  const PowerStyle(this.label);
}

/// What the channels are referenced to.
enum RefMode {
  recorded('As recorded', 'As recorded'),
  average('Average of good channels', 'Avg'),
  channel('One channel', 'Ch'),
  subset('Mean of chosen channels', 'Set');

  final String label;
  final String short;
  const RefMode(this.label, this.short);
}

const highpassPresets = <double?>[null, 0.1, 0.5, 1, 5, 10, 20];
const notchPresets = <double?>[null, 50, 60];

/// The display choices of one tab. Channels are indices into the stream's
/// labels; [scale] is the signal value per lane (e.g. µV/div) in fixed
/// mode.
class ViewSettings {
  final double windowS;
  final ScaleMode scaleMode;
  final double scale;
  final Set<int> hidden;
  final Set<int> bad;
  final bool baseline;

  /// Re-referencing: average of the good channels, or the mean of
  /// [refChannels].
  final RefMode refMode;
  final Set<int> refChannels;

  /// One trace: the mean of the shown good channels.
  final bool mean;
  final double? highpass;
  final double? notch;
  final ColourMode colour;
  final String powerMetric;
  final PowerStyle powerStyle;

  /// Event channels decoded as Manchester trigger words.
  final Set<int> decoded;

  const ViewSettings({
    this.windowS = 10,
    this.scaleMode = ScaleMode.fixed,
    this.scale = 100,
    this.hidden = const {},
    this.bad = const {},
    this.baseline = true,
    this.refMode = RefMode.recorded,
    this.refChannels = const {},
    this.mean = false,
    this.highpass,
    this.notch,
    this.colour = ColourMode.channel,
    this.powerMetric = 'rms',
    this.powerStyle = PowerStyle.trace,
    this.decoded = const {},
  });

  ViewSettings copyWith({
    double? windowS,
    ScaleMode? scaleMode,
    double? scale,
    Set<int>? hidden,
    Set<int>? bad,
    bool? baseline,
    RefMode? refMode,
    Set<int>? refChannels,
    bool? mean,
    double? Function()? highpass,
    double? Function()? notch,
    ColourMode? colour,
    String? powerMetric,
    PowerStyle? powerStyle,
    Set<int>? decoded,
  }) => ViewSettings(
    windowS: windowS ?? this.windowS,
    scaleMode: scaleMode ?? this.scaleMode,
    scale: scale ?? this.scale,
    hidden: hidden ?? this.hidden,
    bad: bad ?? this.bad,
    baseline: baseline ?? this.baseline,
    refMode: refMode ?? this.refMode,
    refChannels: refChannels ?? this.refChannels,
    mean: mean ?? this.mean,
    highpass: highpass != null ? highpass() : this.highpass,
    notch: notch != null ? notch() : this.notch,
    colour: colour ?? this.colour,
    powerMetric: powerMetric ?? this.powerMetric,
    powerStyle: powerStyle ?? this.powerStyle,
    decoded: decoded ?? this.decoded,
  );

  /// Keep only the choices that apply to [info] (validity rules of the
  /// Python viewer).
  ViewSettings validFor(StreamInfo info) {
    var s = this;
    if (!info.badChannels) s = s.copyWith(bad: const {});
    if (!info.canReference) {
      s = s.copyWith(refMode: RefMode.recorded, refChannels: const {});
    } else {
      final refs = {
        for (final c in s.refChannels)
          if (c < info.channelCount) c,
      };
      if (refs.length != s.refChannels.length) {
        s = s.copyWith(refChannels: refs);
      }
    }
    if (!info.canMean) s = s.copyWith(mean: false);
    if (!info.filterable) {
      s = s.copyWith(
        highpass: () => null,
        notch: () => null,
        colour: ColourMode.channel,
      );
    }
    return s;
  }
}

/// Defaults a new tab of one kind starts with (Preferences).
class KindDefaults {
  final double windowS;
  final ScaleMode scaleMode;
  final double scale;
  final double? highpass;
  final double? notch;
  final RefMode refMode;

  /// Labels of the reference channels (channel numbers differ between
  /// devices and port setups).
  final List<String> refLabels;

  const KindDefaults({
    this.windowS = 10,
    this.scaleMode = ScaleMode.fixed,
    this.scale = 100,
    this.highpass,
    this.notch,
    this.refMode = RefMode.recorded,
    this.refLabels = const [],
  });

  /// The defaults a tab's current [s] would give ([labels] are its
  /// channel labels).
  factory KindDefaults.of(ViewSettings s, List<String> labels) => KindDefaults(
    windowS: s.windowS,
    scaleMode: s.scaleMode,
    scale: s.scale,
    highpass: s.highpass,
    notch: s.notch,
    refMode: s.refMode,
    refLabels: [
      for (final c in s.refChannels.toList()..sort())
        if (c < labels.length) labels[c],
    ],
  );

  KindDefaults copyWith({
    double? windowS,
    ScaleMode? scaleMode,
    double? scale,
    double? Function()? highpass,
    double? Function()? notch,
    RefMode? refMode,
    List<String>? refLabels,
  }) => KindDefaults(
    windowS: windowS ?? this.windowS,
    scaleMode: scaleMode ?? this.scaleMode,
    scale: scale ?? this.scale,
    highpass: highpass != null ? highpass() : this.highpass,
    notch: notch != null ? notch() : this.notch,
    refMode: refMode ?? this.refMode,
    refLabels: refLabels ?? this.refLabels,
  );

  static const factory = {
    Kind.eeg: KindDefaults(highpass: 0.5),
    Kind.emg: KindDefaults(highpass: 20),
    Kind.imu: KindDefaults(scaleMode: ScaleMode.perChannel),
    Kind.event: KindDefaults(),
    Kind.other: KindDefaults(scaleMode: ScaleMode.perChannel),
  };

  /// Settings for a new tab whose channels have [labels].
  ViewSettings toSettings([List<String> labels = const []]) {
    final refs = {
      for (final l in refLabels)
        if (labels.contains(l)) labels.indexOf(l),
    };
    // A channel reference that is not in this stream falls back to the
    // recorded one.
    final mode =
        (refMode == RefMode.channel || refMode == RefMode.subset) &&
            refs.isEmpty
        ? RefMode.recorded
        : refMode;
    return ViewSettings(
      windowS: windowS,
      scaleMode: scaleMode,
      scale: scale,
      highpass: highpass,
      notch: notch,
      refMode: mode,
      refChannels: refs,
    );
  }

  Map<String, Object?> toJson() => {
    'window_s': windowS,
    'scale_mode': scaleMode.name,
    'scale': scale,
    'highpass': highpass,
    'notch': notch,
    'ref_mode': refMode.name,
    'ref_labels': refLabels,
  };

  static KindDefaults fromJson(Map<String, Object?> j, KindDefaults fallback) =>
      KindDefaults(
        windowS: (j['window_s'] as num?)?.toDouble() ?? fallback.windowS,
        scaleMode: ScaleMode.values.firstWhere(
          (m) => m.name == j['scale_mode'],
          orElse: () => fallback.scaleMode,
        ),
        scale: (j['scale'] as num?)?.toDouble() ?? fallback.scale,
        highpass: j.containsKey('highpass')
            ? (j['highpass'] as num?)?.toDouble()
            : fallback.highpass,
        notch: j.containsKey('notch')
            ? (j['notch'] as num?)?.toDouble()
            : fallback.notch,
        refMode: switch (j['ref_mode']) {
          final String m => RefMode.values.firstWhere(
            (r) => r.name == m,
            orElse: () => fallback.refMode,
          ),
          // Saved by versions with only the average reference.
          _ => switch (j['reference']) {
            true => RefMode.average,
            false => RefMode.recorded,
            _ => fallback.refMode,
          },
        },
        refLabels: [
          for (final l in (j['ref_labels'] as List?) ?? const []) '$l',
        ],
      );
}

String formatHz(double? value) => value == null ? 'Off' : '${_g(value)} Hz';

/// A rough time left: "5 s", "3 min 20 s", "1 h 5 min".
String formatRemaining(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${math.max(1, s)} s';
  if (s < 3600) {
    // Nearer 10 s is enough past a minute.
    final r = (s / 10).round() * 10;
    return r % 60 == 0 ? '${r ~/ 60} min' : '${r ~/ 60} min ${r % 60} s';
  }
  final m = (s / 60).round();
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

/// "0.5 Hz" -> 0.5; "off", "" or "0" -> null. Accepts a decimal comma.
/// Throws [FormatException] if the text is not a frequency.
double? parseHz(String text) {
  var t = text.trim().toLowerCase();
  if (t.endsWith('hz')) t = t.substring(0, t.length - 2).trim();
  if (t.isEmpty || t == 'off' || t == 'none') return null;
  final value = double.parse(t.replaceAll(',', '.'));
  if (value < 0 || !value.isFinite) throw FormatException('Invalid', text);
  return value == 0 ? null : value;
}

/// A number without trailing zeros, like Python's `:g`.
String _g(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsPrecision(6);
  if (s.contains('.') && !s.contains('e')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

String formatNumber(double v) => _g(v);
