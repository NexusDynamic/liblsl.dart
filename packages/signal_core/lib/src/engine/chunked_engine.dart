import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../dsp/sos.dart';
import '../io/byte_source.dart';
import '../pyramid.dart';
import '../requests.dart';
import 'chunked_index.dart';

/// Channels of regular streams with the same rate, aligned on a common grid
/// of *group ordinals*: `t = t0 + g / rate`.
class _Group {
  final List<ChannelRef> channels;
  final double rate;
  final double t0;
  final int length;
  final Map<int, int> offsets;

  _Group(this.channels, this.rate, this.t0, this.length, this.offsets);

  String get key => channels.join(',');
}

class _DerivedBuild {
  final String key;
  final _Group group;
  final DerivedSpec spec;
  final SummaryPyramid pyramid;
  bool done = false;
  bool cancelled = false;

  _DerivedBuild(this.key, this.group, this.spec, int channels)
    : pyramid = SummaryPyramid(channels);
}

/// Answers [EnvelopeRequest]s and [ReadRequest]s for a recording split into
/// chunks by a [ChunkedSignalIndex], without loading it into memory.
///
/// Views are answered from the index's summary pyramids, or by decoding
/// just the chunks they cover, which are kept in a bounded cache. Filtered
/// and re-referenced views ([DerivedSpec]) are computed in tiles that are
/// kept between requests, and, once the index is complete, summarised into
/// derived pyramids in the background (see [onDerivedProgress]).
///
/// A file format provides the index (and keeps it growing while the file
/// is indexed); this class does the rest.
abstract class ChunkedSignalEngine {
  final ByteSource source;

  /// Memory budget for decoded chunks.
  final int cacheBytes;

  /// Finished derived summaries (filtered views) to keep.
  final int derivedCacheCount;

  /// Memory budget for filtered data kept between requests, so a view that
  /// moves a little (scrolling) is not filtered again.
  final int filteredCacheBytes;

  ChunkedSignalEngine(
    this.source, {
    required this.cacheBytes,
    required this.derivedCacheCount,
    required this.filteredCacheBytes,
  });

  /// The chunks, streams and summary pyramids of the recording.
  ChunkedSignalIndex get chunkIndex;

  final Map<int, ChunkData> _cache = {};
  final Map<int, Future<ChunkData>> _pending = {};
  int _cacheSize = 0;

  final _derivedController = StreamController<DerivedProgress>.broadcast();
  bool _closed = false;

  final Map<String, _DerivedBuild> _derived = {};

  // Filtered tiles of [_tileSize] group ordinals, see [_filtered].
  static const int _tileSize = 1 << 14;
  final Map<String, List<Float32List>> _tiles = {};
  final Map<String, Future<List<Float32List>>> _tilesPending = {};
  int _tileBytes = 0;

  /// [read] and [envelope] calls running. Background work (summaries,
  /// prefetching) gives way to them, see [_giveWay].
  int _requests = 0;
  final Stopwatch _sinceGiveWay = Stopwatch()..start();

  /// Filtered tiles served from memory and computed, for tests and tools.
  int tileHits = 0, tileMisses = 0;

  /// Bytes of filtered tiles kept (within [filteredCacheBytes]).
  int get tileCacheBytes => _tileBytes;

  /// Whether [closeEngine] was called.
  bool get isClosed => _closed;

  /// Progress of derived summaries (filtered views) being built. Request
  /// the envelope again when one is done.
  Stream<DerivedProgress> get onDerivedProgress => _derivedController.stream;

  /// Stop background work and drop the caches. Does not close [source].
  Future<void> closeEngine() async {
    if (_closed) return;
    _closed = true;
    for (final b in _derived.values) {
      b.cancelled = true;
    }
    _cache.clear();
    _tiles.clear();
    await _derivedController.close();
  }

  // -- chunks ---------------------------------------------------------------

  /// Decoded chunk [index], from the cache or the file. With [keep] false a
  /// decoded chunk is not added to the cache (for one-off full passes).
  Future<ChunkData> chunk(int index, {bool keep = true}) {
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached; // most recently used
      return Future.value(cached);
    }
    return _pending[index] ??= _decode(index, keep).whenComplete(() {
      // A block body: returning the removed future would make this one
      // wait for itself.
      _pending.remove(index);
    });
  }

  Future<ChunkData> _decode(int index, bool keep) async {
    final c = chunkIndex.chunks[index];
    final bytes = await source.read(c.offset, c.length);
    final data = chunkIndex.decodeChunk(c, bytes);
    // A binary file is a single chunk that grows while indexing.
    final stable = chunkIndex.complete || index < chunkIndex.chunks.length - 1;
    if (keep && stable && !_closed) {
      _cache[index] = data;
      _cacheSize += data.sizeInBytes;
      while (_cacheSize > cacheBytes && _cache.length > 1) {
        final oldest = _cache.keys.first;
        _cacheSize -= _cache.remove(oldest)!.sizeInBytes;
      }
    }
    return data;
  }

  /// Index of the chunk holding ordinal [ordinal] of [stream]: the last chunk
  /// whose first ordinal is not after it.
  int _chunkFor(int stream, int ordinal) {
    final chunks = chunkIndex.chunks;
    var lo = 0, hi = chunks.length - 1, found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final first = chunks[mid].span(stream)?.firstOrdinal ?? 0;
      if (first <= ordinal) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// Copy ordinals [from, to) of [stream], channels [channels], into [dest]
  /// (one list per channel) starting at [destOffset]. Chunks decoded for
  /// one stream are kept in [scratch] for the next.
  Future<void> _readStream(
    int stream,
    int from,
    int to,
    List<int> channels,
    List<List<double>> dest,
    int destOffset,
    Map<int, ChunkData> scratch, {
    bool keep = true,
  }) async {
    var k = _chunkFor(stream, from);
    var o = from;
    while (o < to && k < chunkIndex.chunks.length) {
      final state = chunkIndex.chunks[k].span(stream);
      if (state == null || state.length == 0) {
        k++;
        continue;
      }
      final first = state.firstOrdinal;
      final end = first + state.length;
      if (end <= o) {
        k++;
        continue;
      }
      if (!keep) await _giveWay();
      final data = scratch[k] ??= await chunk(k, keep: keep);
      final cols = data.streams[stream];
      if (cols != null) {
        final a = math.max(o, first);
        final z = math.min(to, end);
        for (var j = 0; j < channels.length; j++) {
          final src = cols.channels[channels[j]];
          final d = dest[j];
          final base = destOffset + (a - from);
          for (var i = a; i < z; i++) {
            d[base + i - a] = src[i - first];
          }
        }
        o = z;
      }
      k++;
    }
  }

  // -- groups ---------------------------------------------------------------

  _Group _group(List<ChannelRef> channels) {
    if (channels.isEmpty) throw ArgumentError('No channels requested');
    double? rate;
    var t0 = double.infinity;
    final infos = <int, StreamTiming>{};
    for (final ch in channels) {
      final info = chunkIndex.stream(ch.stream);
      if (info == null) {
        throw ArgumentError('Stream ${ch.stream} has no samples');
      }
      if (!info.regular) {
        throw ArgumentError('Stream ${ch.stream} is irregular');
      }
      if (ch.channel < 0 || ch.channel >= info.channelCount) {
        throw RangeError.range(ch.channel, 0, info.channelCount - 1, 'channel');
      }
      final r = info.samplingRate.toDouble();
      if (rate != null && rate != r) {
        throw ArgumentError('Channels have different sampling rates');
      }
      rate = r;
      infos[ch.stream] = info;
      if (info.t0 < t0) t0 = info.t0;
    }
    var length = 0;
    final offsets = <int, int>{};
    for (final e in infos.entries) {
      final off = ((e.value.t0 - t0) * rate!).round();
      offsets[e.key] = off;
      length = math.max(length, off + e.value.length);
    }
    return _Group(channels, rate!, t0, length, offsets);
  }

  /// Samples [from, to) of the group, one list per channel, NaN where a
  /// stream has no data.
  Future<List<Float64List>> _readGroup(
    _Group g,
    int from,
    int to, {
    bool keep = true,
  }) async {
    final n = math.max(0, to - from);
    final out = [
      for (var i = 0; i < g.channels.length; i++)
        Float64List(n)..fillRange(0, n, double.nan),
    ];
    final byStream = <int, List<int>>{};
    for (var i = 0; i < g.channels.length; i++) {
      (byStream[g.channels[i].stream] ??= []).add(i);
    }
    // Streams share chunks: decode each once, even when not cached (keep).
    final scratch = <int, ChunkData>{};
    for (final e in byStream.entries) {
      final stream = e.key;
      final off = g.offsets[stream]!;
      final len = chunkIndex.stream(stream)!.length;
      final a = math.max(0, from - off);
      final z = math.min(len, to - off);
      if (a >= z) continue;
      await _readStream(
        stream,
        a,
        z,
        [for (final i in e.value) g.channels[i].channel],
        [for (final i in e.value) out[i]],
        a + off - from,
        scratch,
        keep: keep,
      );
    }
    return out;
  }

  /// Samples [from, to) of the group with [spec] applied, reading extra
  /// data on each side so filters settle. With [keep], filtered data comes
  /// from (and goes to) the tile cache, see [_filtered].
  Future<List<Float64List>> _derivedWindow(
    _Group g,
    int from,
    int to,
    DerivedSpec spec, {
    bool keep = true,
  }) async {
    if (spec.isIdentity) return _readGroup(g, from, to, keep: keep);
    final out = keep && spec.filters
        ? await _filtered(g, from, to, spec)
        : await _referencedAndFiltered(g, from, to, spec, keep: keep);
    final meanOf = spec.meanOf;
    if (meanOf != null) {
      final n = math.max(0, to - from);
      final mean = Float64List(n);
      for (var i = 0; i < n; i++) {
        var sum = 0.0;
        var count = 0;
        for (final c in meanOf) {
          final v = out[c][i];
          if (v.isNaN) continue;
          sum += v;
          count++;
        }
        mean[i] = count == 0 ? double.nan : sum / count;
      }
      out.add(mean);
    }
    return out;
  }

  /// The requested channels over [from, to), re-referenced and filtered as
  /// [spec] says (without its mean trace).
  Future<List<Float64List>> _referencedAndFiltered(
    _Group g,
    int from,
    int to,
    DerivedSpec spec, {
    bool keep = true,
  }) async {
    final pad = spec.padSamples(g.rate);
    final a = math.max(0, from - pad);
    final z = math.min(g.length, to + pad);
    final cols = await _readGroup(g, a, math.max(a, z), keep: keep);
    applyReference(cols, spec);
    if (spec.filters) {
      final sos = Sos.display(
        g.rate,
        highpass: spec.highpass,
        notch: spec.notch,
      );
      for (final col in cols) {
        var s = 0;
        while (s < col.length && col[s].isNaN) {
          s++;
        }
        var e = col.length;
        while (e > s && col[e - 1].isNaN) {
          e--;
        }
        if (e - s > 1) sos.filtfilt(Float64List.sublistView(col, s, e));
        if (!keep) await _giveWay();
      }
    }
    final n = math.max(0, to - from);
    final start = from - a;
    return [
      for (final col in cols) Float64List.sublistView(col, start, start + n),
    ];
  }

  /// Like [_referencedAndFiltered], stitched from filtered tiles of
  /// [_tileSize] ordinals that are kept between requests: scrolling a view
  /// re-uses them instead of filtering again. The neighbouring tiles are
  /// computed afterwards while nothing else is asked for.
  Future<List<Float64List>> _filtered(
    _Group g,
    int from,
    int to,
    DerivedSpec spec,
  ) async {
    final n = math.max(0, to - from);
    final out = [
      for (var i = 0; i < g.channels.length; i++)
        Float64List(n)..fillRange(0, n, double.nan),
    ];
    if (n == 0) return out;
    final first = from ~/ _tileSize, last = (to - 1) ~/ _tileSize;
    for (var t = first; t <= last; t++) {
      final tile = await _tile(g, spec, t);
      final base = t * _tileSize;
      final a = math.max(from, base);
      final z = math.min(to, base + _tileSize);
      for (var c = 0; c < out.length; c++) {
        final src = tile[c], dst = out[c];
        for (var i = a; i < z && i - base < src.length; i++) {
          dst[i - from] = src[i - base];
        }
      }
    }
    unawaited(_prefetch(g, spec, [first - 1, last + 1]));
    return out;
  }

  /// Filtered tile [t] of [g], from the cache or computed. Cached once its
  /// data (with the filters' padding) is all indexed.
  Future<List<Float32List>> _tile(_Group g, DerivedSpec spec, int t) {
    final key = '${g.key}|${spec.key}|$t';
    final cached = _tiles.remove(key);
    if (cached != null) {
      tileHits++;
      _tiles[key] = cached; // most recently used
      return Future.value(cached);
    }
    return _tilesPending[key] ??=
        () async {
          tileMisses++;
          final from = t * _tileSize;
          final to = math.min(g.length, from + _tileSize);
          final cols = await _referencedAndFiltered(g, from, to, spec);
          final tile = [for (final c in cols) Float32List.fromList(c)];
          final stable =
              chunkIndex.complete || to + spec.padSamples(g.rate) <= g.length;
          if (stable && !_closed) {
            _tiles[key] = tile;
            _tileBytes += tile.fold(0, (s, c) => s + c.lengthInBytes);
            while (_tileBytes > filteredCacheBytes && _tiles.length > 1) {
              final oldest = _tiles.keys.first;
              _tileBytes -= _tiles
                  .remove(oldest)!
                  .fold(0, (s, c) => s + c.lengthInBytes);
            }
          }
          return tile;
        }().whenComplete(() {
          // A block body, as in [chunk]: returning the removed future would
          // make this one wait for itself.
          _tilesPending.remove(key);
        });
  }

  /// In background work, every few milliseconds: let requests that came in
  /// (as isolate or worker messages) start, and wait until they are done.
  /// Otherwise each request waits for a whole block of the background work,
  /// and a viewer's requests pile up behind it.
  Future<void> _giveWay() async {
    if (_sinceGiveWay.elapsedMilliseconds < 8) return;
    await Future<void>.delayed(Duration.zero);
    while (_requests > 0 && !_closed) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    _sinceGiveWay.reset();
  }

  /// Compute [tiles] of [g] that are not cached yet, one at a time and only
  /// while no request is waiting.
  Future<void> _prefetch(_Group g, DerivedSpec spec, List<int> tiles) async {
    for (final t in tiles) {
      await Future<void>.delayed(Duration.zero);
      if (_closed || _requests > 0) return;
      if (t < 0 || t * _tileSize >= g.length) continue;
      if (_tiles.containsKey('${g.key}|${spec.key}|$t')) continue;
      await _tile(g, spec, t);
    }
  }

  // -- derived summaries ----------------------------------------------------

  /// The finished derived pyramid for [spec], or null while it is built.
  /// Building starts once the file is fully indexed.
  SummaryPyramid? _derivedPyramid(_Group g, DerivedSpec spec) {
    final key = '${g.key}|${spec.key}';
    final existing = _derived.remove(key);
    if (existing != null) {
      _derived[key] = existing; // most recently used
      return existing.done ? existing.pyramid : null;
    }
    if (!chunkIndex.complete) return null;
    for (final b in _derived.values) {
      if (!b.done) b.cancelled = true;
    }
    _derived.removeWhere((_, b) => b.cancelled);
    final outputs = g.channels.length + (spec.meanOf != null ? 1 : 0);
    final build = _DerivedBuild(key, g, spec, outputs);
    _derived[key] = build;
    final finished = _derived.values.where((b) => b.done).toList();
    for (var i = 0; i < finished.length - derivedCacheCount; i++) {
      _derived.remove(finished[i].key);
    }
    unawaited(_build(build));
    return null;
  }

  Future<void> _build(_DerivedBuild b) async {
    // Small blocks, so requests (served between blocks) do not wait long.
    const block = _tileSize;
    final total = b.group.length;
    for (var from = 0; from < total; from += block) {
      if (b.cancelled || _closed) return;
      final to = math.min(total, from + block);
      final cols = await _derivedWindow(b.group, from, to, b.spec, keep: false);
      b.pyramid.addColumns(cols, 0, to - from);
      if (!_derivedController.isClosed) {
        _derivedController.add(DerivedProgress(b.key, to / total, false));
      }
      await _giveWay();
    }
    if (b.cancelled || _closed) return;
    b.pyramid.finish();
    b.done = true;
    if (!_derivedController.isClosed) {
      _derivedController.add(DerivedProgress(b.key, 1, true));
    }
  }

  // -- requests -------------------------------------------------------------

  /// Full-resolution samples of some channels over a time range.
  Future<SignalWindow> read(ReadRequest r) async {
    _requests++;
    try {
      return await _read(r);
    } finally {
      _requests--;
    }
  }

  /// The shape of some channels over a time range, for drawing.
  Future<Envelope> envelope(EnvelopeRequest r) async {
    _requests++;
    try {
      return await _envelope(r);
    } finally {
      _requests--;
    }
  }

  Future<SignalWindow> _read(ReadRequest r) async {
    final g = _group(r.channels);
    // Samples whose time is within [t0, t1), allowing for rounding.
    final from = ((r.t0 - g.t0) * g.rate - 1e-6).ceil().clamp(0, g.length);
    final to = ((r.t1 - g.t0) * g.rate - 1e-6).ceil().clamp(from, g.length);
    final cols = await _derivedWindow(g, from, to, r.derived);
    return SignalWindow(g.t0 + from / g.rate, g.rate, [
      for (final c in cols) Float32List.fromList(c),
    ]);
  }

  Future<Envelope> _envelope(EnvelopeRequest r) async {
    final g = _group(r.channels);
    final spec = r.derived;
    final bins = math.max(1, r.bins);
    final outputs = g.channels.length + (spec.meanOf != null ? 1 : 0);
    final startF = (r.t0 - g.t0) * g.rate; // fractional group ordinal
    final span = math.max(0.0, (r.t1 - r.t0) * g.rate);
    final spb = span / bins;

    if (spb < SummaryPyramid.baseBucket) {
      final from = startF.floor().clamp(0, g.length);
      final to = ((r.t1 - g.t0) * g.rate).ceil().clamp(from, g.length);
      final cols = await _derivedWindow(g, from, to, spec);
      final stats = [for (final c in cols) _stats(c)];
      if (spb <= 2) {
        final values = [for (final c in cols) Float32List.fromList(c)];
        return Envelope(
          samples: true,
          start: g.t0 + from / g.rate,
          step: 1 / g.rate,
          min: values,
          max: values,
          stats: stats,
          samplingRate: g.rate,
        );
      }
      final mins = [for (var c = 0; c < outputs; c++) _nanList(bins)];
      final maxs = [for (var c = 0; c < outputs; c++) _nanList(bins)];
      final means = r.binStats
          ? [for (var c = 0; c < outputs; c++) _nanList(bins)]
          : null;
      final stds = r.binStats
          ? [for (var c = 0; c < outputs; c++) _nanList(bins)]
          : null;
      final acc = r.binStats ? SignalStats() : null;
      for (var c = 0; c < cols.length; c++) {
        final col = cols[c], mn = mins[c], mx = maxs[c];
        var current = -1;
        for (var i = 0; i < col.length; i++) {
          final v = col[i];
          if (v.isNaN) continue;
          final b = ((from + i - startF) / spb).floor();
          if (b < 0 || b >= bins) continue;
          final lo = mn[b];
          if (lo.isNaN || v < lo) mn[b] = v;
          final hi = mx[b];
          if (hi.isNaN || v > hi) mx[b] = v;
          if (acc != null) {
            if (b != current) {
              if (current >= 0) {
                means![c][current] = acc.mean;
                stds![c][current] = acc.std;
              }
              acc.clear();
              current = b;
            }
            acc.merge(v, v, v, 0, 1);
          }
        }
        if (acc != null && current >= 0) {
          means![c][current] = acc.mean;
          stds![c][current] = acc.std;
        }
      }
      return Envelope(
        samples: false,
        start: r.t0,
        step: (r.t1 - r.t0) / bins,
        min: mins,
        max: maxs,
        stats: stats,
        samplingRate: g.rate,
        binMean: means,
        binStd: stds,
      );
    }

    // Enough samples per bin to use a summary pyramid.
    SummaryPyramid? derived;
    var approximate = false;
    if (!spec.isIdentity) {
      derived = _derivedPyramid(g, spec);
      approximate = derived == null;
    }
    final mins = [for (var c = 0; c < outputs; c++) _nanList(bins)];
    final maxs = [for (var c = 0; c < outputs; c++) _nanList(bins)];
    final stats = [for (var c = 0; c < outputs; c++) SignalStats()];
    final range = Float64List(2);
    final means = r.binStats
        ? [for (var c = 0; c < outputs; c++) _nanList(bins)]
        : null;
    final stds = r.binStats
        ? [for (var c = 0; c < outputs; c++) _nanList(bins)]
        : null;
    final binStat = SignalStats();

    void fill(SummaryPyramid p, int pc, int oc, int offset) {
      var level = 0;
      while (level + 1 < p.levelCount &&
          SummaryPyramid.bucketSize(level + 1) <= spb) {
        level++;
      }
      final size = SummaryPyramid.bucketSize(level);
      final mn = mins[oc], mx = maxs[oc];
      for (var b = 0; b < bins; b++) {
        final a = startF + b * spb - offset;
        final z = a + spb;
        final ba = (a / size).floor();
        final bz = (z / size).ceil();
        if (p.range(level, pc, ba, bz, range)) {
          mn[b] = range[0];
          mx[b] = range[1];
        }
        if (means != null) {
          binStat.clear();
          p.reduce(level, pc, ba, bz, binStat);
          means[oc][b] = binStat.mean;
          stds![oc][b] = binStat.std;
        }
      }
      p.reduce(
        level,
        pc,
        ((startF - offset) / size).floor(),
        ((startF + span - offset) / size).ceil(),
        stats[oc],
      );
    }

    for (var c = 0; c < outputs; c++) {
      if (derived != null) {
        fill(derived, c, c, 0);
      } else if (c < g.channels.length) {
        final ch = g.channels[c];
        final p = chunkIndex.pyramid(ch.stream);
        if (p != null) fill(p, ch.channel, c, g.offsets[ch.stream]!);
      }
    }
    return Envelope(
      samples: false,
      start: r.t0,
      step: (r.t1 - r.t0) / bins,
      min: mins,
      max: maxs,
      stats: stats,
      samplingRate: g.rate,
      approximate: approximate,
      binMean: means,
      binStd: stds,
    );
  }

  static Float32List _nanList(int n) =>
      Float32List(n)..fillRange(0, n, double.nan);

  static SignalStats _stats(List<double> x) {
    var n = 0;
    var mn = double.infinity, mx = double.negativeInfinity;
    var shift = double.nan;
    var sum = 0.0, sumSq = 0.0;
    for (final v in x) {
      if (v.isNaN) continue;
      if (n == 0) shift = v;
      if (v < mn) mn = v;
      if (v > mx) mx = v;
      final d = v - shift;
      sum += d;
      sumSq += d * d;
      n++;
    }
    if (n == 0) return SignalStats();
    final m = sum / n;
    final variance = sumSq / n - m * m;
    return SignalStats(mn, mx, shift + m, math.sqrt(math.max(0, variance)), n);
  }
}
