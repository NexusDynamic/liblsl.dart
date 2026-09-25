import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../lsl.dart';
import 'protocol.dart';

/// A connection to an LSL bridge ([LslBridgeServer]): the streams it
/// shares, received as [LslInlet]s. Works on the web too, so browsers can
/// view LSL streams through a bridge.
class LslBridgeClient {
  final Uri url;
  final WebSocketChannel _channel;
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
  int _nextPublish = 1;
  final Map<int, _BridgeInlet> _inlets = {};
  late final StreamSubscription<Object?> _sub;
  Timer? _pingTimer;
  bool _closed = false;

  /// Why the connection ended, if it did.
  String? error;

  /// Server time − this computer's time, from the ping with the shortest
  /// round trip among the last few.
  double offset = 0;
  final List<(double rtt, double offset)> _pings = [];

  LslBridgeClient._(this.url, this._channel) {
    _sub = _channel.stream.listen(
      _onMessage,
      onError: (Object e) => _end('$e'),
      onDone: () => _end(error ?? 'The bridge closed the connection'),
    );
    _ping();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _ping());
  }

  /// Connect to [url] (`ws://host:port`), with the bridge's [token] if it
  /// has one.
  static Future<LslBridgeClient> connect(Uri url, {String token = ''}) async {
    final u = token.isEmpty
        ? url
        : url.replace(
            queryParameters: {...url.queryParameters, 'token': token},
          );
    final channel = WebSocketChannel.connect(u);
    await channel.ready;
    return LslBridgeClient._(url, channel);
  }

  /// Fires when the list of shared streams changes.
  Stream<List<BridgeStream>> get onStreams => _streams.stream;

  bool get closed => _closed;

  void _ping() {
    if (_closed) return;
    _channel.sink.add(jsonEncode({'type': 'ping', 't': lsl.clock()}));
  }

  void _onMessage(Object? message) {
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
        case 'pong':
          final sent = (m['t']! as num).toDouble();
          final server = (m['server']! as num).toDouble();
          final now = lsl.clock();
          _pings.add((now - sent, server - (sent + now) / 2));
          if (_pings.length > 10) _pings.removeAt(0);
          offset = _pings.reduce((a, b) => a.$1 <= b.$1 ? a : b).$2;
      }
      return;
    }
    final bytes = message is Uint8List
        ? message
        : Uint8List.fromList(message! as List<int>);
    // Server time to this computer's.
    final (id, chunk) = decodeSamples(bytes, offset: -offset);
    _inlets[id]?._add(chunk);
  }

  void _subscribe() {
    if (_closed) return;
    _channel.sink.add(
      jsonEncode({'type': 'subscribe', 'ids': _inlets.keys.toList()}),
    );
  }

  /// Receive [stream] as an inlet.
  LslInlet open(BridgeStream stream) {
    final inlet = _inlets[stream.id] ??= _BridgeInlet(this, stream);
    _subscribe();
    return inlet;
  }

  void _release(_BridgeInlet inlet) {
    if (_inlets[inlet.bridged.id] == inlet) _inlets.remove(inlet.bridged.id);
    _subscribe();
  }

  /// Publish a stream on the bridge's computer: it becomes an LSL outlet
  /// there (if the bridge [acceptsPublish]). Time stamps given on this
  /// computer's clock ([lsl] `clock()`) arrive on the bridge's.
  Future<LslOutlet> publish(LslOutletSpec spec) async {
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
    await done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _publishing.remove(id);
        throw TimeoutException('The bridge did not answer');
      },
    );
    return _BridgeOutlet(this, id, spec);
  }

  void _send(int id, LslChunk chunk, int channels) {
    if (_closed) return;
    // This computer's time to the bridge's.
    final times = Float64List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      times[i] = chunk.times[i] + offset;
    }
    _channel.sink.add(
      encodeSamples(
        id,
        LslChunk(times, values: chunk.values, strings: chunk.strings),
        channels,
      ),
    );
  }

  void _unpublish(int id) {
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
    _pingTimer?.cancel();
    for (final i in _inlets.values) {
      i._error = reason;
    }
    _streams.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pingTimer?.cancel();
    await _sub.cancel();
    await _channel.sink.close();
    await _streams.close();
  }
}

class _BridgeInlet implements LslInlet {
  final LslBridgeClient _client;
  final BridgeStream bridged;
  final List<LslChunk> _buffer = [];
  int _buffered = 0;
  String? _error;

  _BridgeInlet(this._client, this.bridged);

  void _add(LslChunk c) {
    _buffer.add(c);
    _buffered += c.length;
    // Keep at most a minute, as a real inlet's buffer would.
    final max = math.max(1000, (bridged.description.rate * 60).ceil());
    while (_buffered > max && _buffer.length > 1) {
      _buffered -= _buffer.removeAt(0).length;
    }
  }

  @override
  LslStreamDescription get stream => bridged.description;

  @override
  List<LslChannel> get channels => bridged.channels;

  @override
  String get fullXml => bridged.xml;

  /// Time stamps arrive on this computer's clock already.
  @override
  Future<double> timeCorrection() async => 0;

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
class _BridgeOutlet implements LslOutlet {
  final LslBridgeClient _client;
  final int _id;
  @override
  final LslOutletSpec spec;
  bool _closed = false;

  _BridgeOutlet(this._client, this._id, this.spec);

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
