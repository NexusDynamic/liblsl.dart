/// The WebSocket relay hub.
///
/// **Server-side only.** This library imports `dart:io`, so it is deliberately
/// not exported from `package:peer_coordinator/peer_coordinator.dart` — that
/// barrel has to stay web-safe. Browser clients connect *to* a hub; they never
/// host one.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/src/websocket/ws_protocol.dart';

/// One connected client.
class _Connection {
  _Connection(this.id, this.socket);

  final String id;
  final WebSocket socket;

  /// Endpoints this connection publishes. One node holds several: its
  /// coordination stream plus a stream per data stream.
  final Set<String> endpointIds = {};

  /// Continuous queries this connection has registered, by query id.
  final Map<int, DiscoveryQuery> liveQueries = {};

  /// Endpoints already reported for each live query, so results only fire on
  /// growth — matching LSL, where a resolve that finds nothing is silent.
  final Map<int, Set<String>> reported = {};

  void send(Object data) {
    if (socket.readyState == WebSocket.open) socket.add(data);
  }
}

/// A role-blind relay.
///
/// The hub holds a [PeerRegistry] and a [RelayRouting] table and nothing else.
/// It does not know what a coordinator is, never inspects a coordination
/// message, and never parses a data sample — election, membership and stream
/// lifecycle all stay client-side, exactly as they are over LSL.
///
/// That is what keeps the relay cheap: a data frame costs one two-byte
/// in-place write and a forward per subscriber.
class CoordinationHub {
  CoordinationHub._(this._server);

  final HttpServer _server;
  final PeerRegistry _registry = PeerRegistry();
  final RelayRouting _routing = RelayRouting();
  final Map<String, _Connection> _connections = {};

  /// endpointId -> slot, and back.
  final Map<String, int> _slotByEndpoint = {};
  final Map<int, String> _endpointBySlot = {};

  int _nextConnectionId = 0;
  int _nextSlot = 1; // 0 is reserved as "unassigned"

  /// The port the hub is listening on.
  int get port => _server.port;

  /// Number of currently connected clients.
  int get connectionCount => _connections.length;

  /// Number of registered endpoints across all clients.
  int get endpointCount => _registry.length;

  /// Starts a hub.
  ///
  /// Pass `port: 0` (the default) for an ephemeral port, so tests can run in
  /// parallel without colliding; read [port] afterwards.
  static Future<CoordinationHub> serve({
    InternetAddress? address,
    int port = 0,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    final hub = CoordinationHub._(server);
    unawaited(hub._accept());
    logger.info('Coordination hub listening on port ${hub.port}');
    return hub;
  }

  Future<void> _accept() async {
    await for (final request in _server) {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Expected a WebSocket upgrade request');
        await request.response.close();
        continue;
      }
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _onConnected(socket);
      } catch (e) {
        logger.warning('Failed to upgrade connection: $e');
      }
    }
  }

  void _onConnected(WebSocket socket) {
    final connection = _Connection('conn-${_nextConnectionId++}', socket);
    _connections[connection.id] = connection;
    logger.fine('Hub: ${connection.id} connected');

    socket.listen(
      (Object? data) => _onData(connection, data),
      onDone: () => _onDisconnected(connection),
      onError: (Object e) {
        logger.warning('Hub: ${connection.id} socket error: $e');
        _onDisconnected(connection);
      },
      cancelOnError: true,
    );
  }

  void _onData(_Connection connection, Object? data) {
    try {
      if (data is String) {
        _onControl(connection, WsFrame.decode(data));
      } else if (data is List<int>) {
        _relaySample(
          connection,
          data is Uint8List ? data : Uint8List.fromList(data),
        );
      }
    } catch (e) {
      // One malformed frame must not take down the hub for everyone else.
      logger.warning('Hub: bad frame from ${connection.id}: $e');
    }
  }

  void _onControl(_Connection connection, WsFrame frame) {
    switch (frame.type) {
      case WsControl.hello:
      case WsControl.update:
        _register(
          connection,
          PeerDescriptor.fromJson(
            frame.payload['peer'] as Map<String, dynamic>,
          ),
          publish: frame.payload['publish'] as bool? ?? true,
        );

      case WsControl.query:
        final qid = frame.payload['qid'] as int;
        final query = DiscoveryQuery.fromJson(
          frame.payload['query'] as Map<String, dynamic>,
        );
        final continuous = frame.payload['continuous'] as bool? ?? false;
        if (continuous) {
          connection.liveQueries[qid] = query;
          connection.reported[qid] = {};
        }
        _answerQuery(connection, qid, query, remember: continuous);

      case WsControl.unquery:
        final qid = frame.payload['qid'] as int;
        connection.liveQueries.remove(qid);
        connection.reported.remove(qid);

      case WsControl.subscribe:
        final subscriber = frame.payload['subscriber'] as String;
        for (final producer in (frame.payload['from'] as List).cast<String>()) {
          _routing.subscribe(
            streamName: frame.payload['stream'] as String,
            producerEndpointId: producer,
            subscriberEndpointId: subscriber,
          );
        }

      case WsControl.message:
        _relayMessage(connection, frame);

      case WsControl.welcome:
      case WsControl.queryResult:
      case WsControl.peerGone:
        logger.warning(
          'Hub: ignoring server-only frame ${frame.type.name} from '
          '${connection.id}',
        );
    }
  }

  /// Registers an endpoint.
  ///
  /// [publish] separates two things that look alike but are not: every
  /// endpoint needs a routing identity so the hub can deliver *to* it, but
  /// only an endpoint that actually produces should be discoverable *as* a
  /// publisher. A consumer-only stream (the coordinator's, under
  /// `sendParticipantsReceiveCoordinator`) registers with publish: false — it
  /// must be reachable, but it must not show up in a publisher query.
  void _register(
    _Connection connection,
    PeerDescriptor descriptor, {
    required bool publish,
  }) {
    final endpointId = descriptor.endpointId;
    final slot = _slotByEndpoint.putIfAbsent(endpointId, () {
      final assigned = _nextSlot++;
      _endpointBySlot[assigned] = endpointId;
      return assigned;
    });
    connection.endpointIds.add(endpointId);
    if (publish) {
      _registry.attach(descriptor);
    } else {
      // Reachable, but deliberately absent from discovery.
      _registry.detach(endpointId);
    }

    connection.send(
      WsFrame(WsControl.welcome, {
        'connId': connection.id,
        'endpointId': endpointId,
        'slot': slot,
        'hubTimeMicros': DateTime.now().microsecondsSinceEpoch,
      }).encode(),
    );

    // A new or changed peer may satisfy someone's outstanding query.
    _refreshLiveQueries();
  }

  void _answerQuery(
    _Connection connection,
    int qid,
    DiscoveryQuery query, {
    required bool remember,
  }) {
    final matches = _registry.match(query);
    if (matches.isEmpty) return; // silent, as with an LSL resolve

    if (remember) {
      final already = connection.reported[qid]!;
      final fresh = matches
          .where((m) => !already.contains(m.endpointId))
          .toList(growable: false);
      if (fresh.isEmpty) return; // only report growth
      already.addAll(fresh.map((m) => m.endpointId));
    }

    connection.send(
      WsFrame(WsControl.queryResult, {
        'qid': qid,
        'peers': [
          for (final peer in matches)
            {'slot': _slotByEndpoint[peer.endpointId], 'peer': peer.toJson()},
        ],
      }).encode(),
    );
  }

  void _refreshLiveQueries() {
    for (final connection in _connections.values.toList(growable: false)) {
      for (final entry in connection.liveQueries.entries.toList(
        growable: false,
      )) {
        _answerQuery(connection, entry.key, entry.value, remember: true);
      }
    }
  }

  void _relayMessage(_Connection connection, WsFrame frame) {
    final streamName = frame.payload['stream'] as String;
    final from = frame.payload['from'] as String;
    if (!connection.endpointIds.contains(from)) {
      // Refuse to relay on behalf of an endpoint this connection does not own.
      logger.warning('Hub: ${connection.id} tried to send as $from');
      return;
    }
    final encoded = WsFrame(WsControl.message, {
      'stream': streamName,
      'from': from,
      'payload': frame.payload['payload'],
    }).encode();

    for (final subscriber in _routing.subscribersFor(
      streamName: streamName,
      producerEndpointId: from,
    )) {
      _connectionForEndpoint(subscriber)?.send(encoded);
    }
  }

  void _relaySample(_Connection connection, Uint8List frame) {
    if (!WsSampleFrame.isSample(frame)) return;

    // The sender declares which of its endpoints is publishing; the hub
    // decides whether to believe it, then stamps the authoritative slot.
    final declaredSlot = WsSampleFrame.streamSlotOf(frame);
    final producer = _endpointBySlot[declaredSlot];
    if (producer == null || !connection.endpointIds.contains(producer)) {
      logger.warning(
        'Hub: ${connection.id} published as slot $declaredSlot, which it does '
        'not own',
      );
      return;
    }
    WsSampleFrame.rewriteSourceSlot(frame, declaredSlot);

    final streamName = _registry[producer]?.streamName;
    if (streamName == null) return;

    // The payload is never parsed: one two-byte write above, then forward the
    // same buffer to each subscriber.
    for (final subscriber in _routing.subscribersFor(
      streamName: streamName,
      producerEndpointId: producer,
    )) {
      _connectionForEndpoint(subscriber)?.send(frame);
    }
  }

  _Connection? _connectionForEndpoint(String endpointId) {
    for (final connection in _connections.values) {
      if (connection.endpointIds.contains(endpointId)) return connection;
    }
    return null;
  }

  void _onDisconnected(_Connection connection) {
    if (_connections.remove(connection.id) == null) return;
    logger.fine('Hub: ${connection.id} disconnected');

    for (final endpointId in connection.endpointIds) {
      final descriptor = _registry.detach(endpointId);
      _routing.removeEndpoint(endpointId);
      final slot = _slotByEndpoint.remove(endpointId);
      if (slot != null) _endpointBySlot.remove(slot);

      if (descriptor == null) continue;
      // Tell everyone still connected. The hub does not know or care whether
      // this peer was the coordinator — clients decide what a departure means.
      final notice = WsFrame(WsControl.peerGone, {
        'endpointId': endpointId,
        'nodeUId': descriptor.nodeUId,
      }).encode();
      for (final other in _connections.values) {
        other.send(notice);
      }
    }

    // A departure can only shrink the matching set, and live queries only
    // report growth, so previously-reported entries are cleared to allow a
    // rejoining peer to be reported again.
    for (final other in _connections.values) {
      for (final reported in other.reported.values) {
        reported.removeAll(
          connection.endpointIds.where(reported.contains).toList(),
        );
      }
    }
  }

  /// Stops the hub and closes every connection.
  Future<void> close() async {
    for (final connection in _connections.values.toList(growable: false)) {
      await connection.socket.close();
    }
    _connections.clear();
    _routing.clear();
    _registry.dispose();
    await _server.close(force: true);
    logger.info('Coordination hub stopped');
  }
}
