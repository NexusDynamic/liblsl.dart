import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../lsl.dart';
import 'client.dart';
import 'protocol.dart';

/// Publishes the streams a bridge shares as LSL streams on this computer:
/// those matching [patterns] (names, `*` as a wildcard; all without),
/// named with [suffix] added. Follows the bridge: streams it starts sharing
/// are published too, and ones it stops sharing are closed. Streams this
/// client publishes on the bridge itself are left out.
///
/// Time stamps are put on this computer's LSL clock ([inletOptions] says
/// whether smoothed), so the streams read like any other here. How they
/// got here is kept in [timing] and, with [timingStream], published as the
/// `BridgeTiming` stream for whoever records or watches in this lab.
class LslBridgeRepublisher {
  final LslBridgeClient client;
  final List<String> patterns;
  final String suffix;
  final LslOutletOptions options;
  final LslInletOptions inletOptions;
  final bool timingStream;

  final Map<int, (LslInlet, LslOutlet)> _relays = {};
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<List<BridgeStream>> _sub;
  Timer? _timer;
  Timer? _timingTimer;
  LslOutlet? _timingOutlet;

  /// The clock corrections and latency of each stream published here, hop
  /// by hop, by name; measured every two seconds.
  final Map<String, ClockChain> timing = {};
  bool _closed = false;
  bool _pulling = false;
  Future<void> _syncing = Future.value();

  /// Samples published so far.
  int sent = 0;

  /// Why a stream could not be published, by name.
  final Map<String, String> errors = {};

  LslBridgeRepublisher._(
    this.client,
    this.patterns,
    this.suffix,
    this.options,
    this.inletOptions,
    this.timingStream,
  );

  /// Start publishing [client]'s streams here.
  static Future<LslBridgeRepublisher> start(
    LslBridgeClient client, {
    List<String> patterns = const [],
    String suffix = '',
    LslOutletOptions options = const LslOutletOptions(),
    LslInletOptions inletOptions = const LslInletOptions(),
    bool timingStream = true,
  }) async {
    await lsl.prepare();
    final r = LslBridgeRepublisher._(
      client,
      patterns,
      suffix,
      options,
      // An LSL outlet's time stamps are on its computer's clock.
      inletOptions.copyWith(clockSync: true),
      timingStream,
    );
    r._sub = client.onStreams.listen(
      (_) => r._sync(),
      onDone: () {
        if (!r._changes.isClosed) r._changes.add(null);
      },
    );
    await r._sync();
    r._timer = Timer.periodic(
      Duration(milliseconds: inletOptions.pullIntervalMs),
      (_) => r._pull(),
    );
    if (timingStream) {
      r._timingOutlet = await lsl.createOutlet(
        LslOutletSpec(
          name: 'BridgeTiming$suffix',
          type: 'Timing',
          channelCount: 1,
          rate: 0,
          format: LslFormat.string,
          sourceId: 'bridge:timing:${client.url.host}:${client.url.port}',
        ),
        options,
      );
    }
    r._timingTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => r._measure(),
    );
    return r;
  }

  /// Note each stream's [timing] and publish it: one JSON sample per
  /// stream (strings, as an offset between two clocks needs more digits
  /// than a float32 has).
  Future<void> _measure() async {
    final samples = <String>[];
    for (final (inlet, outlet) in [..._relays.values]) {
      final ClockChain chain;
      try {
        chain = await inlet.chain();
      } catch (_) {
        continue; // not measured yet
      }
      timing[outlet.spec.name] = chain;
      samples.add(
        jsonEncode({
          'stream': outlet.spec.name,
          'offset': chain.offset,
          'uncertainty': chain.uncertainty,
          'drift_ppm': chain.drift * 1e6,
          'latency': chain.latency,
          'hops': chain.toJson(),
        }),
      );
    }
    if (_closed || samples.isEmpty) return;
    final now = lsl.clock();
    await _timingOutlet?.pushStrings(samples, [for (final _ in samples) now]);
  }

  /// Names of the streams published here now.
  List<String> get names => [for (final (_, o) in _relays.values) o.spec.name];

  /// Fires when streams are published or closed.
  Stream<void> get onChange => _changes.stream;

  bool _wanted(BridgeStream s) {
    if (client.ownIds.contains(s.id)) return false;
    if (patterns.isEmpty) return true;
    return patterns.any(
      (p) => RegExp(
        '^${RegExp.escape(p).replaceAll(r'\*', '.*')}\$',
        caseSensitive: false,
      ).hasMatch(s.description.name),
    );
  }

  Future<void> _sync() => _syncing = _syncing.then((_) async {
    if (_closed) return;
    final shared = {for (final s in client.streams) s.id: s};
    var changed = false;
    for (final id in [..._relays.keys]) {
      if (shared.containsKey(id) && _wanted(shared[id]!)) continue;
      final (inlet, outlet) = _relays.remove(id)!;
      timing.remove(outlet.spec.name);
      await inlet.close();
      await outlet.close();
      changed = true;
    }
    for (final s in shared.values) {
      if (_relays.containsKey(s.id) || !_wanted(s)) continue;
      final d = s.description;
      try {
        final outlet = await lsl.createOutlet(
          LslOutletSpec(
            name: '${d.name}$suffix',
            type: d.type,
            channelCount: d.format.isString ? 1 : d.channelCount,
            rate: d.rate,
            format: d.format.isString ? LslFormat.string : LslFormat.float32,
            sourceId: 'bridge:${d.sourceId.isEmpty ? d.name : d.sourceId}',
            channels: s.channels,
            desc: {
              'bridge': {'url': '${client.url}', 'origin': d.hostname},
            },
          ),
          options,
        );
        _relays[s.id] = (client.open(s, options: inletOptions), outlet);
        errors.remove(d.name);
      } catch (e) {
        errors[d.name] = '$e';
      }
      changed = true;
    }
    if (changed && !_changes.isClosed) _changes.add(null);
  });

  Future<void> _pull() async {
    if (_pulling || _closed) return;
    _pulling = true;
    try {
      for (final (inlet, outlet) in [..._relays.values]) {
        final LslChunk c;
        try {
          c = await inlet.pull(4096);
        } catch (_) {
          continue; // gone from the bridge; the next update closes it
        }
        if (c.length == 0) continue;
        sent += c.length;
        if (c.strings != null) {
          final ch = inlet.stream.channelCount;
          await outlet.pushStrings([
            for (var i = 0; i < c.length; i++) c.strings![i * ch],
          ], c.times);
        } else {
          await outlet.push(
            c.values is Float32List
                ? c.values! as Float32List
                : Float32List.fromList(c.values!),
            c.times,
          );
        }
      }
    } finally {
      _pulling = false;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timingTimer?.cancel();
    await _sub.cancel();
    await _syncing;
    await _timingOutlet?.close();
    for (final (inlet, outlet) in _relays.values) {
      await inlet.close();
      await outlet.close();
    }
    _relays.clear();
    await _changes.close();
  }
}
