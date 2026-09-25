import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:signal_viewer/signal_viewer.dart';

import 'package:lsl_tools/lsl_tools.dart';
import 'lsl_forward.dart';

class _Replayed {
  final StreamInfo info;
  final StreamSource source;
  final LslOutlet outlet;

  /// Recording time up to which samples were pushed.
  double pushed;

  /// Samples read ahead: start time and columns.
  SignalWindow? ahead;

  /// Irregular: index of the next event to push.
  int nextEvent = 0;
  bool reading = false;

  _Replayed(this.info, this.source, this.outlet, this.pushed);
}

/// Plays a recording ([SourceSession.replayable]) over LSL in real time: an
/// outlet per stream, named as in the recording, whose samples are stamped
/// with the time they are sent. The outlets are made here, or on a bridge's
/// computer when given its [LslBridgeClient.publish] as the outlet factory.
class LslReplay extends ChangeNotifier {
  final SourceSession session;
  final List<_Replayed> _streams;
  final double from;
  final double end;
  final bool loop;

  /// LSL clock when recording time [from] was sent.
  double _startClock;
  bool _closed = false;
  bool finished = false;
  Timer? _timer;
  DateTime _lastNotify = DateTime.now();

  /// Samples sent so far, over all streams.
  int sent = 0;

  /// Seconds read ahead at a time.
  static const blockS = 2.0;

  LslReplay._(this.session, this._streams, this.from, this.end, this.loop)
    : _startClock = lsl.clock() {
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }

  /// Start replaying [session] from [from] seconds: all its streams, or
  /// only [only], each named as recorded or as [name] gives. Outlets are
  /// made with [create] (default: LSL here).
  static Future<LslReplay> start(
    SourceSession session, {
    double from = 0,
    bool loop = false,
    LslOutletOptions options = const LslOutletOptions(),
    List<StreamInfo>? only,
    String Function(StreamInfo info)? name,
    OutletFactory? create,
  }) async {
    create ??= (spec) => lsl.createOutlet(spec, options);
    final streams = <_Replayed>[];
    var end = 0.0;
    try {
      for (final info in only ?? session.streams) {
        final source = session.sourceFor(info);
        end = math.max(end, source.end);
        final strings = info.irregular && source.events().text != null;
        final outlet = await create(
          LslOutletSpec(
            name: name?.call(info) ?? info.name,
            type: info.type.isEmpty ? info.kind.label : info.type,
            // String outlets carry one channel (the first).
            channelCount: strings ? 1 : info.channelCount,
            rate: info.irregular ? 0 : info.rate,
            format: strings ? LslFormat.string : LslFormat.float32,
            sourceId: 'replay:${info.key}',
            channels: [
              for (var c = 0; c < (strings ? 1 : info.channelCount); c++)
                LslChannel(info.labels[c], unit: info.unit(c)),
            ],
            desc: {
              'acquisition': {'replay_of': session.label},
            },
          ),
        );
        final r = _Replayed(info, source, outlet, from);
        if (info.irregular) {
          final e = source.events();
          while (r.nextEvent < e.length && e.times[r.nextEvent] < from) {
            r.nextEvent++;
          }
        }
        streams.add(r);
      }
    } catch (_) {
      for (final s in streams) {
        await s.outlet.close();
      }
      rethrow;
    }
    return LslReplay._(session, streams, from, end, loop);
  }

  int get streamCount => _streams.length;

  /// Recording time being sent now.
  double get position => math.min(end, from + (lsl.clock() - _startClock));

  void _tick() {
    if (_closed || finished) return;
    final target = from + (lsl.clock() - _startClock);
    for (final s in _streams) {
      if (s.info.irregular) {
        _pushEvents(s, target);
      } else {
        _pushRegular(s, target);
      }
    }
    if (target >= end) {
      if (loop) {
        _startClock = lsl.clock();
        for (final s in _streams) {
          s.pushed = from;
          s.ahead = null;
          s.nextEvent = 0;
          if (s.info.irregular) {
            final e = s.source.events();
            while (s.nextEvent < e.length && e.times[s.nextEvent] < from) {
              s.nextEvent++;
            }
          }
        }
      } else {
        finished = true;
        notifyListeners();
        return;
      }
    }
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 250) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  /// Send the samples of [s] up to recording time [target].
  void _pushRegular(_Replayed s, double target) {
    final w = s.ahead;
    if (w == null || w.start + w.length / w.samplingRate < target + 0.5) {
      _readAhead(s);
    }
    if (w == null) return;
    final rate = w.samplingRate;
    final a = math.max(0, ((s.pushed - w.start) * rate).ceil());
    final z = math.min(w.length, ((target - w.start) * rate).ceil());
    if (z <= a) return;
    final ch = s.info.channelCount;
    final values = Float32List((z - a) * ch);
    final times = Float64List(z - a);
    var n = 0;
    for (var i = a; i < z; i++) {
      final t = w.start + i / rate;
      var gap = false;
      for (var c = 0; c < ch; c++) {
        final v = w.channels[c][i];
        if (v.isNaN) gap = true;
        values[n * ch + c] = v;
      }
      if (gap) continue; // not sent: a gap in the recording
      times[n] = _startClock + (t - from);
      n++;
    }
    s.pushed = w.start + z / rate;
    if (n == 0) return;
    sent += n;
    s.outlet.push(
      Float32List.sublistView(values, 0, n * ch),
      Float64List.sublistView(times, 0, n),
    );
  }

  void _readAhead(_Replayed s) {
    if (s.reading) return;
    s.reading = true;
    final t0 = s.pushed;
    s.source
        .read(t0, t0 + blockS, DerivedSpec.none)
        .then((w) {
          if (w != null && w.length > 0) s.ahead = w;
        })
        .catchError((Object _) {})
        .whenComplete(() => s.reading = false);
  }

  void _pushEvents(_Replayed s, double target) {
    final e = s.source.events();
    final times = <double>[];
    final strings = <String>[];
    final values = <double>[];
    while (s.nextEvent < e.length && e.times[s.nextEvent] <= target) {
      final i = s.nextEvent++;
      times.add(_startClock + (e.times[i] - from));
      if (e.text != null) {
        strings.add(e.text![0][i]);
      } else {
        for (final c in e.channels) {
          values.add(c[i]);
        }
      }
    }
    if (times.isEmpty) return;
    sent += times.length;
    if (e.text != null) {
      s.outlet.pushStrings(strings, times);
    } else {
      s.outlet.push(Float32List.fromList(values), Float64List.fromList(times));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    for (final s in _streams) {
      await s.outlet.close();
    }
  }
}

/// One stream of a recording replayed from a position under another name,
/// listed with the forwards (Forward on a recording's tab).
class LslReplayForward implements LslForwarding {
  final LslReplay replay;
  final StreamInfo info;
  @override
  final String name;

  LslReplayForward._(this.replay, this.info, this.name);

  /// Replay [info] of [session] from [from] seconds as [name].
  static Future<LslReplayForward> start(
    SourceSession session,
    StreamInfo info, {
    required String name,
    required double from,
    bool loop = false,
    LslOutletOptions options = const LslOutletOptions(),
    OutletFactory? create,
  }) async {
    final r = await LslReplay.start(
      session,
      from: from,
      loop: loop,
      options: options,
      only: [info],
      name: (_) => name,
      create: create,
    );
    return LslReplayForward._(r, info, name);
  }

  @override
  String get from => '${info.name} (recording)';

  @override
  SourceSession get source => replay.session;

  @override
  List<int> get channels => [for (var c = 0; c < info.channelCount; c++) c];

  @override
  int get sent => replay.sent;

  @override
  Future<void> close() => replay.close();
}
