import 'dart:math' as math;
import 'dart:typed_data';

/// Min, max, mean and standard deviation of one channel over a run of
/// samples.
class SignalStats {
  double min;
  double max;
  double mean;
  double std;

  /// Number of samples (rows) the statistics cover.
  int count;

  SignalStats([
    this.min = double.nan,
    this.max = double.nan,
    this.mean = double.nan,
    this.std = double.nan,
    this.count = 0,
  ]);

  /// Largest distance of any sample from the mean.
  double get peakDeviation => math.max(max - mean, mean - min);

  bool get isEmpty => count == 0 || mean.isNaN;

  void clear() {
    min = max = mean = std = double.nan;
    count = 0;
  }

  /// Merge the statistics of another run (parallel variance formula).
  void merge(double min, double max, double mean, double std, int count) {
    if (count <= 0 || mean.isNaN) return;
    if (this.count == 0 || this.mean.isNaN) {
      this.min = min;
      this.max = max;
      this.mean = mean;
      this.std = std;
      this.count = count;
      return;
    }
    if (min < this.min) this.min = min;
    if (max > this.max) this.max = max;
    final n = this.count + count;
    final m = (this.mean * this.count + mean * count) / n;
    final da = this.mean - m;
    final db = mean - m;
    final v =
        (this.count * (this.std * this.std + da * da) +
            count * (std * std + db * db)) /
        n;
    this.mean = m;
    this.std = math.sqrt(v);
    this.count = n;
  }

  @override
  String toString() =>
      'SignalStats(min $min, max $max, mean $mean, std $std, n $count)';
}

/// A summary pyramid of one multi-channel signal: for each bucket of
/// consecutive samples, per channel min, max, mean and standard deviation.
///
/// Level 0 buckets hold [baseBucket] samples; each level above combines
/// [fanout] buckets of the level below. This lets a view of any length be
/// drawn from a few thousand buckets instead of millions of samples.
///
/// Samples are appended with [add]; [finish] closes the partial buckets at
/// the end. Buckets can be queried while samples are still being added.
class SummaryPyramid {
  static const int baseBucket = 64;
  static const int fanout = 4;

  /// Values stored per bucket and channel: min, max, mean, std.
  static const int _stride = 4;

  final int channelCount;

  final List<_Level> _levels = [];

  /// Samples added so far.
  int _rows = 0;

  // Level 0 accumulators, per channel. Sums are taken relative to the
  // bucket's first value so a large DC offset does not cost precision.
  final Float64List _min;
  final Float64List _max;
  final Float64List _shift;
  final Float64List _sum;
  final Float64List _sumSq;
  final Int32List _n;
  int _bucketRows = 0;
  bool _finished = false;

  SummaryPyramid(this.channelCount)
    : _min = Float64List(channelCount),
      _max = Float64List(channelCount),
      _shift = Float64List(channelCount),
      _sum = Float64List(channelCount),
      _sumSq = Float64List(channelCount),
      _n = Int32List(channelCount) {
    _levels.add(_Level(channelCount * _stride));
    _resetAccumulators();
  }

  /// Samples added so far.
  int get length => _rows;

  /// Number of levels with at least one bucket.
  int get levelCount {
    var n = _levels.length;
    while (n > 1 && _levels[n - 1].count == 0) {
      n--;
    }
    return n;
  }

  /// Samples per bucket at [level].
  static int bucketSize(int level) {
    var size = baseBucket;
    for (var i = 0; i < level; i++) {
      size *= fanout;
    }
    return size;
  }

  /// Number of complete (or, after [finish], final partial) buckets at
  /// [level].
  int bucketCount(int level) =>
      level < _levels.length ? _levels[level].count : 0;

  /// Memory used by the buckets, in bytes.
  int get sizeInBytes => _levels.fold(0, (s, l) => s + l.data.lengthInBytes);

  void _resetAccumulators() {
    _min.fillRange(0, channelCount, double.infinity);
    _max.fillRange(0, channelCount, double.negativeInfinity);
    _sum.fillRange(0, channelCount, 0);
    _sumSq.fillRange(0, channelCount, 0);
    _n.fillRange(0, channelCount, 0);
    _bucketRows = 0;
  }

  /// Append one sample. [row] holds at least [channelCount] values; NaN
  /// values (missing data) are left out of the statistics.
  void add(Float64List row) {
    assert(!_finished);
    for (var c = 0; c < channelCount; c++) {
      final v = row[c];
      if (v.isNaN) continue;
      final n = _n[c];
      if (n == 0) _shift[c] = v;
      if (v < _min[c]) _min[c] = v;
      if (v > _max[c]) _max[c] = v;
      final d = v - _shift[c];
      _sum[c] += d;
      _sumSq[c] += d * d;
      _n[c] = n + 1;
    }
    _rows++;
    if (++_bucketRows == baseBucket) _closeBaseBucket();
  }

  /// Append [length] samples from per-channel [columns], starting at
  /// [start].
  void addColumns(List<List<double>> columns, int start, int length) {
    final row = Float64List(channelCount);
    for (var i = start; i < start + length; i++) {
      for (var c = 0; c < channelCount; c++) {
        row[c] = columns[c][i];
      }
      add(row);
    }
  }

  void _closeBaseBucket() {
    final level = _levels[0];
    final base = level.grow();
    final d = level.data;
    for (var c = 0; c < channelCount; c++) {
      final o = base + c * _stride;
      final n = _n[c];
      if (n == 0) {
        d[o] = d[o + 1] = d[o + 2] = d[o + 3] = double.nan;
        continue;
      }
      final m = _sum[c] / n;
      final v = _sumSq[c] / n - m * m;
      d[o] = _min[c];
      d[o + 1] = _max[c];
      d[o + 2] = _shift[c] + m;
      d[o + 3] = v > 0 ? math.sqrt(v) : 0;
    }
    _resetAccumulators();
    _propagate(0);
  }

  /// Combine the last [fanout] buckets of [level] into the level above
  /// whenever they complete a group.
  void _propagate(int level) {
    while (_levels[level].count % fanout == 0) {
      final from = _levels[level].count - fanout;
      _combine(level, from, fanout, _rowsIn(level, from, fanout));
      level++;
    }
  }

  /// Rows in [n] buckets of [level] starting at [from], given the samples
  /// added so far.
  List<int> _rowsIn(int level, int from, int n) {
    final size = bucketSize(level);
    return [
      for (var i = 0; i < n; i++)
        math.max(0, math.min(size, _rows - (from + i) * size)),
    ];
  }

  void _combine(int level, int from, int n, List<int> rows) {
    if (_levels.length == level + 1) {
      _levels.add(_Level(channelCount * _stride));
    }
    final src = _levels[level].data;
    final dst = _levels[level + 1];
    final base = dst.grow();
    final stats = SignalStats();
    for (var c = 0; c < channelCount; c++) {
      stats.clear();
      for (var i = 0; i < n; i++) {
        final o = (from + i) * channelCount * _stride + c * _stride;
        stats.merge(src[o], src[o + 1], src[o + 2], src[o + 3], rows[i]);
      }
      final o = base + c * _stride;
      dst.data[o] = stats.min;
      dst.data[o + 1] = stats.max;
      dst.data[o + 2] = stats.mean;
      dst.data[o + 3] = stats.std;
    }
  }

  /// Close the partial buckets at the end of the signal, so every sample is
  /// covered at every level up to a single top bucket. No samples can be
  /// added afterwards.
  void finish() {
    if (_finished) return;
    _finished = true;
    if (_bucketRows > 0) _closeBaseBucket();
    var level = 0;
    while (_levels[level].count > 1) {
      final count = _levels[level].count;
      final rest = count % fanout;
      if (rest != 0) {
        final from = count - rest;
        _combine(level, from, rest, _rowsIn(level, from, rest));
        if (_levels[level + 1].count % fanout == 0) _propagate(level + 1);
      }
      level++;
    }
  }

  /// Merge the statistics of [channel] over buckets [from, to) of [level]
  /// into [out]. Buckets that do not exist yet are skipped.
  void reduce(int level, int channel, int from, int to, SignalStats out) {
    if (level >= _levels.length) return;
    final l = _levels[level];
    if (from < 0) from = 0;
    if (to > l.count) to = l.count;
    if (from >= to) return;
    final size = bucketSize(level);
    final d = l.data;
    final step = channelCount * _stride;
    var o = from * step + channel * _stride;
    for (var b = from; b < to; b++, o += step) {
      final rows = math.min(size, _rows - b * size);
      if (rows <= 0) break;
      out.merge(d[o], d[o + 1], d[o + 2], d[o + 3], rows);
    }
  }

  /// Min and max of [channel] over buckets [from, to) of [level], written
  /// to [out] (min, max). Faster than [reduce] when only the range is
  /// needed. Returns false if there is no data.
  bool range(int level, int channel, int from, int to, Float64List out) {
    if (level >= _levels.length) return false;
    final l = _levels[level];
    if (from < 0) from = 0;
    if (to > l.count) to = l.count;
    if (from >= to) return false;
    final d = l.data;
    final step = channelCount * _stride;
    var mn = double.infinity;
    var mx = double.negativeInfinity;
    var o = from * step + channel * _stride;
    for (var b = from; b < to; b++, o += step) {
      final a = d[o];
      final z = d[o + 1];
      if (a < mn) mn = a;
      if (z > mx) mx = z;
    }
    if (mn > mx) return false;
    out[0] = mn;
    out[1] = mx;
    return true;
  }
}

class _Level {
  final int stride;
  Float32List data;
  int count = 0;

  _Level(this.stride) : data = Float32List(stride * 64);

  /// Make room for one more bucket and return its offset.
  int grow() {
    final offset = count * stride;
    if (offset + stride > data.length) {
      data = Float32List(data.length * 2)..setRange(0, offset, data);
    }
    count++;
    return offset;
  }
}
