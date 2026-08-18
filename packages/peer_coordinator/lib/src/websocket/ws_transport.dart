import 'dart:async';

import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/src/websocket/ws_auth.dart';
import 'package:peer_coordinator/src/websocket/ws_connection.dart';
import 'package:peer_coordinator/src/websocket/ws_limits.dart';
import 'package:peer_coordinator/src/websocket/ws_discovery.dart';
import 'package:peer_coordinator/src/websocket/ws_stream.dart';

/// Configuration for the WebSocket transport.
class WebSocketTransportConfig implements ITransportConfig {
  WebSocketTransportConfig({
    required this.hubUri,
    required this.credentials,
    this.connectTimeout = const Duration(seconds: 10),
    this.maxFrameBytes = WsLimits.defaultMaxFrameBytes,
  });

  /// Where the relay hub is listening, e.g. `ws://127.0.0.1:8080`.
  ///
  /// Use `wss://` for anything off the local machine. The hub never terminates
  /// TLS itself — see `deploy/` for the reverse-proxy stack that does.
  final Uri hubUri;

  /// The session name and shared secret the hub admits peers with.
  ///
  /// Required, not optional: a hub does not accept anonymous peers, so a config
  /// without a credential could only ever fail to connect.
  final HubCredentials credentials;

  final Duration connectTimeout;

  /// Largest frame this node will send, in bytes.
  ///
  /// Must be no larger than the hub's own limit, or the hub will close the
  /// connection on a frame this node considered acceptable.
  final int maxFrameBytes;

  @override
  String get id => 'websocket_transport_config';

  @override
  String get name => 'WebSocket Transport Configuration';

  @override
  String get description => 'Coordination over a WebSocket relay hub';

  @override
  ITransport createTransport() => WebSocketTransport(this);

  @override
  bool validate({bool throwOnError = false}) {
    if (maxFrameBytes < 1024) {
      if (throwOnError) {
        throw ArgumentError.value(
          maxFrameBytes,
          'maxFrameBytes',
          'must leave room for a coordination message (at least 1024)',
        );
      }
      return false;
    }
    if (hubUri.scheme != 'ws' && hubUri.scheme != 'wss') {
      if (throwOnError) {
        throw ArgumentError.value(
          hubUri.toString(),
          'hubUri',
          'must use the ws:// or wss:// scheme',
        );
      }
      return false;
    }
    return true;
  }

  @override
  WebSocketTransportConfig copyWith({
    Uri? hubUri,
    HubCredentials? credentials,
    Duration? connectTimeout,
    int? maxFrameBytes,
  }) => WebSocketTransportConfig(
    hubUri: hubUri ?? this.hubUri,
    credentials: credentials ?? this.credentials,
    connectTimeout: connectTimeout ?? this.connectTimeout,
    maxFrameBytes: maxFrameBytes ?? this.maxFrameBytes,
  );

  /// Diagnostics only, and deliberately without the secret.
  ///
  /// This ends up in logs and error reports. The session name is useful there;
  /// the credential that admits a peer to it is not.
  @override
  Map<String, dynamic> toMap() => {
    'type': 'websocket',
    'hubUri': hubUri.toString(),
    'session': credentials.session,
    'connectTimeoutMs': connectTimeout.inMilliseconds,
    'maxFrameBytes': maxFrameBytes,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebSocketTransportConfig &&
          other.hubUri == hubUri &&
          other.credentials.session == credentials.session &&
          other.credentials.secret == credentials.secret &&
          other.connectTimeout == connectTimeout &&
          other.maxFrameBytes == maxFrameBytes;

  @override
  int get hashCode => Object.hash(
    hubUri,
    credentials.session,
    credentials.secret,
    connectTimeout,
    maxFrameBytes,
  );
}

/// Coordination over a WebSocket relay hub.
///
/// Works on the VM and in the browser: `package:web_socket_channel` presents
/// one API over both, and nothing here touches `dart:io`. Run the hub with
/// `package:peer_coordinator/hub.dart` (server-side) or
/// `dart run peer_coordinator:hub`.
///
/// Every stream on a node shares one socket; endpoints are demultiplexed by
/// the hub-assigned slot carried in each frame.
class WebSocketTransport extends ManagedResource
    implements
        ITransport<WebSocketTransportConfig>,
        IAuthenticatedTransport,
        IResourceManager {
  WebSocketTransport(this.config)
    : _connection = WsConnection(
        config.hubUri,
        credentials: config.credentials,
        maxFrameBytes: config.maxFrameBytes,
      ),
      super(id: 'websocket_transport');

  @override
  final WebSocketTransportConfig config;

  final WsConnection _connection;

  String? _localNodeUId;

  /// Set by [PeerSession] before [initialize].
  ///
  /// The hub ties every endpoint this connection claims to the node named here,
  /// so it has to be known before the socket authenticates.
  @override
  set localNodeUId(String nodeUId) => _localNodeUId = nodeUId;

  /// The socket this node holds to the hub.
  WsConnection get connection => _connection;

  /// Peer clock offsets for this process.
  ///
  /// Non-null here and nowhere else: LSL has native per-inlet corrections and
  /// the in-memory transport's peers share a clock, but two WebSocket peers
  /// read monotonic clocks with unrelated epochs, so the difference has to be
  /// estimated. Owned by the transport rather than by a stream because it
  /// describes the peer *process* — every stream on this socket reads the same
  /// table. `ClockSyncService`, driven by the coordination controller, fills it.
  @override
  final PeerClockOffsets clockOffsets = PeerClockOffsets();

  final Map<String, IResource> _resources = {};
  bool _initialized = false;

  @override
  String get name => 'WebSocket Transport';

  @override
  String get description => 'Coordination over a WebSocket relay hub';

  @override
  bool get initialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    config.validate(throwOnError: true);
    final nodeUId = _localNodeUId;
    if (nodeUId == null) {
      throw StateError(
        'WebSocketTransport has no node identity. It is set by PeerSession '
        'before initialize(); a transport driven directly must set '
        'localNodeUId first.',
      );
    }
    await _connection.connect(timeout: config.connectTimeout, nodeUId: nodeUId);
    _initialized = true;
  }

  @override
  NetworkStreamFactory get streamFactory =>
      WsNetworkStreamFactory(_connection, clockOffsets: clockOffsets);

  @override
  Future<IDiscovery> createDiscovery({
    required NetworkStreamConfig streamConfig,
    required CoordinationConfig coordinationConfig,
    required String id,
  }) async {
    final discovery = WsDiscovery(
      connection: _connection,
      coordinationConfig: coordinationConfig,
      id: id,
    );
    await discovery.create();
    manageResource(discovery);
    return discovery;
  }

  @override
  void manageResource<R extends IResource>(R resource) {
    _resources[resource.id] = resource;
  }

  @override
  Future<R> releaseResource<R extends IResource>(String resourceId) async {
    final resource = _resources.remove(resourceId);
    if (resource == null) {
      throw ArgumentError('Resource with id $resourceId not found');
    }
    return resource as R;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    final pending = <Future<void>>[];
    for (final resource in _resources.values) {
      if (!resource.disposed) {
        final result = resource.dispose();
        if (result is Future<void>) pending.add(result);
      }
    }
    await Future.wait(pending);
    _resources.clear();
    await _connection.close();
    await super.dispose();
  }
}
