import 'dart:async';

import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/src/websocket/ws_connection.dart';
import 'package:peer_coordinator/src/websocket/ws_discovery.dart';
import 'package:peer_coordinator/src/websocket/ws_stream.dart';

/// Configuration for the WebSocket transport.
class WebSocketTransportConfig implements ITransportConfig {
  WebSocketTransportConfig({
    required this.hubUri,
    this.connectTimeout = const Duration(seconds: 10),
  });

  /// Where the relay hub is listening, e.g. `ws://127.0.0.1:8080`.
  final Uri hubUri;

  final Duration connectTimeout;

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
  WebSocketTransportConfig copyWith({Uri? hubUri, Duration? connectTimeout}) =>
      WebSocketTransportConfig(
        hubUri: hubUri ?? this.hubUri,
        connectTimeout: connectTimeout ?? this.connectTimeout,
      );

  @override
  Map<String, dynamic> toMap() => {
    'type': 'websocket',
    'hubUri': hubUri.toString(),
    'connectTimeoutMs': connectTimeout.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebSocketTransportConfig &&
          other.hubUri == hubUri &&
          other.connectTimeout == connectTimeout;

  @override
  int get hashCode => Object.hash(hubUri, connectTimeout);
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
    implements ITransport<WebSocketTransportConfig>, IResourceManager {
  WebSocketTransport(this.config)
    : _connection = WsConnection(config.hubUri),
      super(id: 'websocket_transport');

  @override
  final WebSocketTransportConfig config;

  final WsConnection _connection;

  /// The socket this node holds to the hub.
  WsConnection get connection => _connection;

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
    await _connection.connect(timeout: config.connectTimeout);
    _initialized = true;
  }

  @override
  NetworkStreamFactory get streamFactory => WsNetworkStreamFactory(_connection);

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
