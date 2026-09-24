import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:signal_viewer/signal_viewer.dart';

import 'lsl.dart';

/// A stream received over LSL, shown in one tab.
///
/// Time 0 is the first sample; with clock sync (the default) all streams
/// are on this computer's clock, and share time 0 so that their tabs line
/// up. A regular stream is kept on the grid of its
/// nominal rate, like the device's ports: samples are placed one after the
/// other, and a gap in the time stamps (e.g. samples lost on the network)
/// is filled by interpolation. String streams are markers: a tick with the
/// text at each sample.
class LslSession extends SourceSession implements LiveData {
  final LslInlet inlet;
  final LslInletOptions options;
  late final StreamInfo info = _info(inlet);

  RegularRing? _ring;
  IrregularLog? _log;
  final _changes = Changes();

  /// LSL time of time 0.
  double? _origin;

  /// Time 0 of the clock-synced sessions, while any is open.
  static double? _sharedOrigin;
  static int _openCount = 0;

  /// LSL time of the ring's ordinal 0, adjusted when the sender runs fast.
  double _anchor = 0;

  /// LSL clock when the last sample arrived, and its time.
  double _arrived = 0;
  double _lastT = 0;
  int received = 0;

  /// First and last time stamps received (LSL time), for [measuredRate].
  double? _firstStamp;
  double _lastStamp = 0;

  /// Intervals between time stamps: count, mean and variance (Welford),
  /// the largest, and how many went backwards.
  int _intervals = 0;
  double _intervalMean = 0, _intervalM2 = 0, _intervalMax = 0;
  int backwards = 0;

  bool _closed = false;
  bool _idle = false;
  String? error;
  Timer? _statusTimer;

  /// The receiving loop, which [close] waits for before freeing the inlet.
  late final Future<void> _loop;

  LslSession._(this.inlet, this.options) {
    _openCount++;
    if (info.irregular && options.clockSync) {
      // Irregular streams scroll with the clock from the start.
      _origin = _sharedOrigin ??= lsl.clock();
    }
    if (info.irregular) {
      _log = IrregularLog(
        info.channelCount,
        keepS: 2 * liveBufferS,
        strings: inlet.stream.format.isString,
      );
    } else {
      _ring = RegularRing(info.channelCount, info.rate);
    }
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final idle = received == 0 || lsl.clock() - _arrived > _idleAfter;
      if (idle != _idle) {
        _idle = idle;
        notifyListeners();
      }
    });
    _loop = _run();
  }

  static Future<LslSession> open(
    LslStreamDescription stream,
    LslInletOptions options,
  ) async => LslSession._(await lsl.openInlet(stream, options), options);

  static StreamInfo _info(LslInlet inlet) {
    final s = inlet.stream;
    final n = s.channelCount;
    return StreamInfo(
      key: s.key,
      name: s.name,
      type: s.type,
      kind: s.format.isString ? Kind.event : kindFromType(s.type),
      rate: s.format.isString ? 0 : s.rate,
      labels: [for (final c in inlet.channels) c.label],
      units: [for (final c in inlet.channels) c.unit],
      channels: [for (var c = 0; c < n; c++) ChannelRef(0, c)],
    );
  }

  String get key => info.key;

  @override
  bool get closed => _closed;

  @override
  List<StreamInfo> get streams => [info];

  @override
  String get label => 'LSL';

  @override
  String get titleSuffix => error != null ? ' (error)' : '';

  @override
  String get tooltip => describe();

  @override
  bool get groupable => false;

  @override
  String get rememberKey => key;

  @override
  bool decodable(StreamInfo info) => !inlet.stream.format.isString;

  @override
  StreamSource sourceFor(StreamInfo info) => LiveStreamSource(this, info);

  /// No data for a while (the sender stopped or is gone).
  bool get idle => _idle;

  double get _idleAfter =>
      info.rate > 0 ? math.max(2, 20 / info.rate) : double.infinity;

  int get lostSampleCount => _ring?.lost ?? 0;

  /// Standard deviation of the intervals between time stamps, in seconds
  /// (null until there are two intervals): the jitter.
  double? get intervalStd =>
      _intervals < 2 ? null : math.sqrt(_intervalM2 / (_intervals - 1));

  /// The largest interval between time stamps, in seconds.
  double? get largestInterval => _intervals == 0 ? null : _intervalMax;

  /// Samples per second from the time stamps received so far (null until
  /// there are two).
  double? get measuredRate {
    final first = _firstStamp;
    if (first == null || received < 2 || _lastStamp <= first) return null;
    return (received - 1) / (_lastStamp - first);
  }

  @override
  String describe() => [
    'LSL ${inlet.stream.name}',
    inlet.stream.summary,
    if (lostSampleCount > 0) '$lostSampleCount lost',
    if (error != null)
      'error: $error'
    else if (received == 0)
      'waiting for data'
    else if (_idle)
      'no data',
  ].join(' · ');

  // -- receiving -------------------------------------------------------------

  Future<void> _run() async {
    final interval = Duration(milliseconds: options.pullIntervalMs);
    // Room for a few intervals, so one pull usually gets everything.
    final max = math.max(
      64,
      (math.max(info.rate, 1) * options.pullIntervalMs / 1000 * 8).ceil(),
    );
    var lastPing = 0.0;
    while (!_closed) {
      try {
        var got = false;
        while (!_closed) {
          final c = await inlet.pull(max);
          if (c.length == 0 || _closed) break;
          _ingest(c);
          got = true;
          if (c.length < max) break;
        }
        final now = lsl.clock();
        // Marker streams scroll with time even without new samples.
        if (got || (info.irregular && received > 0 && now - lastPing > 0.05)) {
          lastPing = now;
          _changes.ping();
        }
      } catch (e) {
        if (_closed) return;
        error = '$e';
        notifyListeners();
        return;
      }
      await Future<void>.delayed(interval);
    }
  }

  void _ingest(LslChunk c) {
    final now = lsl.clock();
    final times = c.times;
    final n = info.channelCount;
    _origin ??= options.clockSync
        ? (_sharedOrigin ??= times.first)
        : times.first;
    final origin = _origin!;
    final ring = _ring;
    if (ring != null) {
      final values = c.values!;
      final rate = info.rate;
      // A gap longer than this is filled; shorter jitter is not.
      final tolerance = math.max(2, (rate * 0.05).ceil());
      for (var i = 0; i < c.length; i++) {
        final ts = times[i];
        if (ring.written == 0) {
          _anchor = ts;
          ring.t0 = ts - origin;
        } else {
          final gap = ((ts - _anchor) * rate).round() - ring.written;
          if (gap > tolerance) {
            ring.fill(gap, values, i * n);
          } else if (gap < -tolerance) {
            // The sender's clock runs faster than its nominal rate.
            _anchor = ts - ring.written / rate;
          }
        }
        ring.add(values, i * n);
      }
    } else {
      final log = _log!;
      final text = c.strings;
      final row = List<double>.filled(n, 0);
      for (var i = 0; i < c.length; i++) {
        if (text != null) {
          for (var ch = 0; ch < n; ch++) {
            row[ch] = double.tryParse(text[i * n + ch]) ?? double.nan;
          }
          log.add(times[i] - origin, row, 0, text.sublist(i * n, i * n + n));
        } else {
          log.add(times[i] - origin, c.values!, i * n);
        }
      }
    }
    for (var i = 0; i < c.length; i++) {
      final t = times[i];
      if (received + i > 0) {
        final prev = i == 0 ? _lastStamp : times[i - 1];
        final d = t - prev;
        if (d < 0) backwards++;
        _intervals++;
        final delta = d - _intervalMean;
        _intervalMean += delta / _intervals;
        _intervalM2 += delta * (d - _intervalMean);
        if (d > _intervalMax) _intervalMax = d;
      }
    }
    received += c.length;
    _firstStamp ??= times.first;
    _lastStamp = times.last;
    _lastT = times.last - origin;
    _arrived = now;
    if (_idle) {
      _idle = false;
      notifyListeners();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (--_openCount == 0) _sharedOrigin = null;
    _statusTimer?.cancel();
    await _loop;
    await inlet.close();
    notifyListeners();
  }

  // -- LiveData ----------------------------------------------------------------

  @override
  Listenable get changes => _changes;

  @override
  double get now {
    final ring = _ring;
    if (ring != null) return ring.written == 0 ? 0 : ring.end;
    final origin = _origin;
    if (options.clockSync && origin != null) return lsl.clock() - origin;
    if (received == 0) return 0;
    // Irregular: time goes on between samples.
    return _lastT + math.max(0, lsl.clock() - _arrived);
  }

  @override
  List<Float64List>? columnsAt(
    List<ChannelRef> refs,
    double rate,
    int from,
    int to,
  ) => _ring == null ? null : ringColumns({0: _ring!}, refs, rate, from, to);

  @override
  (int, int)? tickRange(List<ChannelRef> refs, double rate) =>
      _ring == null ? null : ringTickRange({0: _ring!}, refs, rate);

  @override
  EventSamples events(int port) =>
      _log?.events(markers: _log!.strings) ?? EventSamples.empty;
}
