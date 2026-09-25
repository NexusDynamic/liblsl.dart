import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../lsl.dart';
import 'protocol.dart';
import 'server.dart';

bool get supported => lsl.supported;

Future<LslBridgeServer> start(
  List<LslStreamDescription> streams, {
  required int port,
  required String token,
  required bool acceptPublish,
  required LslInletOptions options,
  required LslOutletOptions outletOptions,
}) async {
  final inlets = <LslInlet>[];
  try {
    for (final s in streams) {
      // Clock sync, so time stamps are on this computer's clock (which
      // clients map onto theirs).
      inlets.add(await lsl.openInlet(s, options.copyWith(clockSync: true)));
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    return _Server(server, inlets, token, acceptPublish, outletOptions);
  } catch (_) {
    for (final i in inlets) {
      await i.close();
    }
    rethrow;
  }
}

class _Client {
  final WebSocket socket;
  Set<int> subscribed = {};

  /// Streams this client publishes here, by its id.
  final Map<int, LslOutlet> outlets = {};
  _Client(this.socket);
}

class _Server implements LslBridgeServer {
  final HttpServer _http;
  final List<LslInlet> _inlets;
  final List<BridgeStream> _shared;
  final String token;
  final List<_Client> _clients = [];
  late final Timer _timer;
  bool _pulling = false;
  bool _closed = false;
  @override
  int sent = 0;

  @override
  final bool acceptsPublish;
  final LslOutletOptions outletOptions;
  @override
  int received = 0;

  _Server(
    this._http,
    this._inlets,
    this.token,
    this.acceptsPublish,
    this.outletOptions,
  ) : _shared = [
        for (final (k, i) in _inlets.indexed)
          BridgeStream(
            k + 1,
            i.stream,
            i.channels,
            i.fullXml.isNotEmpty ? i.fullXml : i.stream.xml,
          ),
      ] {
    _http.listen(_onRequest);
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _pull());
  }

  @override
  int get port => _http.port;

  @override
  List<LslStreamDescription> get streams => [for (final i in _inlets) i.stream];

  @override
  int get clientCount => _clients.length;

  @override
  List<String> get published => [
    for (final c in _clients)
      for (final o in c.outlets.values) o.spec.name,
  ];

  /// Create outlets for the streams [client] publishes (a `publish`
  /// message), and tell it which it got.
  Future<void> _publish(_Client client, List<Object?> streams) async {
    final ok = <int>[];
    final errors = <String, String>{};
    for (final raw in streams) {
      final s = BridgeStream.fromJson((raw! as Map).cast<String, Object?>());
      final d = s.description;
      try {
        if (!acceptsPublish) {
          throw StateError('This bridge does not accept streams');
        }
        if (client.outlets.containsKey(s.id)) {
          throw StateError('Already published');
        }
        client.outlets[s.id] = await lsl.createOutlet(
          LslOutletSpec(
            name: d.name,
            type: d.type,
            channelCount: d.format.isString ? 1 : d.channelCount,
            rate: d.rate,
            format: d.format.isString ? LslFormat.string : LslFormat.float32,
            sourceId: d.sourceId.isEmpty ? 'bridge:${d.name}' : d.sourceId,
            channels: s.channels,
            desc: {
              'bridge': {'published_by': '${client.hashCode}'},
            },
          ),
          outletOptions,
        );
        ok.add(s.id);
      } catch (e) {
        errors['${s.id}'] = '$e';
      }
    }
    client.socket.add(
      jsonEncode({'type': 'published', 'ids': ok, 'errors': errors}),
    );
  }

  Future<void> _unpublish(_Client client, Iterable<int> ids) async {
    for (final id in [...ids]) {
      await client.outlets.remove(id)?.close();
    }
  }

  /// Samples of a stream [client] publishes.
  void _samples(_Client client, List<int> bytes) {
    final (id, chunk) = decodeSamples(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    final outlet = client.outlets[id];
    if (outlet == null || chunk.length == 0) return;
    received += chunk.length;
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
    _clients.remove(client);
    _unpublish(client, client.outlets.keys);
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (token.isNotEmpty && request.uri.queryParameters['token'] != token) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'streams': [for (final s in _shared) s.toJson()],
          }),
        );
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final client = _Client(socket);
    _clients.add(client);
    socket.add(
      jsonEncode({
        'type': 'streams',
        'streams': [for (final s in _shared) s.toJson()],
        'accepts_publish': acceptsPublish,
      }),
    );
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
              jsonEncode({'type': 'pong', 't': m['t'], 'server': lsl.clock()}),
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
    try {
      for (final (k, inlet) in _inlets.indexed) {
        final id = k + 1;
        final max = math.max(256, (inlet.stream.rate * 2).ceil());
        while (true) {
          final c = await inlet.pull(max);
          if (c.length == 0) break;
          final targets = [
            for (final cl in _clients)
              if (cl.subscribed.contains(id)) cl,
          ];
          if (targets.isNotEmpty) {
            final frame = encodeSamples(id, c, inlet.stream.channelCount);
            for (final cl in targets) {
              cl.socket.add(frame);
            }
            sent += c.length * targets.length;
          }
          if (c.length < max) break;
        }
      }
    } catch (_) {
      // A stream went away; keep serving the others.
    } finally {
      _pulling = false;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    for (final c in [..._clients]) {
      await _unpublish(c, c.outlets.keys);
      await c.socket.close();
    }
    await _http.close(force: true);
    for (final i in _inlets) {
      await i.close();
    }
  }
}
