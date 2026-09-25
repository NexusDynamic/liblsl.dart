import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:signal_viewer/signal_viewer.dart';

import 'package:lsl_tools/lsl_tools.dart';
import 'lsl_session.dart';

/// A stream being published again over LSL (see [LslForward] and
/// [LslSourceForward]).
abstract interface class LslForwarding {
  /// The name it is published under.
  String get name;

  /// What it comes from, for display.
  String get from;

  /// The session it comes from.
  SourceSession get source;

  /// Channels sent, as indices into the forwarded stream.
  List<int> get channels;

  /// Samples sent so far.
  int get sent;

  Future<void> close();
}

/// Re-publishes a stream received in [session] as a new LSL stream: under
/// another name, optionally with only some [channels] and with [derived]
/// processing (re-referencing, high-pass and notch filters, applied as the
/// samples arrive). Time stamps are passed on as received.
class LslForward implements LslForwarding {
  final LslSession session;
  final LslOutlet outlet;

  /// Channels of the session's stream that are sent, in order.
  @override
  final List<int> channels;
  final DerivedSpec derived;
  final SosStreamFilter? _filter;
  @override
  int sent = 0;

  @override
  SourceSession get source => session;

  @override
  String get from => session.info.name;
  late final void Function(LslChunk) _tap = _onChunk;

  LslForward._(this.session, this.outlet, this.channels, this.derived)
    : _filter = derived.filters && session.info.rate > 0
          ? SosStreamFilter(
              Sos.display(
                session.info.rate,
                highpass: derived.highpass,
                notch: derived.notch,
              ),
              session.info.channelCount,
            )
          : null {
    session.taps.add(_tap);
  }

  /// Start forwarding [session] as [name].
  static Future<LslForward> start(
    LslSession session, {
    required String name,
    List<int>? channels,
    DerivedSpec derived = DerivedSpec.none,
    LslOutletOptions options = const LslOutletOptions(),
  }) async {
    final info = session.info;
    final stream = session.inlet.stream;
    final strings = stream.format.isString;
    final chosen = strings
        ? const [0]
        : (channels ?? [for (var c = 0; c < info.channelCount; c++) c]);
    final outlet = await lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: stream.type,
        channelCount: chosen.length,
        rate: info.irregular ? 0 : info.rate,
        format: strings ? LslFormat.string : LslFormat.float32,
        sourceId:
            'forward:${stream.sourceId.isEmpty ? stream.uid : stream.sourceId}:$name',
        channels: [
          for (final c in chosen)
            LslChannel(info.labels[c], unit: info.unit(c)),
        ],
        desc: {
          'forwarded': {
            'from': stream.name,
            'source_id': stream.sourceId,
            'hostname': stream.hostname,
            if (derived.highpass > 0) 'highpass_hz': '${derived.highpass}',
            if (derived.notch > 0) 'notch_hz': '${derived.notch}',
            if (derived.references) 'rereferenced': 'true',
          },
        },
      ),
      options,
    );
    return LslForward._(
      session,
      outlet,
      chosen,
      strings ? DerivedSpec.none : derived,
    );
  }

  @override
  String get name => outlet.spec.name;

  void _onChunk(LslChunk c) {
    if (c.length == 0) return;
    if (c.strings != null) {
      outlet.pushStrings([
        for (var i = 0; i < c.length; i++)
          c.strings![i * session.info.channelCount],
      ], c.times);
      sent += c.length;
      return;
    }
    final n = session.info.channelCount;
    final values = c.values!;
    final m = c.length;
    List<Float64List>? cols;
    if (derived.references || _filter != null) {
      cols = [
        for (var ch = 0; ch < n; ch++)
          Float64List(m)
            ..setAll(0, [for (var i = 0; i < m; i++) values[i * n + ch]]),
      ];
      if (derived.references) applyReference(cols, derived);
      final f = _filter;
      if (f != null) {
        for (var ch = 0; ch < n; ch++) {
          f.process(ch, cols[ch]);
        }
      }
    }
    final out = Float32List(m * channels.length);
    for (var i = 0; i < m; i++) {
      for (var k = 0; k < channels.length; k++) {
        final ch = channels[k];
        out[i * channels.length + k] = cols == null
            ? values[i * n + ch]
            : cols[ch][i];
      }
    }
    outlet.push(out, c.times);
    sent += m;
  }

  @override
  Future<void> close() async {
    session.taps.remove(_tap);
    await outlet.close();
  }
}

/// Publishes a live tab over LSL: any source (a device, a serial stream, a
/// merged group of ports), with exactly the tab's channels, or some of
/// them ([channels]), optionally with [derived] processing (causal
/// filters). Samples are read as every stream of the tab has them, and
/// stamped on the LSL clock (this computer's time of the tab's newest
/// sample when forwarding started, onwards by the rate).
class LslSourceForward implements LslForwarding {
  @override
  final SourceSession source;
  final StreamInfo info;
  final StreamSource _stream;
  final LslOutlet outlet;
  @override
  final List<int> channels;
  final DerivedSpec derived;

  /// Sample tick of the next sample to send (regular streams).
  int? _next;

  /// Events sent (irregular streams).
  int _events = 0;

  /// LSL time minus the tab's time.
  final double _offset;
  late final Timer _timer;
  bool _busy = false;
  @override
  int sent = 0;

  LslSourceForward._(
    this.source,
    this.info,
    this._stream,
    this.outlet,
    this.channels,
    this.derived,
  ) : _offset = lsl.clock() - _stream.end {
    if (info.irregular) {
      // Only what comes from now on.
      _events = _stream.events().length;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }

  /// Start publishing tab [info] of [session] as [name].
  static Future<LslSourceForward> start(
    SourceSession session,
    StreamInfo info, {
    required String name,
    List<int>? channels,
    DerivedSpec derived = DerivedSpec.none,
    LslOutletOptions options = const LslOutletOptions(),
  }) async {
    // A source of its own: its processing state is not the tab's.
    final stream = session.sourceFor(info);
    final text = info.irregular && stream.events().text != null;
    final chosen = text
        ? const [0]
        : (channels ?? [for (var c = 0; c < info.channelCount; c++) c]);
    final outlet = await lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: info.type.isEmpty ? info.kind.label : info.type,
        channelCount: chosen.length,
        rate: info.irregular ? 0 : info.rate,
        format: text ? LslFormat.string : LslFormat.float32,
        sourceId: 'forward:${session.rememberKey}:${info.key}:$name',
        channels: [
          for (final c in chosen)
            LslChannel(info.labels[c], unit: info.unit(c)),
        ],
        desc: {
          'forwarded': {
            'from': '${session.label} · ${info.name}',
            if (derived.highpass > 0) 'highpass_hz': '${derived.highpass}',
            if (derived.notch > 0) 'notch_hz': '${derived.notch}',
            if (derived.references) 'rereferenced': 'true',
          },
        },
      ),
      options,
    );
    return LslSourceForward._(
      session,
      info,
      stream,
      outlet,
      chosen,
      text ? DerivedSpec.none : derived,
    );
  }

  @override
  String get name => outlet.spec.name;

  @override
  String get from => '${source.label} · ${info.name}';

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      if (info.irregular) {
        await _sendEvents();
      } else {
        await _sendSamples();
      }
    } catch (_) {
      // The source is closing; its tab closes the forward.
    } finally {
      _busy = false;
    }
  }

  Future<void> _sendSamples() async {
    final rate = info.rate;
    final session = source;
    // Ticks every stream of the tab has (a merged group waits for its
    // slowest port).
    final int end;
    if (session is LiveData) {
      final range = (session as LiveData).tickRange(info.channels, rate);
      if (range == null) return;
      end = range.$2;
    } else {
      end = (_stream.end * rate).floor();
    }
    final next = _next ??= end;
    if (end <= next) return;
    final w = await _stream.read(
      (next + 1e-6) / rate,
      (end - 1e-6) / rate,
      derived,
    );
    if (w == null || w.length == 0) return;
    final first = (w.start * rate).round();
    final n = math.min(w.length, end - first);
    final ch = channels.length;
    final values = Float32List(n * ch);
    final times = Float64List(n);
    var k = 0;
    for (var i = math.max(0, next - first); i < n; i++) {
      var gap = false;
      for (var j = 0; j < ch; j++) {
        final v = w.channels[channels[j]][i];
        if (v.isNaN) gap = true;
        values[k * ch + j] = v;
      }
      if (gap) continue;
      times[k++] = (first + i) / rate + _offset;
    }
    _next = first + n;
    if (k == 0) return;
    await outlet.push(
      Float32List.sublistView(values, 0, k * ch),
      Float64List.sublistView(times, 0, k),
    );
    sent += k;
  }

  Future<void> _sendEvents() async {
    final e = _stream.events();
    if (e.length <= _events) return;
    final from = _events;
    _events = e.length;
    final times = [for (var i = from; i < e.length; i++) e.times[i] + _offset];
    if (e.text != null) {
      await outlet.pushStrings([
        for (var i = from; i < e.length; i++) e.text![0][i],
      ], times);
    } else {
      final values = Float32List(times.length * channels.length);
      for (var i = from; i < e.length; i++) {
        for (var j = 0; j < channels.length; j++) {
          values[(i - from) * channels.length + j] = e.channels[channels[j]][i];
        }
      }
      await outlet.push(values, Float64List.fromList(times));
    }
    sent += times.length;
  }

  @override
  Future<void> close() async {
    _timer.cancel();
    await outlet.close();
  }
}
