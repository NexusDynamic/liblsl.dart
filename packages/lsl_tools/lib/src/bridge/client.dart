import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:peer_coordinator/coordination.dart'
    show
        ClockModel,
        ClockProbeSample,
        ClockSyncService,
        LatencyWindow,
        PeerClockOffsets,
        TimestampSmoother;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../lsl.dart';
import 'protocol.dart';

/// A connection to an LSL bridge ([LslBridgeServer]): the streams it
/// shares, received as [LslInlet]s. Works on the web too, so browsers can
/// view LSL streams through a bridge.
class LslBridgeClient {
  final Uri url;

  /// What this computer is called in the [ClockChain]s it passes on.
  final String name;
  final WebSocketChannel _channel;
  final double Function() _clock;
  final _streams = StreamController<List<BridgeStream>>.broadcast();
  List<BridgeStream> streams = const [];

  /// Whether the bridge lets this client publish streams ([publish]).
  bool acceptsPublish = false;

  /// Ids in [streams] of the streams this client publishes: the bridge
  /// shares them with everyone, this client included.
  final Set<int> ownIds = {};

  /// The shared streams other than the ones this client publishes.
  List<BridgeStream> get others => [
    for (final s in streams)
      if (!ownIds.contains(s.id)) s,
  ];

  /// Our publish id to the id the bridge shares the stream as.
  final Map<int, int> _sharedAs = {};

  /// Streams published here, by id, waiting for the bridge's answer.
  final Map<int, Completer<void>> _publishing = {};
  final Map<int, BridgeOutlet> _outlets = {};
  int _nextPublish = 1;
  final Map<int, _BridgeInlet> _inlets = {};
  late final StreamSubscription<Object?> _sub;
  bool _closed = false;

  /// Why the connection ended, if it did.
  String? error;

  /// The bridge's clock against this computer's, measured as LSL measures
  /// an outlet's (bursts of probes, the fastest round trip of each) with a
  /// line fitted through the last minute for the drift.
  final _link = ClockModel();
  final _linked = Completer<void>();
  late final ClockSyncService _sync;
  static const _bridge = 'bridge';

  LslBridgeClient._(this.url, this.name, this._channel, this._clock) {
    _sub = _channel.stream.listen(
      _onMessage,
      onError: (Object e) => _end('$e'),
      onDone: () => _end(
        error ?? _channel.closeReason ?? 'The bridge closed the connection',
      ),
    );
    _sync = ClockSyncService(
      offsets: PeerClockOffsets(),
      sendProbe: (_, wave, _) {
        if (_closed) return;
        _channel.sink.add(
          jsonEncode({'type': 'ping', 't': _clock(), 'wave': wave}),
        );
      },
      onEstimate: (_, estimate) {
        _link.add(estimate);
        if (!_linked.isCompleted) _linked.complete();
        _outlets.keys.forEach(_sendTiming);
        for (final i in _inlets.values) {
          i._flush();
        }
      },
    )..trackPeer(_bridge);
  }

  /// Connect to [url] (`ws://host:port`), with the bridge's [token] if it
  /// has one. [clock] replaces this computer's LSL clock (for tests).
  static Future<LslBridgeClient> connect(
    Uri url, {
    String token = '',
    String name = 'client',
    double Function()? clock,
  }) async {
    final u = url.replace(
      queryParameters: {
        ...url.queryParameters,
        'v': '$bridgeProtocol',
        if (token.isNotEmpty) 'token': token,
      },
    );
    final channel = WebSocketChannel.connect(u);
    await channel.ready;
    return LslBridgeClient._(url, name, channel, clock ?? lsl.clock);
  }

  /// The hop from the bridge's clock to this computer's, or null until it
  /// has been measured (about a second after connecting).
  ClockHop? get link =>
      _link.ready ? _link.hop(node: name, via: _bridge) : null;

  /// Completes once [link] is known.
  Future<void> get linked => _linked.future;

  /// Fires when the list of shared streams changes.
  Stream<List<BridgeStream>> get onStreams => _streams.stream;

  bool get closed => _closed;

  void _onMessage(Object? message) {
    final now = _clock();
    if (message is String) {
      final m = jsonDecode(message) as Map<String, Object?>;
      switch (m['type']) {
        case 'published':
          final ok = {
            for (final id in (m['ids'] as List?) ?? const [])
              (id as num).toInt(),
          };
          final shared = (m['shared_ids'] as Map?) ?? const {};
          for (final e in shared.entries) {
            final id = (e.value as num).toInt();
            _sharedAs[int.parse('${e.key}')] = id;
            ownIds.add(id);
          }
          final errors = (m['errors'] as Map?) ?? const {};
          for (final e in errors.entries) {
            _publishing
                .remove(int.parse('${e.key}'))
                ?.completeError(StateError('${e.value}'));
          }
          for (final id in ok) {
            _publishing.remove(id)?.complete();
          }
        case 'streams':
          if (m['protocol'] != bridgeProtocol) {
            _end('The bridge speaks an older protocol: update it');
            _channel.sink.close();
            return;
          }
          acceptsPublish = m['accepts_publish'] == true;
          streams = [
            for (final s in m['streams']! as List)
              BridgeStream.fromJson(
                (s as Map).cast<String, Object?>(),
                host: url.host,
              ),
          ];
          final ids = {for (final s in streams) s.id};
          ownIds.retainAll(ids);
          // Streams no longer shared end once what arrived is read.
          for (final i in _inlets.values) {
            if (!ids.contains(i.bridged.id)) {
              i._error ??= '${i.bridged.description.name} is no longer shared';
            }
          }
          if (!_streams.isClosed) _streams.add(streams);
        case 'timing':
          _inlets[(m['id'] as num?)?.toInt()]?._timing(
            ClockChain.fromJson(m['hops']),
          );
        case 'pong':
          final t0 = m['t'], t1 = m['t1'], t2 = m['t2'], wave = m['wave'];
          if (t0 is! num || t1 is! num || t2 is! num || wave is! num) return;
          _sync.recordReply(
            _bridge,
            wave.toInt(),
            ClockProbeSample(
              t0: t0.toDouble(),
              t1: t1.toDouble(),
              t2: t2.toDouble(),
              t3: now,
            ),
          );
      }
      return;
    }
    final bytes = message is Uint8List
        ? message
        : Uint8List.fromList(message! as List<int>);
    final (id, chunk) = decodeSamples(bytes, received: now);
    _inlets[id]?._add(chunk);
  }

  void _subscribe() {
    if (_closed) return;
    _channel.sink.add(
      jsonEncode({'type': 'subscribe', 'ids': _inlets.keys.toList()}),
    );
  }

  /// Receive [stream] as an inlet, which treats time stamps as an LSL inlet
  /// does: with [LslInletOptions.clockSync] they arrive on this computer's
  /// clock (smoothed with [LslInletOptions.dejitter]); without, as the
  /// origin stamped them, with [LslInlet.timeCorrectionEx] to correct them.
  LslInlet open(
    BridgeStream stream, {
    LslInletOptions options = const LslInletOptions(),
  }) {
    final inlet = _inlets[stream.id] ??= _BridgeInlet(this, stream, options);
    _subscribe();
    return inlet;
  }

  void _release(_BridgeInlet inlet) {
    if (_inlets[inlet.bridged.id] == inlet) _inlets.remove(inlet.bridged.id);
    _subscribe();
  }

  /// Publish a stream on the bridge's computer: it becomes an LSL outlet
  /// there (if the bridge [acceptsPublish]). Time stamps are taken to be on
  /// this computer's clock ([lsl] `clock()`), unless the outlet is given
  /// the [BridgeOutlet.upstream] they came through.
  Future<BridgeOutlet> publish(LslOutletSpec spec) async {
    if (_closed) throw StateError('The bridge is closed');
    final id = _nextPublish++;
    final done = _publishing[id] = Completer<void>();
    _channel.sink.add(
      jsonEncode({
        'type': 'publish',
        'streams': [
          BridgeStream(
            id,
            LslStreamDescription(
              name: spec.name,
              type: spec.type,
              channelCount: spec.channelCount,
              rate: spec.rate,
              format: spec.format,
              sourceId: spec.sourceId,
            ),
            spec.channels,
            '',
          ).toJson(),
        ],
      }),
    );
    // The bridge must know how to read the time stamps before any arrive.
    await Future.wait([done.future, linked]).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _publishing.remove(id);
        throw TimeoutException('The bridge did not answer');
      },
    );
    final outlet = _outlets[id] = BridgeOutlet._(this, id, spec);
    _sendTiming(id);
    return outlet;
  }

  /// Tell the bridge how outlet [id]'s time stamps map onto its clock: the
  /// way they came here, then our link walked backwards.
  void _sendTiming(int id) {
    final outlet = _outlets[id];
    final link = this.link;
    if (_closed || outlet == null || link == null) return;
    _channel.sink.add(
      jsonEncode({
        'type': 'timing',
        'id': id,
        'hops': outlet._upstream.then(link.inverse(node: url.host)).toJson(),
      }),
    );
  }

  void _send(int id, LslChunk chunk, int channels) {
    if (_closed) return;
    _channel.sink.add(encodeSamples(id, chunk, channels));
  }

  void _unpublish(int id) {
    _outlets.remove(id);
    final shared = _sharedAs.remove(id);
    if (shared != null) ownIds.remove(shared);
    if (_closed) return;
    _channel.sink.add(
      jsonEncode({
        'type': 'unpublish',
        'ids': [id],
      }),
    );
  }

  void _end(String reason) {
    if (_closed) return;
    error = reason;
    _closed = true;
    _sync.dispose();
    for (final i in _inlets.values) {
      i._error = reason;
    }
    _streams.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sync.dispose();
    await _sub.cancel();
    await _channel.sink.close();
    await _streams.close();
  }
}

class _BridgeInlet implements LslInlet {
  final LslBridgeClient _client;
  final BridgeStream bridged;
  final LslInletOptions options;
  final List<LslChunk> _buffer = [];
  int _buffered = 0;
  String? _error;

  /// How time stamps map onto the bridge's clock; null until it says.
  ClockChain? _upstream;

  /// Chunks that arrived before their time stamps could be mapped.
  final List<LslChunk> _held = [];
  final TimestampSmoother? _smoother;
  final _latency = LatencyWindow();
  double? _lastTime;

  _BridgeInlet(this._client, this.bridged, this.options)
    : _smoother = options.dejitter && bridged.description.rate > 0
          ? TimestampSmoother(
              bridged.description.rate,
              monotonize: options.monotonize,
            )
          : null;

  bool get _mappable => _upstream != null && _client._link.ready;

  /// Keep at most a minute, as a real inlet's buffer would.
  int get _max => math.max(1000, (bridged.description.rate * 60).ceil());

  void _timing(ClockChain upstream) {
    _upstream = upstream;
    _flush();
  }

  void _add(LslChunk c) {
    if (c.length == 0) return;
    if (!_mappable) {
      _held.add(c);
      var held = _held.fold(0, (n, h) => n + h.length);
      while (held > _max && _held.length > 1) {
        held -= _held.removeAt(0).length;
      }
      return;
    }
    // Origin clock to the bridge's, then to this computer's.
    final link = _client._link;
    final upstream = _upstream!;
    final mapped = Float64List(c.length);
    for (var i = 0; i < c.length; i++) {
      final onBridge = upstream.map(c.times[i]);
      mapped[i] = onBridge + link.offsetAt(onBridge);
    }
    _lastTime = c.times.last;
    final received = c.received;
    if (received != null) _latency.add(received - mapped.last);
    _smoother?.smoothAll(mapped);
    _buffer.add(
      options.clockSync
          ? LslChunk(
              mapped,
              values: c.values,
              strings: c.strings,
              received: received,
            )
          : c,
    );
    _buffered += c.length;
    while (_buffered > _max && _buffer.length > 1) {
      _buffered -= _buffer.removeAt(0).length;
    }
  }

  void _flush() {
    if (!_mappable || _held.isEmpty) return;
    final held = [..._held];
    _held.clear();
    held.forEach(_add);
  }

  @override
  LslStreamDescription get stream => bridged.description;

  @override
  List<LslChannel> get channels => bridged.channels;

  @override
  String get fullXml => bridged.xml;

  @override
  Future<double> timeCorrection() async => (await timeCorrectionEx()).offset;

  /// Zero with clock sync (time stamps arrive on this computer's clock
  /// already), else the whole way's offset at the latest sample.
  @override
  Future<LslTimeCorrection> timeCorrectionEx() async {
    if (options.clockSync) return LslTimeCorrection.zero;
    final at = _lastTime;
    if (!_mappable || at == null) throw StateError('No clock offset yet');
    final chain = await this.chain();
    return LslTimeCorrection(
      offset: chain.offsetAt(at),
      uncertainty: chain.uncertainty,
      remoteTime: at,
    );
  }

  @override
  Future<ClockChain> chain() async {
    final upstream = _upstream;
    if (upstream == null || !_client._link.ready) {
      throw StateError('No clock offset yet');
    }
    return upstream.then(
      _client._link.hop(
        node: _client.name,
        via: LslBridgeClient._bridge,
        latency: _latency.mean,
        jitter: _latency.jitter,
      ),
    );
  }

  @override
  Future<LslChunk> pull(int maxSamples) async {
    if (_error != null && _buffer.isEmpty) throw StateError(_error!);
    if (_buffer.isEmpty) return LslChunk.empty;
    final c = _buffer.removeAt(0);
    _buffered -= c.length;
    return c;
  }

  @override
  Future<void> close() async => _client._release(this);
}

/// A stream this client publishes on the bridge.
class BridgeOutlet implements LslOutlet {
  final LslBridgeClient _client;
  final int _id;
  @override
  final LslOutletSpec spec;
  bool _closed = false;
  ClockChain _upstream = ClockChain.empty;

  BridgeOutlet._(this._client, this._id, this.spec);

  /// How the time stamps pushed map onto this computer's clock: empty (the
  /// default) when they are on it already, or the [LslInlet.chain] of the
  /// inlet they are passed on from unchanged. Set it again as that changes.
  ClockChain get upstream => _upstream;

  set upstream(ClockChain chain) {
    _upstream = chain;
    _client._sendTiming(_id);
  }

  @override
  Future<void> push(Float32List values, Float64List times) async {
    if (_closed || times.isEmpty) return;
    _client._send(_id, LslChunk(times, values: values), spec.channelCount);
  }

  @override
  Future<void> pushStrings(List<String> values, List<double> times) async {
    if (_closed || values.isEmpty) return;
    _client._send(
      _id,
      LslChunk(Float64List.fromList(times), strings: values),
      1,
    );
  }

  /// Whether the bridge is still there (who reads the stream there is not
  /// known here).
  @override
  Future<bool> hasConsumers() async => !_closed && !_client.closed;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client._unpublish(_id);
  }
}
