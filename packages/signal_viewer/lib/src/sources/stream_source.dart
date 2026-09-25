import 'package:flutter/foundation.dart';
import 'package:signal_core/signal_core.dart';

import '../model/stream_info.dart';
import '../model/view_settings.dart';

/// Samples of an irregular stream (events), all in memory.
class EventSamples {
  final Float64List times;
  final List<Float32List> channels;

  /// The samples of a string stream (LSL markers) per channel; [channels]
  /// then hold their numeric values, or NaN.
  final List<List<String>>? text;

  /// Whether each sample is a moment (drawn as a tick with its [text])
  /// rather than a level that holds until the next.
  final bool markers;

  const EventSamples(
    this.times,
    this.channels, {
    this.text,
    this.markers = false,
  });

  int get length => times.length;

  static final empty = EventSamples(Float64List(0), const []);
}

/// The data behind one tab: a group of ports of a recording or of a live
/// device.
abstract class StreamSource {
  StreamInfo get info;

  bool get live;

  /// Time range with data, in seconds.
  double get start;
  double get end;

  /// Fires when new data is available (live samples, indexing progress, a
  /// finished derived summary).
  Listenable get changes;

  /// Progress (0-1) of a derived summary being built, or null.
  double? get derivedProgress;

  /// Whether a recording is still being indexed, so [end] grows.
  bool get indexing;

  /// Shape of the regular stream over [t0, t1] reduced to [bins].
  Future<Envelope?> envelope(
    double t0,
    double t1,
    int bins,
    DerivedSpec derived, {
    bool binStats = false,
  });

  /// Full-resolution samples of the regular stream over [t0, t1).
  Future<SignalWindow?> read(double t0, double t1, DerivedSpec derived);

  /// Samples of an irregular stream.
  EventSamples events();
}

/// The processing a tab asks for, from its settings.
DerivedSpec derivedSpec(StreamInfo info, ViewSettings s, List<int> lanes) {
  if (info.irregular) return DerivedSpec.none;
  final mode = info.canReference ? s.refMode : RefMode.recorded;
  final average = mode == RefMode.average;
  final refs = s.refChannels.toList()..sort();
  return DerivedSpec(
    highpass: info.filterable ? s.highpass ?? 0 : 0,
    notch: info.filterable ? s.notch ?? 0 : 0,
    averageReference: average,
    exclude: average ? s.bad : const {},
    referenceOf: switch (mode) {
      RefMode.channel when refs.isNotEmpty => [refs.first],
      RefMode.subset when refs.isNotEmpty => refs,
      _ => null,
    },
    meanOf: s.mean && info.canMean
        ? [
            for (final c in lanes)
              if (!s.bad.contains(c)) c,
          ]
        : null,
  );
}
