/// Streams between LSL or a bridge and a `peer_coordinator` session (WebRTC,
/// say): [LslDataStreamPump] sends an inlet's samples through a
/// [DataStream], and [DataStreamInlet] receives a [DataStream] as an inlet,
/// which a [BridgeOutlet], an LSL outlet or an [LslRecorder] can take.
///
/// Time stamps cross unchanged, as they do through a bridge, and each end
/// adds its hop to the stream's [ClockChain].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:peer_coordinator/framework.dart';

import '../lsl.dart';

/// Seconds to add to `peer_coordinator`'s clock to get this computer's LSL
/// clock. Both are steady, so it does not change (and is zero without LSL,
/// where they are one clock).
double _peerToLsl() => lsl.clock() - PeerClock.now();

/// [chain] ending [by] seconds later: the same hops, read on another clock
/// of the last one's computer.
ClockChain _shifted(ClockChain chain, double by) {
  if (by == 0) return chain;
  if (chain.hops.isEmpty) {
    return ClockChain([ClockHop(node: 'local', via: 'local', offset: by)]);
  }
  final last = chain.hops.last;
  return ClockChain([
    ...chain.hops.take(chain.hops.length - 1),
    ClockHop(
      node: last.node,
      via: last.via,
      offset: last.offset + by,
      drift: last.drift,
      at: last.at,
      uncertainty: last.uncertainty,
      latency: last.latency,
      jitter: last.jitter,
    ),
  ]);
}

/// Sends what an inlet receives through a [DataStream], each sample with
/// the time stamp it came with.
class LslDataStreamPump {
  /// Opened without clock sync, so its time stamps are the origin's.
  final LslInlet inlet;
  final DataStream stream;
  late final Timer _pulling, _measuring;
  bool _busy = false;
  bool _closed = false;

  /// Samples sent so far.
  int sent = 0;

  LslDataStreamPump._(this.inlet, this.stream);

  /// Start sending [inlet]'s samples through [stream], which must have its
  /// channel count and a matching data type, and be started.
  static Future<LslDataStreamPump> start(
    LslInlet inlet,
    DataStream stream, {
    Duration pullInterval = const Duration(milliseconds: 20),
  }) async {
    if (!stream.relaysSourceClock) {
      throw UnsupportedError(
        '${stream.config.name} cannot pass time stamps on',
      );
    }
    final pump = LslDataStreamPump._(inlet, stream);
    await pump._measure();
    pump._pulling = Timer.periodic(pullInterval, (_) => pump._pull());
    // As often as LSL and the bridge measure clock offsets.
    pump._measuring = Timer.periodic(
      const Duration(seconds: 2),
      (_) => pump._measure(),
    );
    return pump;
  }

  Future<void> _measure() async {
    try {
      final chain = await inlet.chain();
      if (!_closed) stream.upstream = _shifted(chain, -_peerToLsl());
    } catch (_) {
      // No measurement now; receivers keep the last.
    }
  }

  Future<void> _pull() async {
    // Not before receivers can be told how to read the time stamps.
    if (_busy || _closed || stream.upstream.hops.isEmpty) return;
    _busy = true;
    try {
      final c = await inlet.pull(4096);
      final ch = inlet.stream.channelCount;
      final type = stream.config.dataType;
      for (var i = 0; i < c.length && !_closed; i++) {
        final Iterable<Object> sample;
        if (c.strings != null) {
          sample = c.strings!.getRange(i * ch, (i + 1) * ch);
        } else {
          final values = c.values!.getRange(i * ch, (i + 1) * ch);
          sample =
              type == StreamDataType.float32 || type == StreamDataType.double64
              ? values
              : values.map((v) => v.round());
        }
        await stream.sendDataAt(c.times[i], sample);
        sent++;
      }
    } catch (_) {
      // The stream ended on one side; close() is the owner's call.
    } finally {
      _busy = false;
    }
  }

  /// Stop sending. The inlet and the stream stay open.
  void close() {
    if (_closed) return;
    _closed = true;
    _pulling.cancel();
    _measuring.cancel();
  }
}

/// One producer's samples on a [DataStream], as an inlet.
///
/// Treats time stamps as an LSL inlet does: with
/// [LslInletOptions.clockSync] on this computer's LSL clock (samples whose
/// clock offset is not known yet are left out), without it as the origin
/// stamped them, with [timeCorrectionEx] and [chain] beside them.
class DataStreamInlet implements LslInlet {
  final DataStream source;

  /// The node whose samples these are (its uId).
  final String from;

  /// What this computer, and the transport, are called in the [chain].
  final String node, via;
  final LslInletOptions options;

  @override
  final LslStreamDescription stream;
  @override
  final List<LslChannel> channels;

  late final StreamSubscription<IMessage> _sub;
  final TimestampSmoother? _smoother;
  final _latency = LatencyWindow();
  final List<double> _times = [], _values = [];
  final List<String> _strings = [];
  double _received = double.nan;
  MessageTiming? _timing;

  DataStreamInlet(
    this.source, {
    required this.from,
    this.node = 'here',
    this.via = 'peer',
    String type = '',
    this.options = const LslInletOptions(),
  }) : stream = LslStreamDescription(
         name: source.config.name,
         type: type,
         channelCount: source.config.channels,
         rate: source.config.sampleRate,
         format: LslFormat.values.byName(source.config.dataType.name),
         sourceId: 'peer:$from:${source.config.name}',
         hostname: from,
         uid: 'peer:$from:${source.config.name}',
       ),
       channels = [
         for (var c = 0; c < source.config.channels; c++)
           LslChannel('ch${c + 1}'),
       ],
       _smoother = options.dejitter && source.config.sampleRate > 0
           ? TimestampSmoother(
               source.config.sampleRate,
               monotonize: options.monotonize,
             )
           : null {
    _sub = source.inbox.listen(_add);
  }

  /// Keep at most a minute, as a real inlet's buffer would.
  int get _max => (stream.rate * 60).ceil().clamp(1000, 1 << 24);

  void _add(IMessage m) {
    final timing = m.timing;
    final stamped = timing?.sourceClock;
    if (timing == null || stamped == null || timing.sourceId != from) return;
    final offset = timing.clockOffset;
    final toLsl = _peerToLsl();
    if (offset != null) {
      _timing = timing;
      _latency.add(timing.receivedClock - stamped - offset);
    } else if (options.clockSync) {
      return;
    }
    final mapped = offset == null ? stamped : stamped + offset + toLsl;
    _times.add(
      options.clockSync ? _smoother?.smooth(mapped) ?? mapped : stamped,
    );
    _received = timing.receivedClock + toLsl;
    if (stream.format.isString) {
      _strings.addAll(m.data.map((v) => '$v'));
    } else {
      _values.addAll(m.data.map((v) => (v as num).toDouble()));
    }
    final over = _times.length - _max;
    if (over > 0) {
      _times.removeRange(0, over);
      final values = stream.format.isString ? _strings : _values;
      values.removeRange(0, over * stream.channelCount);
    }
  }

  @override
  String get fullXml {
    String text(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<?xml version="1.0"?><info>'
        '<name>${text(stream.name)}</name>'
        '<type>${text(stream.type)}</type>'
        '<channel_count>${stream.channelCount}</channel_count>'
        '<nominal_srate>${stream.rate}</nominal_srate>'
        '<channel_format>${stream.format.name}</channel_format>'
        '<source_id>${text(stream.sourceId)}</source_id>'
        '<hostname>${text(stream.hostname)}</hostname>'
        '</info>';
  }

  @override
  Future<LslChunk> pull(int maxSamples) async {
    if (_times.isEmpty) return LslChunk.empty;
    final chunk = stream.format.isString
        ? LslChunk(
            Float64List.fromList(_times),
            strings: [..._strings],
            received: _received,
          )
        : LslChunk(
            Float64List.fromList(_times),
            values: Float64List.fromList(_values),
            received: _received,
          );
    _times.clear();
    _values.clear();
    _strings.clear();
    return chunk;
  }

  @override
  Future<double> timeCorrection() async => (await timeCorrectionEx()).offset;

  /// Zero with clock sync, else the whole way's offset at the latest
  /// sample.
  @override
  Future<LslTimeCorrection> timeCorrectionEx() async {
    if (options.clockSync) return LslTimeCorrection.zero;
    final chain = await this.chain();
    final at = _timing!.sourceClock!;
    return LslTimeCorrection(
      offset: chain.offsetAt(at),
      uncertainty: chain.uncertainty,
      remoteTime: at,
    );
  }

  /// The hops the sender reported, then the one from it to here.
  @override
  Future<ClockChain> chain() async {
    final timing = _timing;
    if (timing == null) throw StateError('No clock offset yet');
    final upstream = timing.upstream ?? ClockChain.empty;
    final stamped = timing.sourceClock!;
    return upstream.then(
      ClockHop(
        node: node,
        via: via,
        offset: timing.clockOffset! - upstream.offsetAt(stamped) + _peerToLsl(),
        at: upstream.map(stamped),
        uncertainty: (timing.uncertainty ?? 0) - upstream.uncertainty,
        latency: _latency.mean,
        jitter: _latency.jitter,
      ),
    );
  }

  /// Stop receiving. The [DataStream] stays open.
  @override
  Future<void> close() => _sub.cancel();
}
