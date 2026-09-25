/// A hub plus the credentials to reach it, for tests and benchmarks.
///
/// Server-side only: imports `dart:io` by way of the hub.
library;

import 'dart:async';

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/src/websocket/ws_connection.dart';
import 'package:peer_coordinator/src/websocket/ws_transport.dart';

/// A running hub and everything a client needs to join it.
///
/// Exists because a hub now requires credentials and every client has to
/// present the matching ones — which is three lines of setup repeated across
/// every WebSocket test, and three lines that must agree.
class TestHub {
  TestHub(this.hub, this.credentials);

  final CoordinationHub hub;
  final HubCredentials credentials;

  Uri get uri => hub.uri;

  /// A transport config pointing at this hub with the right credentials.
  WebSocketTransportConfig transportConfig({
    Duration connectTimeout = const Duration(seconds: 10),
    int maxFrameBytes = WsLimits.defaultMaxFrameBytes,
  }) => WebSocketTransportConfig(
    hubUri: uri,
    credentials: credentials,
    connectTimeout: connectTimeout,
    maxFrameBytes: maxFrameBytes,
  );

  /// A raw connection to this hub, already authenticated as [nodeUId].
  ///
  /// For tests that drive the wire protocol directly rather than through a
  /// session.
  Future<WsConnection> connect(
    String nodeUId, {
    int maxFrameBytes = WsLimits.defaultMaxFrameBytes,
  }) async {
    final connection = WsConnection(
      uri,
      credentials: credentials,
      maxFrameBytes: maxFrameBytes,
    );
    await connection.connect(nodeUId: nodeUId);
    return connection;
  }

  Future<void> close() => hub.close();
}

/// Starts a hub on an ephemeral port with a fixed, throwaway secret.
///
/// The secret is a constant on purpose: these hubs live on loopback for the
/// length of one test, and a readable value makes a failing handshake easy to
/// reason about. Never use it for anything reachable.
Future<TestHub> startTestHub({
  String session = 'test_session',
  String secret = 'test-secret-not-for-real-use',
  WsLimits limits = const WsLimits(),
  Duration? sessionTtl,
}) async {
  final credentials = HubCredentials(session: session, secret: secret);
  final hub = await CoordinationHub.serve(
    credentials: credentials,
    limits: limits,
    sessionTtl: sessionTtl,
  );
  return TestHub(hub, credentials);
}
