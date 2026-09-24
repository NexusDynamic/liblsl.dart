import 'dart:typed_data';

import 'pyramid.dart';

/// One channel of one stream of a source (e.g. a port of a device, or a
/// stream of a recording).
class ChannelRef {
  final int stream;
  final int channel;

  const ChannelRef(this.stream, this.channel);

  @override
  bool operator ==(Object other) =>
      other is ChannelRef && other.stream == stream && other.channel == channel;

  @override
  int get hashCode => stream * 1024 + channel;

  @override
  String toString() => 'S$stream:$channel';
}

/// Processing applied to a set of channels for display: re-referencing
/// (average, or to chosen channels), high-pass and notch filters
/// (zero-phase), and a mean trace.
///
/// Channel numbers in [exclude], [referenceOf] and [meanOf] are indices
/// into the request's channel list, not device channel numbers.
class DerivedSpec {
  /// High-pass cutoff in Hz; 0 for none.
  final double highpass;

  /// Notch frequency in Hz; 0 for none.
  final double notch;

  /// Subtract the mean of the channels not in [exclude] from every channel.
  final bool averageReference;

  /// Channels left out of the average reference (e.g. bad channels).
  final Set<int> exclude;

  /// If not null (and [averageReference] is off), subtract the mean of
  /// these channels from every channel: one channel for a single-channel
  /// reference, several for e.g. linked ears.
  final List<int>? referenceOf;

  /// If not null, an extra output channel holds the mean of these channels
  /// (after referencing and filtering).
  final List<int>? meanOf;

  const DerivedSpec({
    this.highpass = 0,
    this.notch = 0,
    this.averageReference = false,
    this.exclude = const {},
    this.referenceOf,
    this.meanOf,
  });

  static const none = DerivedSpec();

  bool get filters => highpass > 0 || notch > 0;

  /// Whether this leaves the data unchanged.
  bool get isIdentity => !filters && !references && meanOf == null;

  /// Whether the channels are re-referenced.
  bool get references =>
      averageReference || (referenceOf != null && referenceOf!.isNotEmpty);

  /// Samples of real data to read on each side of a window so the filters
  /// settle before the part that is shown.
  int padSamples(double rate) {
    if (!filters) return 0;
    var seconds = 2.0;
    if (highpass > 0) {
      final s = 5 / highpass;
      seconds = s > 5 ? s : 5;
    }
    return (seconds * rate).ceil();
  }

  /// A key that identifies this processing, for caching.
  String get key {
    final ex = exclude.toList()..sort();
    final ref = [...?referenceOf]..sort();
    return 'hp=$highpass;n=$notch;ref=$averageReference;ex=${ex.join(',')};'
        'refof=${ref.join(',')};mean=${meanOf?.join(',')}';
  }

  @override
  bool operator ==(Object other) => other is DerivedSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'DerivedSpec($key)';
}

/// A request for the shape of some channels over a time range, reduced to
/// [bins] columns (typically one per pixel).
///
/// All channels must come from regular streams with the same sampling rate;
/// streams are aligned on their first sample times.
class EnvelopeRequest {
  final List<ChannelRef> channels;

  /// Start and end in seconds from the start of the recording.
  final double t0;
  final double t1;

  /// Number of columns to reduce the range to.
  final int bins;

  final DerivedSpec derived;

  /// Also return the mean and standard deviation of each bin
  /// ([Envelope.binMean], [Envelope.binStd]), e.g. for RMS over time.
  final bool binStats;

  const EnvelopeRequest({
    required this.channels,
    required this.t0,
    required this.t1,
    required this.bins,
    this.derived = DerivedSpec.none,
    this.binStats = false,
  });
}

/// The result of an [EnvelopeRequest].
///
/// When the range holds few samples per bin, [samples] is true and [min]
/// and [max] are the same lists of individual samples, the first at [start]
/// seconds and then every [step] seconds. Otherwise each of the [bins]
/// entries of [min] and [max] covers [step] seconds from [start]. Entries
/// without data are NaN.
class Envelope {
  final bool samples;
  final double start;
  final double step;

  /// Per output channel: the requested channels, then the mean trace if
  /// [DerivedSpec.meanOf] was set.
  final List<Float32List> min;
  final List<Float32List> max;

  /// Statistics of each output channel over the requested range.
  final List<SignalStats> stats;

  /// Samples per second of the channels.
  final double samplingRate;

  /// True when derived data was asked for but a coarse summary of the raw
  /// data was returned, because the derived summary is still being built.
  final bool approximate;

  /// Mean and standard deviation of each bin, per output channel, when
  /// [EnvelopeRequest.binStats] was set (not in [samples] mode).
  final List<Float32List>? binMean;
  final List<Float32List>? binStd;

  const Envelope({
    required this.samples,
    required this.start,
    required this.step,
    required this.min,
    required this.max,
    required this.stats,
    required this.samplingRate,
    this.approximate = false,
    this.binMean,
    this.binStd,
  });

  int get length => min.isEmpty ? 0 : min.first.length;
}

/// A request for the full-resolution samples of some channels over a time
/// range. Channels follow the same rules as in [EnvelopeRequest].
class ReadRequest {
  final List<ChannelRef> channels;
  final double t0;
  final double t1;
  final DerivedSpec derived;

  const ReadRequest({
    required this.channels,
    required this.t0,
    required this.t1,
    this.derived = DerivedSpec.none,
  });
}

/// Samples of some channels, evenly spaced: sample `i` is at
/// `start + i / samplingRate` seconds. Missing values are NaN.
class SignalWindow {
  final double start;
  final double samplingRate;

  /// Per output channel, like [Envelope.min].
  final List<Float32List> channels;

  const SignalWindow(this.start, this.samplingRate, this.channels);

  int get length => channels.isEmpty ? 0 : channels.first.length;
}

/// Progress of building a derived summary in the background.
class DerivedProgress {
  final String key;
  final double progress;
  final bool done;

  const DerivedProgress(this.key, this.progress, this.done);
}
