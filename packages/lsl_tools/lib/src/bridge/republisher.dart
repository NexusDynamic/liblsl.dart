import 'dart:async';
import 'dart:typed_data';

import '../lsl.dart';
import 'client.dart';
import 'protocol.dart';

/// Publishes the streams a bridge shares as LSL streams on this computer:
/// those matching [patterns] (names, `*` as a wildcard; all without),
/// named with [suffix] added. Follows the bridge: streams it starts sharing
/// are published too, and ones it stops sharing are closed. Streams this
/// client publishes on the bridge itself are left out.
class LslBridgeRepublisher {
  final LslBridgeClient client;
  final List<String> patterns;
  final String suffix;
  final LslOutletOptions options;

  final Map<int, (LslInlet, LslOutlet)> _relays = {};
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<List<BridgeStream>> _sub;
  Timer? _timer;
  bool _closed = false;
  bool _pulling = false;
  Future<void> _syncing = Future.value();

  /// Samples published so far.
  int sent = 0;

  /// Why a stream could not be published, by name.
  final Map<String, String> errors = {};

  LslBridgeRepublisher._(this.client, this.patterns, this.suffix, this.options);

  /// Start publishing [client]'s streams here.
  static Future<LslBridgeRepublisher> start(
    LslBridgeClient client, {
    List<String> patterns = const [],
    String suffix = '',
    LslOutletOptions options = const LslOutletOptions(),
  }) async {
    await lsl.prepare();
    final r = LslBridgeRepublisher._(client, patterns, suffix, options);
    r._sub = client.onStreams.listen(
      (_) => r._sync(),
      onDone: () {
        if (!r._changes.isClosed) r._changes.add(null);
      },
    );
    await r._sync();
    r._timer = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => r._pull(),
    );
    return r;
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
          ),
          options,
        );
        _relays[s.id] = (client.open(s), outlet);
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
    await _sub.cancel();
    await _syncing;
    for (final (inlet, outlet) in _relays.values) {
      await inlet.close();
      await outlet.close();
    }
    _relays.clear();
    await _changes.close();
  }
}
