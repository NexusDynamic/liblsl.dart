import 'dart:math' as math;
import 'dart:typed_data';

import '../requests.dart';
import 'sos.dart';

/// Causal processing of a live stream for display, one block at a time.
///
/// Samples are appended as they arrive; each is referenced and filtered
/// once, with filter state carried across blocks, and kept in a ring buffer
/// of [capacity] samples. Reading a window then only copies. This is what
/// makes a redraw cheap no matter how long the filters take to settle.
///
/// Positions are ticks: sample numbers on the stream's sample grid.
class LiveProcessor {
  final DerivedSpec spec;
  final int channelCount;
  final int capacity;

  final SosStreamFilter _filter;
  final List<Float32List> _out;

  /// Tick of the first sample kept, and one past the last processed.
  int _begin = 0;
  int _end = 0;
  bool _started = false;

  LiveProcessor(this.spec, this.channelCount, double rate, this.capacity)
    : _filter = SosStreamFilter(
        Sos.display(rate, highpass: spec.highpass, notch: spec.notch),
        channelCount,
      ),
      _out = List.generate(
        channelCount + (spec.meanOf != null ? 1 : 0),
        (_) => Float32List(capacity),
      );

  /// Number of output channels: one per input, plus the mean trace if
  /// [DerivedSpec.meanOf] is set.
  int get outputCount => _out.length;

  bool get started => _started;

  /// One past the last processed tick.
  int get end => _end;

  /// First tick still in the buffer.
  int get begin => math.max(_begin, _end - capacity);

  /// Process [cols] (one list per input channel, raw samples starting at
  /// tick [start]) and keep the result. The columns are modified.
  ///
  /// Blocks should follow each other. A block that overlaps what was
  /// processed is trimmed; after a gap, the filters restart.
  void append(List<List<double>> cols, int start) {
    if (cols.isEmpty) return;
    final n = cols.first.length;
    var from = 0;
    if (!_started) {
      _started = true;
      _begin = _end = start;
    } else if (start < _end) {
      from = _end - start; // already have these
      if (from >= n) return;
    } else if (start > _end) {
      _filter.reset();
      if (start - _end >= capacity) {
        _begin = start;
      } else {
        _fillNaN(_end, start);
      }
      _end = start;
    }
    applyReference(cols, spec, from: from, to: n);
    if (_filter.active) {
      for (var c = 0; c < channelCount; c++) {
        _filterRuns(c, cols[c], from, n);
      }
    }
    final meanOf = spec.meanOf;
    for (var i = from; i < n; i++) {
      final slot = (_end + i - from) % capacity;
      for (var c = 0; c < channelCount; c++) {
        _out[c][slot] = cols[c][i];
      }
      if (meanOf != null) {
        var sum = 0.0;
        var count = 0;
        for (final c in meanOf) {
          final v = cols[c][i];
          if (v.isNaN) continue;
          sum += v;
          count++;
        }
        _out[channelCount][slot] = count == 0 ? double.nan : sum / count;
      }
    }
    _end += n - from;
  }

  /// Filter the stretches of [x] without NaN; the filter restarts after
  /// each gap.
  void _filterRuns(int channel, List<double> x, int from, int to) {
    var i = from;
    while (i < to) {
      if (x[i].isNaN) {
        _filter.reset(channel);
        i++;
        continue;
      }
      var j = i;
      while (j < to && !x[j].isNaN) {
        j++;
      }
      _filter.process(channel, x, from: i, to: j);
      i = j;
    }
  }

  void _fillNaN(int from, int to) {
    for (var t = from; t < to; t++) {
      final slot = t % capacity;
      for (final o in _out) {
        o[slot] = double.nan;
      }
    }
  }

  /// Processed samples of ticks [from, to) of each output channel, NaN
  /// where there are none.
  List<Float64List> read(int from, int to) {
    final n = math.max(0, to - from);
    final a = math.max(from, begin), z = math.min(to, _end);
    return [
      for (final o in _out)
        () {
          final col = Float64List(n)..fillRange(0, n, double.nan);
          for (var t = a; t < z; t++) {
            col[t - from] = o[t % capacity];
          }
          return col;
        }(),
    ];
  }
}
