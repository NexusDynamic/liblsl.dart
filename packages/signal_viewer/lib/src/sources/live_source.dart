import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:signal_core/signal_core.dart';

import '../model/stream_info.dart';
import 'columns.dart';
import 'live_buffers.dart';
import 'stream_source.dart';

/// One tab's view of live data (a device or an LSL stream): the newest
/// [liveBufferS] seconds.
///
/// Processed data (reference, filters, mean) is kept in an
/// [LiveProcessor] that takes in each new sample once, so a redraw only
/// copies the window instead of filtering it again.
class LiveStreamSource implements StreamSource {
  final LiveData session;
  @override
  final StreamInfo info;

  LiveProcessor? _processor;

  LiveStreamSource(this.session, this.info);

  int get _capacity => (liveBufferS * info.rate).ceil() + 1;

  /// The processor for [spec], brought up to date with the newest samples.
  LiveProcessor _processed(DerivedSpec spec) {
    var p = _processor;
    if (p == null || p.spec != spec) {
      p = _processor = LiveProcessor(
        spec,
        info.channelCount,
        info.rate,
        _capacity,
      );
    }
    final range = session.tickRange(info.channels, info.rate);
    if (range == null) return p;
    final (first, end) = range;
    var from = p.started ? math.max(p.end, first) : first;
    from = math.max(from, end - _capacity);
    if (end > from) {
      final cols = session.columnsAt(info.channels, info.rate, from, end);
      if (cols != null) p.append(cols, from);
    }
    return p;
  }

  /// Columns over [t0, t1) with [derived] applied, and their start time.
  (List<Float64List>, double)? _window(
    double t0,
    double t1,
    DerivedSpec derived,
  ) {
    if (info.irregular) return null;
    final from = (t0 * info.rate).floor();
    final to = (t1 * info.rate).ceil();
    if (derived.isIdentity) {
      final cols = session.columnsAt(info.channels, info.rate, from, to);
      return cols == null ? null : (cols, from / info.rate);
    }
    return (_processed(derived).read(from, to), from / info.rate);
  }

  @override
  bool get live => true;

  @override
  Listenable get changes => session.changes;

  @override
  double? get derivedProgress => null;

  @override
  bool get indexing => false;

  @override
  double get end => session.now;

  @override
  double get start => math.max(0, end - liveBufferS);

  @override
  Future<Envelope?> envelope(
    double t0,
    double t1,
    int bins,
    DerivedSpec derived, {
    bool binStats = false,
  }) async {
    final w = _window(t0, t1, derived);
    if (w == null) return null;
    final (cols, start) = w;
    return envelopeOf(cols, start, info.rate, t0, t1, bins, binStats: binStats);
  }

  @override
  Future<SignalWindow?> read(double t0, double t1, DerivedSpec derived) async {
    final w = _window(t0, t1, derived);
    if (w == null) return null;
    final (cols, start) = w;
    return SignalWindow(start, info.rate, [
      for (final c in cols) Float32List.fromList(c),
    ]);
  }

  @override
  EventSamples events() => session.events(info.streamIndices.first);
}
