/// Resource limits for a hub and its clients.
///
/// Web-safe: plain data, no `dart:io`. The client reads [maxFrameBytes] to
/// check its own sends; the hub reads all of it.
library;

/// What a hub will accept before it stops being polite.
///
/// The defaults are sized for a lab session or a handful of friends, not for a
/// public service. They exist so that a single misbehaving or malicious peer
/// cannot make the hub allocate without bound — everything else about the
/// hub's safety comes from the fact that only authenticated peers get in.
class WsLimits {
  const WsLimits({
    this.maxFrameBytes = defaultMaxFrameBytes,
    this.handshakeTimeout = const Duration(seconds: 5),
    this.pingInterval = const Duration(seconds: 20),
    this.maxConnections = 64,
    this.maxEndpointsPerConnection = 32,
    this.maxLiveQueriesPerConnection = 32,
    this.maxPeers = 256,
  });

  /// 1 MiB. Comfortably above any coordination message or realistic sample —
  /// a 1024-channel float64 sample is 8206 bytes — and small enough that a
  /// rejected frame costs nothing.
  static const int defaultMaxFrameBytes = 1024 * 1024;

  /// Largest single WebSocket frame, in bytes.
  ///
  /// On the hub this is handed to `WebSocketTransformer.upgrade`, which
  /// rejects at the frame's length header before any payload is buffered. On
  /// the client it is checked before a send, so an over-size frame fails
  /// locally and loudly instead of getting the connection killed remotely.
  final int maxFrameBytes;

  /// How long a connection may stay unauthenticated before it is dropped.
  final Duration handshakeTimeout;

  /// WebSocket ping interval. Without this a half-open socket holds its
  /// endpoint ids, slot and routes until the OS notices, which may be never.
  final Duration pingInterval;

  /// Concurrent connections, authenticated or not.
  final int maxConnections;

  /// Endpoints one connection may register. A node holds one for its
  /// coordination stream plus one per data stream.
  final int maxEndpointsPerConnection;

  /// Continuous queries one connection may keep open.
  final int maxLiveQueriesPerConnection;

  /// Registered endpoints across the whole hub. Also bounds slot allocation.
  final int maxPeers;

  WsLimits copyWith({
    int? maxFrameBytes,
    Duration? handshakeTimeout,
    Duration? pingInterval,
    int? maxConnections,
    int? maxEndpointsPerConnection,
    int? maxLiveQueriesPerConnection,
    int? maxPeers,
  }) => WsLimits(
    maxFrameBytes: maxFrameBytes ?? this.maxFrameBytes,
    handshakeTimeout: handshakeTimeout ?? this.handshakeTimeout,
    pingInterval: pingInterval ?? this.pingInterval,
    maxConnections: maxConnections ?? this.maxConnections,
    maxEndpointsPerConnection:
        maxEndpointsPerConnection ?? this.maxEndpointsPerConnection,
    maxLiveQueriesPerConnection:
        maxLiveQueriesPerConnection ?? this.maxLiveQueriesPerConnection,
    maxPeers: maxPeers ?? this.maxPeers,
  );
}

/// Thrown when a frame this node is about to send exceeds
/// [WsLimits.maxFrameBytes].
///
/// Thrown rather than swallowed: for a data stream, silently dropping samples
/// looks like packet loss and is far harder to diagnose than a failed send.
class WsFrameTooLargeException implements Exception {
  const WsFrameTooLargeException({required this.bytes, required this.limit});

  final int bytes;
  final int limit;

  @override
  String toString() =>
      'WsFrameTooLargeException: frame of $bytes bytes exceeds the '
      '$limit byte limit. Raise maxFrameBytes on both the hub and every '
      'client, or reduce the stream\'s channel count or chunk size.';
}

/// Thrown when the hub refuses or ends a connection.
///
/// Carries the close code so a caller can tell "wrong secret" from "the
/// session is over" from an ordinary disconnect.
class HubConnectionException implements Exception {
  const HubConnectionException(this.code, this.reason);

  /// A [HubCloseCode], or a standard WebSocket close code.
  final int? code;
  final String? reason;

  @override
  String toString() =>
      'HubConnectionException($code): ${reason ?? 'no reason'}';
}
