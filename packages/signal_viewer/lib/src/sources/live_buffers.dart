import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:signal_core/signal_core.dart';

import 'stream_source.dart';

/// Seconds of live data kept per stream.
const liveBufferS = 60.0;

/// Live data behind [LiveStreamSource]: a device or an LSL stream.
abstract class LiveData {
  /// Fires for new samples.
  Listenable get changes;

  /// Latest time with data, in seconds.
  double get now;

  /// Columns of the regular channels [refs] over ticks [from, to) of the
  /// grid at [rate] Hz (tick = time × rate), NaN where there is no data.
  List<Float64List>? columnsAt(
    List<ChannelRef> refs,
    double rate,
    int from,
    int to,
  );

  /// Ticks [first, end) that every stream of [refs] has data for, or null
  /// if a stream has none yet.
  (int, int)? tickRange(List<ChannelRef> refs, double rate);

  EventSamples events(int stream);
}

/// Samples of one regular stream at [rate], in a ring buffer: sample
/// (ordinal) `n` is at `t0 + n / rate`.
class RegularRing {
  final int channelCount;
  final double rate;
  final int capacity;
  final List<Float32List> _data;

  /// Ordinal of the next sample.
  int written = 0;

  /// Time of ordinal 0.
  double t0 = 0;

  /// Samples filled in by interpolation.
  int lost = 0;

  late final Float64List _last = Float64List(channelCount);

  RegularRing(this.channelCount, this.rate)
    : capacity = (rate * liveBufferS).ceil() + 1,
      _data = List.generate(
        channelCount,
        (_) => Float32List((rate * liveBufferS).ceil() + 1),
      );

  int get first => math.max(0, written - capacity);

  /// Time just after the newest sample.
  double get end => t0 + written / rate;

  /// Add one sample: `values[offset + c]` for each channel.
  void add(List<double> values, [int offset = 0]) {
    final slot = written % capacity;
    for (var c = 0; c < channelCount; c++) {
      final v = values[offset + c];
      _data[c][slot] = v;
      _last[c] = v;
    }
    written++;
  }

  /// Fill [count] lost samples by interpolating from the last sample
  /// towards the next one (`values[offset + c]`).
  void fill(int count, List<double> values, [int offset = 0]) {
    if (count <= 0) return;
    lost += count;
    // Beyond the buffer, only the newest samples are kept.
    final skip = math.max(0, count - capacity);
    written += skip;
    final row = Float64List(channelCount);
    for (var k = skip + 1; k <= count; k++) {
      final f = k / (count + 1);
      for (var c = 0; c < channelCount; c++) {
        row[c] = _last[c] + (values[offset + c] - _last[c]) * f;
      }
      final slot = written % capacity;
      for (var c = 0; c < channelCount; c++) {
        _data[c][slot] = row[c];
      }
      written++;
    }
    for (var c = 0; c < channelCount; c++) {
      _last[c] = row[c];
    }
  }

  /// Copy ordinals [from, to) of [channel] into [dest] at [offset].
  void copy(int channel, int from, int to, Float64List dest, int offset) {
    final a = math.max(from, first), z = math.min(to, written);
    final src = _data[channel];
    for (var o = a; o < z; o++) {
      dest[offset + o - from] = src[o % capacity];
    }
  }

  /// Tick of ordinal 0 on the grid at [gridRate].
  int origin(double gridRate) => (t0 * gridRate).round();
}

/// Samples of an irregular stream, kept for [keepS] seconds (all of them
/// with the default).
class IrregularLog {
  final int channelCount;
  final double keepS;

  /// Whether values are strings (LSL markers).
  final bool strings;

  Float64List _times = Float64List(64);
  List<Float32List> _values;
  List<List<String>>? _text;
  int _start = 0, _end = 0;

  IrregularLog(
    this.channelCount, {
    this.keepS = double.infinity,
    this.strings = false,
  }) : _values = List.generate(channelCount, (_) => Float32List(64)),
       _text = strings ? List.generate(channelCount, (_) => <String>[]) : null;

  int get length => _end - _start;

  double? get lastTime => length == 0 ? null : _times[_end - 1];

  /// Add a sample at [t]: `values[offset + c]` for each channel, and for a
  /// string stream its [text].
  void add(
    double t,
    List<double> values, [
    int offset = 0,
    List<String>? text,
  ]) {
    if (_end == _times.length) _grow();
    _times[_end] = t;
    for (var c = 0; c < channelCount; c++) {
      _values[c][_end] = values[offset + c];
      _text?[c].add(text == null ? '' : text[offset + c]);
    }
    _end++;
  }

  /// Make room: drop what is older than [keepS], then double the capacity
  /// if still needed. New lists each time, so [events] handed out earlier
  /// stay as they were.
  void _grow() {
    var from = _start;
    if (keepS.isFinite && _end > _start) {
      final cutoff = _times[_end - 1] - keepS;
      while (from < _end && _times[from] < cutoff) {
        from++;
      }
    }
    final n = _end - from;
    final cap = math.max(64, n * 2);
    _times = Float64List(cap)..setRange(0, n, _times, from);
    _values = [
      for (final v in _values) Float32List(cap)..setRange(0, n, v, from),
    ];
    if (_text != null) {
      _text = [for (final t in _text!) t.sublist(from - _start)];
    }
    _start = 0;
    _end = n;
  }

  EventSamples events({bool markers = false}) {
    if (length == 0) return EventSamples.empty;
    return EventSamples(
      Float64List.sublistView(_times, _start, _end),
      [for (final v in _values) Float32List.sublistView(v, _start, _end)],
      text: _text == null
          ? null
          : [for (final t in _text!) UnmodifiableListView(t)],
      markers: markers,
    );
  }
}

/// Columns of [refs] from [rings] (by stream), see [LiveData.columnsAt].
List<Float64List>? ringColumns(
  Map<int, RegularRing> rings,
  List<ChannelRef> refs,
  double rate,
  int from,
  int to,
) {
  final bufs = {for (final r in refs) r.stream: rings[r.stream]};
  if (bufs.values.any((b) => b == null)) return null;
  final n = math.max(0, to - from);
  final cols = [
    for (final _ in refs) Float64List(n)..fillRange(0, n, double.nan),
  ];
  for (var i = 0; i < refs.length; i++) {
    final b = bufs[refs[i].stream]!;
    final origin = b.origin(rate);
    b.copy(refs[i].channel, from - origin, to - origin, cols[i], 0);
  }
  return cols;
}

/// See [LiveData.tickRange].
(int, int)? ringTickRange(
  Map<int, RegularRing> rings,
  List<ChannelRef> refs,
  double rate,
) {
  int? first, end;
  for (final stream in {for (final r in refs) r.stream}) {
    final b = rings[stream];
    if (b == null || b.written == 0) return null;
    final o = b.origin(rate);
    first = math.max(first ?? o + b.first, o + b.first);
    end = math.min(end ?? o + b.written, o + b.written);
  }
  if (first == null || end == null) return null;
  return (first, math.max(first, end));
}

class Changes extends ChangeNotifier {
  void ping() => notifyListeners();
}
