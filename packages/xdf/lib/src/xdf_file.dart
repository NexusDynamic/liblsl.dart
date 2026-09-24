import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';
import 'package:xml/xml.dart';

import 'chunks.dart';
import 'format.dart';
import 'load.dart' show canDropSamples;
import 'stream_info.dart';
import 'sync.dart';

const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Settings for [XdfFile].
class XdfFileOptions {
  /// Bytes read from the file at a time while indexing.
  final int readBytes;

  /// Memory budget for decoded chunks.
  final int cacheBytes;

  /// Finished derived summaries (filtered views) to keep.
  final int derivedCacheCount;

  /// Memory budget for filtered data kept between requests.
  final int filteredCacheBytes;

  /// How long indexing runs before giving other work on its thread a turn.
  final Duration indexSlice;

  /// Clock synchronisation and dejittering (pyxdf's defaults).
  final XdfSyncOptions sync;

  const XdfFileOptions({
    this.readBytes = _isWeb ? 1 << 20 : 4 << 20,
    this.cacheBytes = _isWeb ? 256 << 20 : 512 << 20,
    this.derivedCacheCount = 4,
    this.filteredCacheBytes = _isWeb ? 32 << 20 : 64 << 20,
    this.indexSlice = _isWeb
        ? const Duration(milliseconds: 12)
        : const Duration(milliseconds: 50),
    this.sync = const XdfSyncOptions(),
  });
}

/// A run of samples of a regular stream with evenly spaced ordinals.
class _Segment {
  final int startIndex;
  int startOrdinal;

  /// First raw time stamp; the sums are relative to it (and to
  /// [startIndex]) for precision.
  final double t0;
  int count = 0;
  double si = 0, sii = 0, st = 0, sit = 0;

  _Segment(this.startIndex, this.startOrdinal, this.t0);

  void add(double t) {
    final j = count.toDouble();
    final d = t - t0;
    si += j;
    sii += j * j;
    st += d;
    sit += j * d;
    count++;
  }

  /// Least-squares line through the raw time stamps: time of the j-th
  /// sample is `t0 + c0 + c1·j`.
  (double, double) fit(double nominalRate) {
    if (count < 2) return (0, nominalRate > 0 ? 1 / nominalRate : 0);
    final det = count * sii - si * si;
    final c1 = (count * sit - si * st) / det;
    final c0 = (st - c1 * si) / count;
    return (c0, c1);
  }
}

/// Clock corrections of a stream, from its clock offsets so far.
class _Clock {
  final List<double> times = [];
  final List<double> values = [];
  List<XdfRange> _ranges = const [];
  List<XdfClockFit>? _fits;

  void add(double time, double value) {
    times.add(time);
    values.add(value);
    _fits = null;
  }

  bool _prepare(XdfSyncOptions o) {
    if (!o.synchronizeClocks || times.isEmpty) return false;
    if (_fits == null) {
      _ranges = o.handleClockResets && times.length > 1
          ? detectClockResets(times, values, o)
          : [(0, times.length - 1)];
      _fits = clockFits(times, values, _ranges, o);
    }
    return true;
  }

  /// A function that maps raw time stamps, given in order, to the
  /// recorder's clock. Like pyxdf, it moves on to the next clock range at
  /// the first time stamp closer to that range's first clock time than to
  /// the current one's last.
  double Function(double t) mapper(XdfSyncOptions o) {
    if (!_prepare(o)) return (t) => t;
    final fits = _fits!;
    final ranges = _ranges;
    var r = 0;
    return (t) {
      while (r + 1 < ranges.length &&
          !((t - times[ranges[r].$2]).abs() <
              (t - times[ranges[r + 1].$1]).abs())) {
        r++;
      }
      final (a, b) = fits[r];
      return t + a + b * t;
    };
  }
}

/// One stream of an [XdfFile]: its header, and how its samples map to
/// time.
class XdfStreamIndex implements StreamTiming {
  /// Its position among the file's streams; [ChannelRef.stream] of its
  /// channels.
  final int slot;

  /// Its id in the file.
  final int id;
  final XdfStreamInfo info;
  XdfStreamFooter? footer;

  final XdfSyncOptions _sync;
  final _Clock _clock = _Clock();

  // -- regular numeric streams ----------------------------------------------

  final List<_Segment> _segments = [];
  SummaryPyramid? _pyramid;
  int _ordinals = 0;
  double _lastRaw = 0;

  // Grid, from [_fitGrid]: absolute time of ordinal 0, and rate.
  double _gridT0 = 0;
  double _gridRate = 0;
  double _origin = 0;

  // -- irregular streams ------------------------------------------------------

  Float64List _times = Float64List(0);
  List<Float32List> _values = const [];
  List<List<String>>? _strings;

  /// Samples read so far.
  int sampleCount = 0;

  /// Gaps longer than this (seconds) start a new segment.
  late final double _breakAfter = math.max(
    _sync.jitterBreakSeconds,
    _sync.jitterBreakSamples / info.nominalRate,
  );

  /// Whether the stream is never split into segments (no dejittering, or
  /// it can drop samples).
  late final bool _oneSegment =
      !_sync.dejitterTimestamps || canDropSamples(info);

  XdfStreamIndex._(this.slot, this.id, this.info, this._sync) {
    if (regular) {
      _pyramid = SummaryPyramid(info.channelCount);
      _gridRate = info.nominalRate;
    } else {
      _times = Float64List(64);
      if (info.format.isString) {
        _strings = [for (var c = 0; c < info.channelCount; c++) <String>[]];
      }
      _values = [for (var c = 0; c < info.channelCount; c++) Float32List(64)];
    }
  }

  /// Whether samples are on an even grid (a numeric stream with a nominal
  /// rate). Others (markers, irregular streams) are kept in memory, see
  /// [XdfFile.events].
  @override
  bool get regular => info.regular && !info.format.isString;

  @override
  int get channelCount => info.channelCount;

  /// Samples per second of the grid: the effective rate (as pyxdf measures
  /// it), once known.
  @override
  num get samplingRate => regular ? _gridRate : 0;

  /// Time of the first sample, from the start of the recording.
  @override
  double get t0 => regular ? _gridT0 - _origin : _firstTime - _origin;

  /// Ordinals on the grid (samples, and gaps between segments).
  @override
  int get length => regular ? _ordinals : sampleCount;

  /// Time just after the last sample, from the start of the recording.
  double get t1 {
    if (regular) return t0 + (_gridRate > 0 ? _ordinals / _gridRate : 0);
    return sampleCount == 0 ? t0 : _synced()[sampleCount - 1] - _origin;
  }

  /// Clock offsets so far.
  List<XdfClockOffset> get clockOffsets => [
    for (var i = 0; i < _clock.times.length; i++)
      XdfClockOffset(_clock.times[i], _clock.values[i]),
  ];

  /// Segments between breaks so far (regular streams), as ranges of
  /// sample indices.
  List<XdfRange> get segments => [
    for (final s in _segments) (s.startIndex, s.startIndex + s.count - 1),
  ];

  double get _firstTime {
    if (regular) return _gridT0;
    return sampleCount == 0 ? 0 : _synced()[0];
  }

  Float64List? _syncedCache;
  int _syncedCount = -1;
  int _syncedOffsets = -1;

  /// The recorder's times of the samples of an irregular stream.
  Float64List _synced() {
    final n = sampleCount;
    if (_syncedCache == null ||
        _syncedCount != n ||
        _syncedOffsets != _clock.times.length) {
      final sync = _clock.mapper(_sync);
      _syncedCache = Float64List(n);
      for (var i = 0; i < n; i++) {
        _syncedCache![i] = sync(_times[i]);
      }
      _syncedCount = n;
      _syncedOffsets = _clock.times.length;
    }
    return _syncedCache!;
  }

  /// The ordinal of sample [index] (regular streams).
  int ordinalOf(int index) {
    var lo = 0, hi = _segments.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_segments[mid].startIndex <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final s = _segments[lo];
    return s.startOrdinal + index - s.startIndex;
  }

  /// Samples per second measured so far, for spacing a break.
  double _rateSoFar() {
    var count = 0.0, duration = 0.0;
    for (final s in _segments) {
      if (s.count < 2) continue;
      final (_, c1) = s.fit(info.nominalRate);
      count += s.count - 1;
      duration += c1 * (s.count - 1);
    }
    return count > 0 && duration > 0 ? count / duration : info.nominalRate;
  }

  /// Place the next sample, with raw time stamp [t]; returns its ordinal.
  int _place(double t) {
    final index = sampleCount++;
    if (_segments.isEmpty) {
      _segments.add(_Segment(index, 0, t)..add(t));
      _lastRaw = t;
      _ordinals = 1;
      return 0;
    }
    final dt = t - _lastRaw;
    _lastRaw = t;
    final breaks = !_oneSegment && dt.abs() > _breakAfter;
    if (breaks) {
      final step = math.max(1, (dt * _rateSoFar()).round());
      final ordinal = _ordinals - 1 + step;
      _segments.add(_Segment(index, ordinal, t)..add(t));
      _ordinals = ordinal + 1;
      return ordinal;
    }
    _segments.last.add(t);
    return _ordinals++;
  }

  void _addIrregular(
    double t,
    List<double>? values,
    int offset, [
    List<String>? text,
  ]) {
    final n = sampleCount;
    if (n == _times.length) {
      _times = Float64List(n * 2)..setRange(0, n, _times);
      _values = [
        for (final v in _values) Float32List(n * 2)..setRange(0, n, v),
      ];
    }
    _times[n] = t;
    for (var c = 0; c < _values.length; c++) {
      if (text != null) {
        _strings![c].add(text[offset + c]);
        _values[c][n] = double.tryParse(text[offset + c]) ?? double.nan;
      } else {
        _values[c][n] = values![offset + c];
      }
    }
    sampleCount = n + 1;
  }

  /// Fit the grid to the samples so far: the effective rate, and the
  /// recorder's time of the first sample.
  void _fitGrid() {
    if (!regular || _segments.isEmpty) return;
    final r = info.nominalRate;
    final sync = _clock.mapper(_sync);
    var count = 0.0, duration = 0.0;
    for (final (k, s) in _segments.indexed) {
      final (c0, c1) = _sync.dejitterTimestamps ? s.fit(r) : (0.0, 0.0);
      final a = sync(s.t0 + c0);
      if (k == 0) _gridT0 = a;
      if (s.count < 2) continue;
      final z = sync(s.t0 + c0 + c1 * (s.count - 1));
      count += s.count - 1;
      duration += z - a;
    }
    _gridRate = count > 0 && duration > 0 ? count / duration : r;
  }

  @override
  String toString() =>
      'XdfStreamIndex($slot: ${info.name}, $sampleCount samples)';
}

/// A samples chunk of a regular stream, decodable on its own.
class XdfSampleChunk implements SignalChunk {
  final XdfIndexer _index;
  final int index;
  @override
  final int offset;
  @override
  final int length;

  /// The stream (its slot).
  final int slot;

  /// Index of its first sample in the stream, and its number of samples.
  final int firstIndex;
  final int count;

  /// Ordinal of its first sample.
  int get firstOrdinal => _own.firstOrdinal;

  /// Ordinals it covers (samples, and a gap before a break in it).
  int get ordinals => _own.length;

  _Span _own;

  XdfSampleChunk._(
    this._index,
    this.index,
    this.offset,
    this.length,
    this.slot,
    this.firstIndex,
    this.count,
    int firstOrdinal,
    int ordinals,
  ) : _own = _Span(firstOrdinal, ordinals);

  @override
  StreamChunkSpan? span(int stream) =>
      stream == slot ? _own : _index._cursor(stream, index);
}

class _Span implements StreamChunkSpan {
  @override
  final int firstOrdinal;
  @override
  final int length;
  const _Span(this.firstOrdinal, this.length);
}

/// Indexes an XDF file in one sequential pass, for [XdfFile]: stream
/// headers, clock offsets, footers, a summary pyramid per regular stream
/// and where each samples chunk is; irregular streams are kept in memory.
class XdfIndexer implements ChunkedSignalIndex {
  final ByteSource source;
  final XdfFileOptions options;

  XmlElement? header;
  final List<XdfStreamIndex> streams = [];
  final Map<int, XdfStreamIndex> _byId = {};

  @override
  final List<XdfSampleChunk> chunks = [];

  /// Chunk indices of each regular stream.
  final Map<int, List<int>> _chunksOf = {};

  bool _complete = false;
  int indexedBytes = 0;

  XdfIndexer(this.source, this.options);

  @override
  bool get complete => _complete;

  double get progress =>
      source.length == 0 ? 1 : math.min(1, indexedBytes / source.length);

  @override
  XdfStreamIndex? stream(int stream) =>
      stream >= 0 && stream < streams.length ? streams[stream] : null;

  @override
  SummaryPyramid? pyramid(int stream) => this.stream(stream)?._pyramid;

  /// Where regular [slot] is at chunk [chunk]: the first ordinal of its
  /// next chunk, or its end.
  StreamChunkSpan? _cursor(int slot, int chunk) {
    final list = _chunksOf[slot];
    if (list == null) return null;
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] < chunk) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // Where another stream is at a chunk: no samples, at its next one.
    return _Span(
      lo < list.length ? chunks[list[lo]].firstOrdinal : streams[slot].length,
      0,
    );
  }

  /// Start of the recording: the recorder's time of the earliest first
  /// sample.
  double origin = 0;

  /// Recompute clock corrections and grids from what was read so far.
  void refreshTiming() {
    var o = double.infinity;
    for (final s in streams) {
      s._fitGrid();
      if (s.sampleCount > 0) o = math.min(o, s._firstTime);
    }
    origin = o.isFinite ? o : 0;
    for (final s in streams) {
      s._origin = origin;
    }
  }

  /// Duration from the start of the recording to its last sample.
  double get duration {
    var end = 0.0;
    for (final s in streams) {
      if (s.sampleCount > 0) end = math.max(end, s.t1);
    }
    return end;
  }

  /// Index the file; [onProgress] is called after each read.
  Future<void> run({
    void Function()? onProgress,
    bool Function()? cancelled,
  }) async {
    final head = await source.read(0, 4);
    if (!isXdf(head)) throw const FormatException('Not an XDF file');
    var pos = 4;
    var buffer = Uint8List(0);
    var bufferStart = 4;
    final slice = Stopwatch()..start();
    while (pos < source.length) {
      if (cancelled?.call() ?? false) return;
      final rel = pos - bufferStart;
      var h = readChunkHeader(buffer, rel);
      if (h == null || h.contentOffset + h.contentLength > buffer.length) {
        // Refill from this chunk on, with room for all of it (its header
        // first, if that was cut off too).
        var need = h == null ? 16 : h.contentOffset - rel + h.contentLength;
        while (true) {
          final size = math.min(
            source.length - pos,
            math.max(need, options.readBytes),
          );
          buffer = await source.read(pos, size);
          bufferStart = pos;
          h = readChunkHeader(buffer, 0);
          if (h == null) break;
          final end = h.contentOffset + h.contentLength;
          if (end <= buffer.length || size == source.length - pos) break;
          need = end;
        }
        if (h == null || h.contentOffset + h.contentLength > buffer.length) {
          break; // a truncated last chunk
        }
      }
      final content = Uint8List.sublistView(
        buffer,
        h.contentOffset,
        h.contentOffset + h.contentLength,
      );
      try {
        _chunk(h.tag, bufferStart + h.contentOffset, content);
      } on FormatException {
        // A damaged chunk: skip it.
      }
      pos = bufferStart + h.contentOffset + h.contentLength;
      indexedBytes = pos;
      if (slice.elapsed >= options.indexSlice) {
        refreshTiming();
        onProgress?.call();
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
    }
    indexedBytes = source.length;
    refreshTiming();
    for (final s in streams) {
      if (cancelled?.call() ?? false) return;
      await _remap(s, cancelled);
    }
    for (final s in streams) {
      s._pyramid?.finish();
    }
    refreshTiming();
    _complete = true;
    onProgress?.call();
  }

  /// Place the segments of regular stream [s] by their synchronised start
  /// times (while indexing, a break was spaced by the raw time stamps,
  /// which a clock reset makes wrong), and rebuild its pyramid if that
  /// moved any.
  Future<void> _remap(XdfStreamIndex s, bool Function()? cancelled) async {
    if (!s.regular || s._segments.length < 2 || s._gridRate <= 0) return;
    final sync = s._clock.mapper(options.sync);
    final r = s.info.nominalRate;
    var moved = false;
    var end = 0;
    for (final seg in s._segments) {
      final (c0, _) = options.sync.dejitterTimestamps ? seg.fit(r) : (0.0, 0.0);
      final ideal = ((sync(seg.t0 + c0) - s._gridT0) * s._gridRate).round();
      final o = math.max(end, ideal);
      if (o != seg.startOrdinal) {
        seg.startOrdinal = o;
        moved = true;
      }
      end = o + seg.count;
    }
    if (!moved) return;
    s._ordinals = end;
    final list = _chunksOf[s.slot] ?? const <int>[];
    for (final k in list) {
      final c = chunks[k];
      final first = s.ordinalOf(c.firstIndex);
      c._own = _Span(
        first,
        s.ordinalOf(c.firstIndex + c.count - 1) + 1 - first,
      );
    }
    // Rebuild the pyramid from the chunks, in the new places.
    final ch = s.channelCount;
    final pyramid = SummaryPyramid(ch);
    final nan = Float64List(ch)..fillRange(0, ch, double.nan);
    final row = Float64List(ch);
    final slice = Stopwatch()..start();
    for (final k in list) {
      if (cancelled?.call() ?? false) return;
      final c = chunks[k];
      final data = decodeChunk(c, await source.read(c.offset, c.length));
      final cols = data.streams[s.slot]!.channels;
      while (pyramid.length < c.firstOrdinal) {
        pyramid.add(nan);
      }
      for (var i = 0; i < c.ordinals; i++) {
        for (var j = 0; j < ch; j++) {
          row[j] = cols[j][i];
        }
        pyramid.add(row);
      }
      if (slice.elapsed >= options.indexSlice) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
    }
    s._pyramid = pyramid;
  }

  void _chunk(int tag, int offset, Uint8List content) {
    final kind = XdfTag.of(tag);
    if (kind == XdfTag.fileHeader) {
      final doc = XmlDocument.parse(utf8.decode(content, allowMalformed: true));
      header = doc.getElement('info') ?? doc.rootElement;
      return;
    }
    if (kind == null || kind == XdfTag.boundary) return;
    if (content.length < 4) throw const FormatException('Short chunk');
    final id = ByteData.sublistView(content).getUint32(0, Endian.little);
    final body = Uint8List.sublistView(content, 4);
    switch (kind) {
      case XdfTag.streamHeader:
        if (_byId.containsKey(id)) return;
        final s = XdfStreamIndex._(
          streams.length,
          id,
          XdfStreamInfo.parse(utf8.decode(body, allowMalformed: true)),
          options.sync,
        );
        streams.add(s);
        _byId[id] = s;
      case XdfTag.samples:
        final s = _byId[id];
        if (s == null) return;
        _samples(s, offset, content);
      case XdfTag.clockOffset:
        final s = _byId[id];
        if (s == null) return;
        final d = ByteData.sublistView(body);
        s._clock.add(
          d.getFloat64(0, Endian.little),
          d.getFloat64(8, Endian.little),
        );
      case XdfTag.streamFooter:
        final s = _byId[id];
        if (s == null) return;
        try {
          s.footer = XdfStreamFooter.parse(
            utf8.decode(body, allowMalformed: true),
          );
        } on XmlException {
          // A damaged footer: ignore it.
        }
      case XdfTag.fileHeader || XdfTag.boundary:
        break;
    }
  }

  void _samples(XdfStreamIndex s, int offset, Uint8List content) {
    final info = s.info;
    final samples = readSamples(content, info.format, info.channelCount);
    final ts = samples.timestamps;
    final previous = s.regular
        ? s._lastRaw
        : (s.sampleCount == 0 ? 0.0 : s._times[s.sampleCount - 1]);
    fillTimestamps(ts, s.sampleCount == 0 ? 0 : previous, info.nominalRate);
    final ch = info.channelCount;
    if (!s.regular) {
      for (var i = 0; i < samples.length; i++) {
        s._addIrregular(ts[i], samples.values, i * ch, samples.strings);
      }
      return;
    }
    if (samples.length == 0) return;
    final firstIndex = s.sampleCount;
    final pyramid = s._pyramid!;
    final values = samples.values!;
    final row = Float64List(ch);
    final nan = Float64List(ch)..fillRange(0, ch, double.nan);
    var firstOrdinal = -1;
    for (var i = 0; i < samples.length; i++) {
      final ordinal = s._place(ts[i]);
      if (firstOrdinal < 0) firstOrdinal = ordinal;
      while (pyramid.length < ordinal) {
        pyramid.add(nan);
      }
      for (var c = 0; c < ch; c++) {
        row[c] = values[i * ch + c];
      }
      pyramid.add(row);
    }
    final chunk = XdfSampleChunk._(
      this,
      chunks.length,
      offset,
      content.length,
      s.slot,
      firstIndex,
      samples.length,
      firstOrdinal,
      s._ordinals - firstOrdinal,
    );
    (_chunksOf[s.slot] ??= []).add(chunks.length);
    chunks.add(chunk);
  }

  @override
  ChunkData decodeChunk(XdfSampleChunk chunk, Uint8List bytes) {
    final s = streams[chunk.slot];
    final ch = s.channelCount;
    final samples = readSamples(bytes, s.info.format, ch);
    final n = chunk.ordinals;
    final cols = [
      for (var c = 0; c < ch; c++) Float32List(n)..fillRange(0, n, double.nan),
    ];
    final values = samples.values!;
    for (var i = 0; i < samples.length; i++) {
      final o = s.ordinalOf(chunk.firstIndex + i) - chunk.firstOrdinal;
      if (o < 0 || o >= n) continue;
      for (var c = 0; c < ch; c++) {
        cols[c][o] = values[i * ch + c];
      }
    }
    return ChunkData(chunk.index, [
      for (var k = 0; k < streams.length; k++)
        k == chunk.slot ? StreamColumns(chunk.firstOrdinal, cols) : null,
    ]);
  }
}

/// Samples of an irregular stream (e.g. markers), in memory.
class XdfEvents {
  /// Times from the start of the recording.
  final Float64List times;

  /// Values per channel; NaN for strings that are not numbers.
  final List<Float32List> channels;

  /// Strings per channel, for string streams.
  final List<List<String>>? strings;

  const XdfEvents(this.times, this.channels, this.strings);

  int get length => times.length;
}

/// Random access to a large XDF recording without loading it into memory.
///
/// Opening a file indexes it in one sequential pass: stream headers, clock
/// offsets, a summary pyramid per regular stream, and where each samples
/// chunk is. Views of regular streams are answered from the pyramids or by
/// decoding the chunks they cover ([envelope], [read]); irregular streams
/// (markers) are kept in memory ([events]).
///
/// Time stamps are synchronised and dejittered as pyxdf does by default
/// ([XdfFileOptions.sync]); each regular stream is placed on an even grid
/// at its effective rate, from the recorder's time of its first sample.
/// Times are from the start of the recording ([origin]).
///
/// A stream without breaks gets exactly pyxdf's time stamps. After a break
/// (a gap, or a clock reset), a segment starts where pyxdf puts it (within
/// a sample), but drifts within the segment if its rate differs from the
/// stream's overall effective rate; [loadXdf] has exact time stamps.
class XdfFile extends ChunkedSignalEngine {
  final XdfFileOptions options;
  final XdfIndexer _indexer;
  final _progress = StreamController<void>.broadcast();
  final _indexed = Completer<void>();
  final _firstRead = Completer<void>();
  final Stopwatch _sinceUpdate = Stopwatch()..start();

  XdfFile._(super.source, this.options)
    : _indexer = XdfIndexer(source, options),
      super(
        cacheBytes: options.cacheBytes,
        derivedCacheCount: options.derivedCacheCount,
        filteredCacheBytes: options.filteredCacheBytes,
      );

  /// Open [source] and index it on the current isolate. Returns once the
  /// first part is read (the stream headers, normally).
  static Future<XdfFile> open(
    ByteSource source, {
    XdfFileOptions options = const XdfFileOptions(),
  }) async {
    final file = XdfFile._(source, options);
    unawaited(file._run());
    await file._firstRead.future;
    return file;
  }

  Future<void> _run() async {
    try {
      await _indexer.run(onProgress: _onProgress, cancelled: () => isClosed);
      if (isClosed) return;
      if (!_firstRead.isCompleted) _firstRead.complete();
      _indexed.complete();
      if (!_progress.isClosed) _progress.add(null);
    } catch (e, s) {
      if (!_firstRead.isCompleted) _firstRead.completeError(e, s);
      if (!_indexed.isCompleted) _indexed.completeError(e, s);
      if (!_progress.isClosed) _progress.addError(e, s);
    }
  }

  void _onProgress() {
    if (!_firstRead.isCompleted) _firstRead.complete();
    if (_sinceUpdate.elapsedMilliseconds >= 200 && !_progress.isClosed) {
      _progress.add(null);
      _sinceUpdate.reset();
    }
  }

  /// The indexer, for tests and tools.
  XdfIndexer get indexer => _indexer;

  @override
  ChunkedSignalIndex get chunkIndex => _indexer;

  /// Fires while indexing runs, and when it is done.
  Stream<void> get onIndex => _progress.stream;

  /// Completes once the whole file is indexed.
  Future<void> get indexed => _indexed.future;

  bool get complete => _indexer.complete;

  /// Indexing progress, 0-1.
  double get progress => _indexer.progress;

  /// The file header's `info` element.
  XmlElement? get header => _indexer.header;

  /// The streams, in the order of their headers; a stream's position is
  /// its [XdfStreamIndex.slot].
  List<XdfStreamIndex> get streams => _indexer.streams;

  /// The recorder's LSL time of time 0.
  double get origin => _indexer.origin;

  /// Seconds from the first to the last sample of any stream.
  double get duration => _indexer.duration;

  /// The samples of irregular stream [slot] so far.
  XdfEvents events(int slot) {
    final s = _indexer.streams[slot];
    if (s.regular) throw ArgumentError('Stream $slot is regular');
    final n = s.sampleCount;
    final synced = s._synced();
    final times = Float64List(n);
    for (var i = 0; i < n; i++) {
      times[i] = synced[i] - s._origin;
    }
    return XdfEvents(
      times,
      [for (final v in s._values) Float32List.sublistView(v, 0, n)],
      s._strings == null
          ? null
          : [for (final t in s._strings!) List.unmodifiable(t.sublist(0, n))],
    );
  }

  @override
  Future<Envelope> envelope(EnvelopeRequest r) {
    _check(r.channels);
    return super.envelope(r);
  }

  @override
  Future<SignalWindow> read(ReadRequest r) {
    _check(r.channels);
    return super.read(r);
  }

  void _check(List<ChannelRef> channels) {
    for (final c in channels) {
      final s = _indexer.stream(c.stream);
      if (s == null || !s.regular) {
        throw ArgumentError('Stream ${c.stream} is not a regular stream');
      }
    }
  }

  Future<void> close() async {
    if (isClosed) return;
    await closeEngine();
    await source.close();
    await _progress.close();
  }
}
