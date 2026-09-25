/// A loopback-only control surface for a running hub.
///
/// Server-side only.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/hub.dart';

/// Session control over HTTP, on its own port.
///
/// A separate server rather than a path on the hub's own port, because the hub
/// is meant to sit behind a reverse proxy: anything sharing that port is one
/// proxy misconfiguration away from being public, whereas a second port that is
/// never proxied — and by default bound to loopback — cannot be reached from
/// outside the host at all. In the compose stack it is simply not published.
///
/// Endpoints, all requiring `Authorization: Bearer <token>`:
///
/// * `GET  /status` — session name, epoch, status, peer and connection counts
/// * `POST /end`    — end the session; everyone is disconnected
/// * `POST /open`   — reopen with a secret: `{"secret": "...", "ttlSeconds": 0}`
/// * `POST /revoke` — bar one node: `{"nodeUId": "..."}`
class HubAdminServer {
  HubAdminServer._(this._server, this._hub, this._token);

  final HttpServer _server;
  final CoordinationHub _hub;
  final String _token;

  int get port => _server.port;

  /// Starts the admin server.
  ///
  /// [token] is required and compared in constant time. [address] defaults to
  /// loopback and should stay there.
  static Future<HubAdminServer> serve({
    required CoordinationHub hub,
    required String token,
    InternetAddress? address,
    int port = 0,
  }) async {
    if (token.isEmpty) {
      throw ArgumentError.value('<redacted>', 'token', 'must not be empty');
    }
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final admin = HubAdminServer._(server, hub, token);
    unawaited(admin._accept());
    logger.info(
      'Hub admin listening on http://${server.address.host}:'
      '${server.port}',
    );
    return admin;
  }

  Future<void> _accept() async {
    await for (final request in _server) {
      try {
        await _handle(request);
      } catch (e) {
        logger.warning('Admin: request failed: $e');
        await _respond(request, HttpStatus.internalServerError, {
          'error': '$e',
        });
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final offered = header.startsWith('Bearer ') ? header.substring(7) : '';
    if (!HubCredentials.secureEquals(offered, _token)) {
      logger.warning('Admin: rejected an unauthorised request');
      await _respond(request, HttpStatus.unauthorized, {
        'error': 'unauthorized',
      });
      return;
    }

    final path = request.uri.path;
    if (request.method == 'GET' && path == '/status') {
      await _respond(request, HttpStatus.ok, _status());
      return;
    }
    if (request.method != 'POST') {
      await _respond(request, HttpStatus.methodNotAllowed, {
        'error': 'use GET /status, POST /end, /open or /revoke',
      });
      return;
    }

    final body = await _readJson(request);
    switch (path) {
      case '/end':
        await _hub.endSession(
          reason: body['reason'] as String? ?? 'ended by an operator',
        );
        await _respond(request, HttpStatus.ok, _status());
      case '/open':
        final secret = body['secret'] as String?;
        if (secret == null || secret.isEmpty) {
          await _respond(request, HttpStatus.badRequest, {
            'error':
                'open requires a "secret" — reopening means saying which '
                'credential admits the next cohort',
          });
          return;
        }
        final ttl = (body['ttlSeconds'] as num?)?.toInt();
        _hub.openSession(
          secret: secret,
          ttl: ttl == null || ttl <= 0 ? null : Duration(seconds: ttl),
        );
        await _respond(request, HttpStatus.ok, _status());
      case '/revoke':
        final nodeUId = body['nodeUId'] as String?;
        if (nodeUId == null || nodeUId.isEmpty) {
          await _respond(request, HttpStatus.badRequest, {
            'error': 'revoke requires a "nodeUId"',
          });
          return;
        }
        await _hub.revoke(nodeUId);
        await _respond(request, HttpStatus.ok, _status());
      default:
        await _respond(request, HttpStatus.notFound, {'error': 'no such path'});
    }
  }

  Map<String, Object?> _status() => {
    'session': _hub.sessionName,
    'epoch': _hub.epoch,
    'status': _hub.status.name,
    'connections': _hub.connectionCount,
    'pending': _hub.pendingCount,
    'endpoints': _hub.endpointCount,
  };

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  Future<void> _respond(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
