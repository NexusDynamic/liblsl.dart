import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../lsl.dart';
import 'protocol.dart';
import 'server.dart';

bool get supported => lsl.supported;
const bool relaySupported = true;

Future<LslBridgeServer> start(
  List<LslStreamDescription> streams, {
  required int port,
  required String host,
  required String token,
  required bool acceptPublish,
  required bool localOutlets,
  required List<String> allowedOrigins,
  required LslInletOptions options,
  required LslOutletOptions outletOptions,
}) async {
  final needsLsl = streams.isNotEmpty || (acceptPublish && localOutlets);
  if (needsLsl && !lsl.supported) {
    throw UnsupportedError(
      'LSL is not available here: only a relay without local outlets can '
      'run',
    );
  }
  final http = await HttpServer.bind(host, port);
  final server = _Server(
    http,
    host,
    token,
    acceptPublish,
    localOutlets,
    allowedOrigins,
    options,
    outletOptions,
  );
  try {
    for (final s in streams) {
      await server.share(s);
    }
  } catch (_) {
    await server.close();
    rethrow;
  }
  return server;
}

/// A stream the server shares: from LSL here, or published by a client.
class _Shared {
  final BridgeStream stream;

  /// The inlet it is read from, when from LSL here.
  final LslInlet? inlet;

  /// The client publishing it, and its id there.
  final _Client? publisher;
  final int publisherId;

  /// The LSL outlet it is also published on here, if any.
  LslOutlet? outlet;

  _Shared.local(this.stream, LslInlet this.inlet)
    : publisher = null,
      publisherId = 0;
  _Shared.published(this.stream, _Client this.publisher, this.publisherId)
    : inlet = null;

  int get id => stream.id;
}

class _Client {
  final WebSocket socket;
  final String address;
  Set<int> subscribed = {};

  /// Streams this client publishes here: its id to the shared stream.
  final Map<int, _Shared> published = {};
  _Client(this.socket, this.address);
}

class _Server implements LslBridgeServer {
  final HttpServer _http;
  @override
  final String host;
  final String token;
  @override
  final bool acceptsPublish;
  @override
  final bool localOutlets;
  final List<String> allowedOrigins;
  final LslInletOptions options;
  final LslOutletOptions outletOptions;

  /// Shared streams by id; ids are never reused, so a client that still
  /// asks for a stream that went away gets nothing.
  final Map<int, _Shared> _shared = {};
  int _nextId = 1;
  final List<_Client> _clients = [];
  final _changes = StreamController<void>.broadcast();
  late final Timer _timer;
  bool _pulling = false;
  bool _closed = false;
  @override
  int sent = 0;
  @override
  int received = 0;

  _Server(
    this._http,
    this.host,
    this.token,
    this.acceptsPublish,
    this.localOutlets,
    this.allowedOrigins,
    this.options,
    this.outletOptions,
  ) {
    _http.listen(_onRequest);
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _pull());
  }

  @override
  int get port => _http.port;

  @override
  Stream<void> get onChange => _changes.stream;

  @override
  Future<List<String>> localAddresses() async {
    if (host != '0.0.0.0') return [host];
    final found = <String>[];
    try {
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        found.addAll(i.addresses.map((a) => a.address));
      }
    } catch (_) {
      // Not allowed here (some sandboxes): loopback only.
    }
    return [...found, '127.0.0.1'];
  }

  @override
  List<LslStreamDescription> get streams => [
    for (final s in _shared.values)
      if (s.inlet != null) s.inlet!.stream,
  ];

  @override
  int get clientCount => _clients.length;

  @override
  List<LslBridgeClientInfo> get clients => [
    for (final c in _clients)
      LslBridgeClientInfo(c.address, c.subscribed.length, [
        for (final s in c.published.values) s.stream.description.name,
      ]),
  ];

  @override
  List<String> get published => [
    for (final s in _shared.values)
      if (s.publisher != null) s.stream.description.name,
  ];

  /// This computer's clock, which time stamps sent and received are on:
  /// LSL's when there is LSL, else any steady clock (a relay without LSL
  /// only passes time stamps between clients, each mapped to its clock).
  double _clock() =>
      lsl.supported ? lsl.clock() : DateTime.now().microsecondsSinceEpoch / 1e6;

  void _changed({bool streams = false}) {
    if (streams) {
      final message = _streamsMessage();
      for (final c in _clients) {
        c.socket.add(message);
      }
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  String _streamsMessage() => jsonEncode({
    'type': 'streams',
    'streams': [for (final s in _shared.values) s.stream.toJson()],
    'accepts_publish': acceptsPublish,
  });

  @override
  Future<bool> share(LslStreamDescription stream) async {
    if (_closed) throw StateError('The bridge is closed');
    for (final s in _shared.values) {
      final d = s.inlet?.stream;
      if (d != null && d.uid == stream.uid) return false;
      // An outlet made here for a client: sharing it again would send the
      // client's stream around twice.
      final o = s.outlet?.spec;
      if (o != null && o.name == stream.name && o.sourceId == stream.sourceId) {
        return false;
      }
    }
    // Clock sync, so time stamps are on this computer's clock (which
    // clients map onto theirs).
    final inlet = await lsl.openInlet(
      stream,
      options.copyWith(clockSync: true),
    );
    final id = _nextId++;
    _shared[id] = _Shared.local(
      BridgeStream(
        id,
        inlet.stream,
        inlet.channels,
        inlet.fullXml.isNotEmpty ? inlet.fullXml : inlet.stream.xml,
      ),
      inlet,
    );
    _changed(streams: true);
    return true;
  }

  @override
  Future<void> unshare(LslStreamDescription stream) async {
    final gone = [
      for (final s in _shared.values)
        if (s.inlet?.stream.uid == stream.uid) s,
    ];
    for (final s in gone) {
      _shared.remove(s.id);
      await s.inlet!.close();
    }
    if (gone.isNotEmpty) _changed(streams: true);
  }

  /// Share the streams [client] publishes (a `publish` message), with LSL
  /// outlets here if asked, and tell it which it got.
  Future<void> _publish(_Client client, List<Object?> streams) async {
    final ok = <int>[];
    final ids = <String, int>{};
    final errors = <String, String>{};
    for (final raw in streams) {
      final s = BridgeStream.fromJson((raw! as Map).cast<String, Object?>());
      final d = s.description;
      try {
        if (!acceptsPublish) {
          throw StateError('This bridge does not accept streams');
        }
        if (client.published.containsKey(s.id)) {
          throw StateError('Already published');
        }
        final id = _nextId++;
        final shared = _Shared.published(
          BridgeStream(
            id,
            LslStreamDescription(
              name: d.name,
              type: d.type,
              channelCount: d.channelCount,
              rate: d.rate,
              format: d.format.isString ? LslFormat.string : LslFormat.float32,
              sourceId: d.sourceId,
              hostname: client.address,
              uid: 'published:$id',
            ),
            s.channels,
            '',
          ),
          client,
          s.id,
        );
        if (localOutlets) {
          shared.outlet = await lsl.createOutlet(
            LslOutletSpec(
              name: d.name,
              type: d.type,
              channelCount: d.format.isString ? 1 : d.channelCount,
              rate: d.rate,
              format: d.format.isString ? LslFormat.string : LslFormat.float32,
              sourceId: d.sourceId.isEmpty ? 'bridge:${d.name}' : d.sourceId,
              channels: s.channels,
              desc: {
                'bridge': {'published_by': client.address},
              },
            ),
            outletOptions,
          );
        }
        client.published[s.id] = shared;
        _shared[id] = shared;
        ok.add(s.id);
        ids['${s.id}'] = id;
      } catch (e) {
        errors['${s.id}'] = '$e';
      }
    }
    client.socket.add(
      jsonEncode({
        'type': 'published',
        'ids': ok,
        'shared_ids': ids,
        'errors': errors,
      }),
    );
    if (ok.isNotEmpty) _changed(streams: true);
  }

  Future<void> _unpublish(_Client client, Iterable<int> ids) async {
    var any = false;
    for (final id in [...ids]) {
      final s = client.published.remove(id);
      if (s == null) continue;
      any = true;
      _shared.remove(s.id);
      await s.outlet?.close();
    }
    if (any && !_closed) _changed(streams: true);
  }

  /// Samples of a stream [client] publishes: to the LSL outlet here, and to
  /// the clients that receive it.
  void _samples(_Client client, List<int> message) {
    final bytes = message is Uint8List ? message : Uint8List.fromList(message);
    if (bytes.length < 13) return;
    final data = ByteData.sublistView(bytes);
    final s = client.published[data.getUint32(0, Endian.little)];
    if (s == null) return;
    final n = data.getUint32(4, Endian.little);
    if (n == 0) return;
    received += n;
    final targets = [
      for (final c in _clients)
        if (c.subscribed.contains(s.id)) c,
    ];
    if (targets.isNotEmpty) {
      // The same samples under the id the stream is shared as.
      final frame = Uint8List.fromList(bytes);
      ByteData.sublistView(frame).setUint32(0, s.id, Endian.little);
      for (final c in targets) {
        c.socket.add(frame);
      }
      sent += n * targets.length;
    }
    final outlet = s.outlet;
    if (outlet == null) return;
    final (_, chunk) = decodeSamples(bytes);
    if (chunk.strings != null) {
      final ch = (chunk.strings!.length / chunk.length).round();
      outlet.pushStrings([
        for (var i = 0; i < chunk.length; i++) chunk.strings![i * ch],
      ], chunk.times);
    } else {
      final v = chunk.values!;
      outlet.push(v is Float32List ? v : Float32List.fromList(v), chunk.times);
    }
  }

  void _gone(_Client client) {
    if (!_clients.remove(client)) return;
    _unpublish(client, client.published.keys);
    _changed();
  }

  /// Whether [a] equals [b], taking as long whatever the difference.
  static bool _same(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var d = x.length ^ y.length;
    for (var i = 0; i < x.length; i++) {
      d |= x[i] ^ (i < y.length ? y[i] : 0);
    }
    return d == 0;
  }

  Future<void> _refuse(HttpRequest request) async {
    request.response.statusCode = HttpStatus.forbidden;
    await request.response.close();
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (token.isNotEmpty &&
        !_same(request.uri.queryParameters['token'] ?? '', token)) {
      return _refuse(request);
    }
    // Browsers say where the page is from; other clients send no Origin.
    final origin = request.headers.value('origin');
    if (allowedOrigins.isNotEmpty &&
        origin != null &&
        !allowedOrigins.contains(origin)) {
      return _refuse(request);
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'streams': [for (final s in _shared.values) s.stream.toJson()],
            'accepts_publish': acceptsPublish,
          }),
        );
      await request.response.close();
      return;
    }
    final address =
        request.connectionInfo?.remoteAddress.address ?? 'unknown address';
    final socket = await WebSocketTransformer.upgrade(request);
    final client = _Client(socket, address);
    _clients.add(client);
    socket.add(_streamsMessage());
    _changed();
    socket.listen(
      (message) {
        if (message is! String) {
          _samples(client, message as List<int>);
          return;
        }
        final m = jsonDecode(message) as Map<String, Object?>;
        switch (m['type']) {
          case 'subscribe':
            client.subscribed = {
              for (final id in (m['ids'] as List?) ?? const [])
                (id as num).toInt(),
            };
          case 'ping':
            socket.add(
              jsonEncode({'type': 'pong', 't': m['t'], 'server': _clock()}),
            );
          case 'publish':
            _publish(client, (m['streams'] as List?) ?? const []);
          case 'unpublish':
            _unpublish(client, [
              for (final id in (m['ids'] as List?) ?? const [])
                (id as num).toInt(),
            ]);
        }
      },
      onDone: () => _gone(client),
      onError: (Object _) => _gone(client),
    );
  }

  Future<void> _pull() async {
    if (_pulling || _closed) return;
    _pulling = true;
    final failed = <_Shared>[];
    try {
      for (final s in [..._shared.values]) {
        final inlet = s.inlet;
        if (inlet == null) continue;
        final max = math.max(256, (inlet.stream.rate * 2).ceil());
        try {
          while (true) {
            final c = await inlet.pull(max);
            if (c.length == 0) break;
            final targets = [
              for (final cl in _clients)
                if (cl.subscribed.contains(s.id)) cl,
            ];
            if (targets.isNotEmpty) {
              final frame = encodeSamples(s.id, c, inlet.stream.channelCount);
              for (final cl in targets) {
                cl.socket.add(frame);
              }
              sent += c.length * targets.length;
            }
            if (c.length < max) break;
          }
        } catch (_) {
          // The stream went away; keep serving the others.
          failed.add(s);
        }
      }
    } finally {
      _pulling = false;
    }
    for (final s in failed) {
      await unshare(s.inlet!.stream);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    for (final c in [..._clients]) {
      await _unpublish(c, c.published.keys);
      await c.socket.close();
    }
    await _http.close(force: true);
    for (final s in _shared.values) {
      await s.inlet?.close();
    }
    _shared.clear();
    await _changes.close();
  }
}
