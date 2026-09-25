import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../lsl.dart';
import 'protocol.dart';
import 'server.dart';

bool get supported => lsl.supported;

Future<LslBridgeServer> start(
  List<LslStreamDescription> streams, {
  required int port,
  required String token,
  required LslInletOptions options,
}) async {
  final inlets = <LslInlet>[];
  try {
    for (final s in streams) {
      // Clock sync, so time stamps are on this computer's clock (which
      // clients map onto theirs).
      inlets.add(await lsl.openInlet(s, options.copyWith(clockSync: true)));
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    return _Server(server, inlets, token);
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

  _Server(this._http, this._inlets, this.token)
    : _shared = [
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
      }),
    );
    socket.listen(
      (message) {
        if (message is! String) return;
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
        }
      },
      onDone: () => _clients.remove(client),
      onError: (Object _) => _clients.remove(client),
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
    for (final c in _clients) {
      await c.socket.close();
    }
    await _http.close(force: true);
    for (final i in _inlets) {
      await i.close();
    }
  }
}
