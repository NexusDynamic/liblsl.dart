/// The WebSocket relay hub.
///
/// **Server-side only.** This library imports `dart:io`, so it is deliberately
/// not exported from `package:peer_coordinator/peer_coordinator.dart` — that
/// barrel has to stay web-safe. Browser clients connect *to* a hub; they never
/// host one.
///
/// ## Security posture
///
/// This is research software. Every peer that authenticates is inside one trust
/// domain: it can see every other peer, and subscribe to every stream. The
/// secret is the whole boundary, so hand it only to people you would let run
/// code in your session, and put the hub behind a reverse proxy rather than on
/// a public interface — see `deploy/` for a compose stack that does that.
///
/// What the hub *does* guarantee:
///
/// * nothing happens on a connection before it proves knowledge of the shared
///   secret, and an unauthenticated socket holds a nonce and a timer, no more;
/// * a peer cannot publish, relay or signal under another peer's identity,
///   because every endpoint id is checked against the `nodeUId` it
///   authenticated as;
/// * no single frame can make the hub allocate without bound;
/// * ending a session disconnects everyone and invalidates every outstanding
///   credential, so participants cannot rejoin afterwards.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/src/websocket/ws_auth.dart';
import 'package:peer_coordinator/src/websocket/ws_limits.dart';
import 'package:peer_coordinator/src/websocket/ws_protocol.dart';

export 'package:peer_coordinator/src/websocket/ws_auth.dart'
    show HubCloseCode, HubCredentials;
export 'package:peer_coordinator/src/hub/hub_admin.dart' show HubAdminServer;
export 'package:peer_coordinator/src/websocket/ws_limits.dart' show WsLimits;

/// Whether a hub is currently admitting peers.
enum HubSessionStatus { open, closed }

/// A socket that has connected but not yet proved anything.
///
/// Deliberately tiny. Everything an unauthenticated peer could make the hub
/// allocate lives in this class, and it is one nonce and one timer.
class _Pending {
  _Pending(this.socket, this.nonce, this.deadline);

  final WebSocket socket;

  /// Single-use challenge. Cleared the moment an `auth` frame is processed, so
  /// a captured proof cannot be replayed even on this connection.
  String? nonce;

  final Timer deadline;
}

/// One authenticated client.
class _Connection {
  _Connection(this.id, this.socket, this.nodeUId);

  final String id;
  final WebSocket socket;

  /// The identity this connection proved at auth time.
  ///
  /// Every endpoint it later claims must belong to this node. That single check
  /// is what stops one authenticated peer from speaking as another.
  final String nodeUId;

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
  CoordinationHub._(this._server, this._session, this._secret, this.limits);

  final HttpServer _server;
  final PeerRegistry _registry = PeerRegistry();
  final RelayRouting _routing = RelayRouting();
  final Map<String, _Connection> _connections = {};
  final Map<String, _Pending> _pending = {};

  /// Resource limits. Fixed for the hub's lifetime — [WsLimits.maxFrameBytes]
  /// in particular is handed to the WebSocket upgrade per connection and cannot
  /// change under a live socket.
  final WsLimits limits;

  final String _session;
  String _secret;
  int _epoch = 1;
  HubSessionStatus _status = HubSessionStatus.open;

  /// Nodes refused for the rest of this epoch.
  final Set<String> _revoked = {};

  Timer? _ttlTimer;

  /// endpointId -> slot, and back.
  final Map<String, int> _slotByEndpoint = {};
  final Map<int, String> _endpointBySlot = {};

  int _nextConnectionId = 0;
  int _nextSlot = 1; // 0 is reserved as "unassigned"

  /// The port the hub is listening on.
  int get port => _server.port;

  /// Where clients should point a `WebSocketTransportConfig`.
  ///
  /// Always `ws://`: the hub never terminates TLS itself. A `wss://` deployment
  /// puts a reverse proxy in front, and clients use the proxy's address.
  Uri get uri => Uri(scheme: 'ws', host: _server.address.host, port: port);

  /// The one session this hub hosts.
  String get sessionName => _session;

  /// The current session generation.
  ///
  /// Bound into every auth proof, so incrementing it invalidates every
  /// credential a participant might have kept.
  int get epoch => _epoch;

  HubSessionStatus get status => _status;

  /// Number of authenticated clients.
  int get connectionCount => _connections.length;

  /// Sockets that have connected but not yet authenticated.
  int get pendingCount => _pending.length;

  /// Number of registered endpoints across all clients.
  int get endpointCount => _registry.length;

  /// The subscribers this hub would relay [producerEndpointId]'s stream to.
  ///
  /// Read-only, and the only way to tell a route that was actually torn down
  /// from one a client is merely ignoring locally — which is exactly the
  /// distinction `NetworkStream.removeInlet` has to get right.
  Set<String> subscribersFor({
    required String streamName,
    required String producerEndpointId,
  }) => _routing.subscribersFor(
    streamName: streamName,
    producerEndpointId: producerEndpointId,
  );

  /// Starts a hub for one session.
  ///
  /// [credentials] is required rather than optional on purpose: an open relay
  /// is not a mode this package offers, not even as a default, because the
  /// failure is silent and total.
  ///
  /// Pass `port: 0` (the default) for an ephemeral port, so tests can run in
  /// parallel without colliding; read [port] afterwards.
  ///
  /// [sessionTtl] closes the session automatically once it elapses — the point
  /// being that an experiment can be scheduled to end without anyone having to
  /// remember to end it.
  static Future<CoordinationHub> serve({
    required HubCredentials credentials,
    InternetAddress? address,
    int port = 0,
    WsLimits limits = const WsLimits(),
    Duration? sessionTtl,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    final hub = CoordinationHub._(
      server,
      credentials.session,
      credentials.secret,
      limits,
    );
    if (sessionTtl != null) hub._armTtl(sessionTtl);
    unawaited(hub._accept());
    logger.info(
      'Coordination hub listening on port ${hub.port} for session '
      '"${credentials.session}" (epoch ${hub._epoch})',
    );
    return hub;
  }

  // ---------------------------------------------------------------- lifecycle

  /// Ends the session: disconnects every peer and refuses new ones.
  ///
  /// Idempotent. All coordination state is dropped, so a peer that reconnects
  /// after [openSession] starts clean rather than inheriting a half-torn-down
  /// membership. Credentials minted for the ended epoch stay invalid even after
  /// the session is reopened, because [epoch] only ever moves forward.
  Future<void> endSession({String reason = 'session ended'}) async {
    if (_status == HubSessionStatus.closed) return;
    _status = HubSessionStatus.closed;
    _ttlTimer?.cancel();
    _ttlTimer = null;
    logger.info('Session "$_session" (epoch $_epoch) ending: $reason');

    final sockets = <Future<void>>[];
    for (final pending in _pending.values.toList(growable: false)) {
      pending.deadline.cancel();
      sockets.add(pending.socket.close(HubCloseCode.sessionClosed, reason));
    }
    for (final connection in _connections.values.toList(growable: false)) {
      sockets.add(connection.socket.close(HubCloseCode.sessionClosed, reason));
    }
    _pending.clear();
    _connections.clear();
    _routing.clear();
    _registry.clear();
    _slotByEndpoint.clear();
    _endpointBySlot.clear();
    _revoked.clear();
    await Future.wait(sockets);
  }

  /// Reopens the hub as a new session generation.
  ///
  /// [secret] is required, and that is the whole point: reopening means
  /// admitting a cohort, so the operator has to say which credential admits it.
  /// Pass the same string to keep the old one — deliberately an explicit
  /// choice, because the alternative is a hub that silently readmits everyone
  /// who took part in the session you just ended. Bumping [epoch] alone would
  /// not stop them: the epoch is announced in the challenge, so anyone still
  /// holding the secret would simply prove against the new one.
  void openSession({required String secret, Duration? ttl}) {
    if (secret.isEmpty) {
      throw ArgumentError.value('<redacted>', 'secret', 'must not be empty');
    }
    final rotated = secret != _secret;
    _epoch++;
    _secret = secret;
    _revoked.clear();
    _status = HubSessionStatus.open;
    _ttlTimer?.cancel();
    _ttlTimer = null;
    if (ttl != null) _armTtl(ttl);
    logger.info(
      'Session "$_session" open at epoch $_epoch'
      '${rotated ? ' with a rotated secret' : ' reusing the previous secret'}',
    );
  }

  /// Bars one node for the rest of this epoch, and disconnects it now.
  ///
  /// For the case the session as a whole should continue: one participant
  /// withdraws, or misbehaves, and must not be able to rejoin.
  Future<void> revoke(String nodeUId, {String reason = 'revoked'}) async {
    _revoked.add(nodeUId);
    final live = _connections.values
        .where((c) => c.nodeUId == nodeUId)
        .toList(growable: false);
    for (final connection in live) {
      await _drop(connection, HubCloseCode.sessionClosed, reason);
    }
    logger.info('Node $nodeUId revoked from session "$_session": $reason');
  }

  void _armTtl(Duration ttl) {
    _ttlTimer = Timer(
      ttl,
      () => unawaited(endSession(reason: 'session time limit reached')),
    );
  }

  // --------------------------------------------------------------- connecting

  Future<void> _accept() async {
    await for (final request in _server) {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Expected a WebSocket upgrade request');
        await request.response.close();
        continue;
      }
      if (_status == HubSessionStatus.closed) {
        // Refused before the upgrade, so a closed hub never allocates a socket.
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..write('Session closed');
        await request.response.close();
        continue;
      }
      if (_pending.length + _connections.length >= limits.maxConnections) {
        logger.warning(
          'Hub: refusing connection, at capacity '
          '(${limits.maxConnections})',
        );
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..write('Hub at capacity');
        await request.response.close();
        continue;
      }
      try {
        // maxPayloadLength is the hub's only real defence against a frame
        // sized to exhaust memory: the SDK rejects at the frame's *length
        // header*, before a byte of payload is buffered, and checks the
        // post-inflate size too, so it also covers a deflate bomb. Note it is
        // per frame rather than per message — a fragmented message can still
        // accumulate across continuation frames, and no reverse proxy caps
        // WebSocket frames either, so a cumulative byte-rate limit is the
        // remaining gap. Post-auth that is a trusted-peer problem; pre-auth,
        // the handshake deadline bounds it.
        final socket = await WebSocketTransformer.upgrade(
          request,
          maxPayloadLength: limits.maxFrameBytes,
        );
        socket.pingInterval = limits.pingInterval;
        _onConnected(socket);
      } catch (e) {
        logger.warning('Failed to upgrade connection: $e');
      }
    }
  }

  /// Challenges a fresh socket and waits, briefly, for it to answer.
  void _onConnected(WebSocket socket) {
    final id = 'conn-${_nextConnectionId++}';
    final nonce = HubCredentials.newNonce();
    final pending = _Pending(
      socket,
      nonce,
      Timer(limits.handshakeTimeout, () {
        if (_pending.remove(id) == null) return;
        logger.warning('Hub: $id did not authenticate in time');
        unawaited(
          socket.close(HubCloseCode.unauthorized, 'handshake timed out'),
        );
      }),
    );
    _pending[id] = pending;

    socket.listen(
      (Object? data) => _onSocketData(id, data),
      onDone: () => _onSocketClosed(id),
      onError: (Object e) {
        // Includes the SDK's own "frame payload length exceeds ..." — the
        // oversize case arrives here, having allocated nothing.
        logger.warning('Hub: $id socket error: $e');
        _onSocketClosed(id);
      },
      cancelOnError: true,
    );

    if (socket.readyState == WebSocket.open) {
      // The epoch is announced, not guessed. It is a replay domain, not a
      // secret: naming it lets an honest client bind its proof to the current
      // generation, while a proof captured from an earlier one stays useless
      // because the epoch it names no longer matches. What actually keeps a
      // departed participant out is the session being closed, or its secret
      // having been rotated.
      socket.add(
        WsFrame(WsControl.challenge, {
          'nonce': nonce,
          'epoch': _epoch,
          'session': _session,
        }).encode(),
      );
    }
  }

  void _onSocketData(String id, Object? data) {
    final connection = _connections[id];
    if (connection != null) {
      _onData(connection, data);
      return;
    }
    final pending = _pending[id];
    if (pending == null) return; // already gone
    _onPendingData(id, pending, data);
  }

  /// Handles the one frame an unauthenticated connection may send.
  void _onPendingData(String id, _Pending pending, Object? data) {
    if (data is! String) {
      _rejectPending(id, pending, 'binary frame before authentication');
      return;
    }
    final WsFrame frame;
    try {
      frame = WsFrame.decode(data);
    } catch (e) {
      _rejectPending(id, pending, 'undecodable frame: $e');
      return;
    }
    if (frame.type != WsControl.auth) {
      _rejectPending(id, pending, '${frame.type.name} before authentication');
      return;
    }

    // Consumed whether or not it verifies, so a proof is good for one attempt.
    final nonce = pending.nonce;
    pending.nonce = null;
    if (nonce == null) {
      _rejectPending(id, pending, 'challenge already used');
      return;
    }

    if (_status == HubSessionStatus.closed) {
      _rejectPending(
        id,
        pending,
        'session closed',
        code: HubCloseCode.sessionClosed,
      );
      return;
    }

    final session = frame.payload['session'] as String?;
    final epoch = frame.payload['epoch'] as int?;
    final nodeUId = frame.payload['nodeUId'] as String?;
    final proof = frame.payload['proof'] as String?;
    if (session == null ||
        epoch == null ||
        nodeUId == null ||
        nodeUId.isEmpty ||
        proof == null) {
      _rejectPending(id, pending, 'incomplete auth frame');
      return;
    }
    if (session != _session) {
      // Named rather than silent: pointing a client at the wrong hub is a
      // configuration mistake people make constantly, and it looks identical
      // to a wrong secret unless the log says otherwise.
      _rejectPending(id, pending, 'wrong session "$session"');
      return;
    }
    if (epoch != _epoch) {
      _rejectPending(
        id,
        pending,
        'stale epoch $epoch (session is at $_epoch)',
        code: HubCloseCode.sessionClosed,
      );
      return;
    }
    if (_revoked.contains(nodeUId)) {
      _rejectPending(
        id,
        pending,
        'node revoked',
        code: HubCloseCode.sessionClosed,
      );
      return;
    }

    final expected = HubCredentials.computeProof(
      secret: _secret,
      nonce: nonce,
      session: _session,
      epoch: _epoch,
      nodeUId: nodeUId,
    );
    if (!HubCredentials.secureEquals(proof, expected)) {
      _rejectPending(id, pending, 'bad proof');
      return;
    }

    // One node holds one socket. A second connection for a live nodeUId is
    // almost always a reconnect after a drop the hub has not noticed yet, so
    // the newer socket wins and the stale one is evicted — a peer that cannot
    // reconnect until its old socket times out is worse than useless on a
    // flaky network. Concurrent impersonation is not a risk this trades away:
    // both sockets had to know the secret.
    final stale = _connections.values
        .where((c) => c.nodeUId == nodeUId)
        .toList(growable: false);
    for (final connection in stale) {
      logger.warning(
        'Hub: $nodeUId reconnected on $id, evicting ${connection.id}',
      );
      unawaited(
        _drop(connection, HubCloseCode.identityConflict, 'reconnected'),
      );
    }

    pending.deadline.cancel();
    _pending.remove(id);
    final connection = _Connection(id, pending.socket, nodeUId);
    _connections[id] = connection;
    connection.send(
      WsFrame(WsControl.authOk, {
        'connId': id,
        'epoch': _epoch,
        'hubTimeMicros': DateTime.now().microsecondsSinceEpoch,
      }).encode(),
    );
    logger.fine('Hub: $id authenticated as $nodeUId');
  }

  void _rejectPending(
    String id,
    _Pending pending,
    String reason, {
    int code = HubCloseCode.unauthorized,
  }) {
    if (_pending.remove(id) == null) return;
    pending.deadline.cancel();
    logger.warning('Hub: refusing $id: $reason');
    unawaited(pending.socket.close(code, reason));
  }

  // ------------------------------------------------------------------ traffic

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
          if (!connection.liveQueries.containsKey(qid) &&
              connection.liveQueries.length >=
                  limits.maxLiveQueriesPerConnection) {
            logger.warning(
              'Hub: ${connection.id} exceeded '
              '${limits.maxLiveQueriesPerConnection} live queries',
            );
            return;
          }
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

      case WsControl.unsubscribe:
        final subscriber = frame.payload['subscriber'] as String;
        for (final producer in (frame.payload['from'] as List).cast<String>()) {
          _routing.unsubscribe(
            streamName: frame.payload['stream'] as String,
            producerEndpointId: producer,
            subscriberEndpointId: subscriber,
          );
        }

      case WsControl.message:
        _relayMessage(connection, frame);

      case WsControl.signal:
        _forwardSignal(connection, frame);

      case WsControl.auth:
        // Already authenticated. Re-authenticating on a live connection has no
        // meaning and would only be a way to change identity mid-stream.
        logger.warning('Hub: ${connection.id} re-sent auth; ignoring');

      case WsControl.challenge:
      case WsControl.authOk:
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
  ///
  /// Every claim is checked against the identity the connection authenticated
  /// as. Without that, `publish: false` on someone else's endpoint id is a
  /// one-frame way to de-register them, and owning their endpoint id is a way
  /// to speak as them.
  void _register(
    _Connection connection,
    PeerDescriptor descriptor, {
    required bool publish,
  }) {
    final endpointId = descriptor.endpointId;

    if (descriptor.nodeUId != connection.nodeUId) {
      logger.warning(
        'Hub: ${connection.id} (${connection.nodeUId}) published a descriptor '
        'for node ${descriptor.nodeUId}',
      );
      return;
    }
    // The descriptor's `nodeUId` field is not enough on its own: the endpoint id
    // is a separate string, and a peer could pair its own nodeUId with an
    // endpoint id addressed to somebody else. Endpoint ids are built as
    // `session/nodeUId/streamName` — by `PeerDescriptor.forNode` and by
    // `RtcMesh.signallingEndpointFor` alike — so requiring the authenticated
    // node to appear as a path segment checks the thing that actually matters
    // without pinning the format.
    if (!endpointId.split('/').contains(connection.nodeUId)) {
      logger.warning(
        'Hub: ${connection.id} (${connection.nodeUId}) tried to claim '
        '$endpointId, which is not addressed to it',
      );
      return;
    }
    final owner = _connectionForEndpoint(endpointId);
    if (owner != null && owner.id != connection.id) {
      logger.warning(
        'Hub: ${connection.id} tried to claim $endpointId, held by '
        '${owner.id}',
      );
      return;
    }
    final known = connection.endpointIds.contains(endpointId);
    if (!known &&
        connection.endpointIds.length >= limits.maxEndpointsPerConnection) {
      logger.warning(
        'Hub: ${connection.id} exceeded '
        '${limits.maxEndpointsPerConnection} endpoints',
      );
      return;
    }
    if (!_slotByEndpoint.containsKey(endpointId)) {
      if (_slotByEndpoint.length >= limits.maxPeers) {
        logger.warning('Hub: at ${limits.maxPeers} endpoints, refusing more');
        return;
      }
      // The slot travels as a uint16, and slots are not reused within a hub's
      // lifetime. Refusing past the range beats silently truncating into
      // another endpoint's slot and misrouting its samples.
      if (_nextSlot > 0xFFFF) {
        logger.severe(
          'Hub: slot space exhausted after $_nextSlot registrations; '
          'restart the hub',
        );
        return;
      }
    }

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

  /// Forwards a signalling frame to the one endpoint it names.
  ///
  /// The hub's only unicast, and the only payload it never inspects. This is
  /// what lets a peer-to-peer transport use this hub for discovery and
  /// connection setup while keeping its data off it entirely: the two peers
  /// exchange whatever they need to dial each other, and the hub is a post box.
  ///
  /// Ownership of `from` is checked exactly as [_relayMessage] does, so a
  /// connection cannot signal on another peer's behalf. An unknown or departed
  /// `to` is dropped silently — the sender learns from its own connection
  /// attempt timing out, and there is nothing useful the hub could add.
  void _forwardSignal(_Connection connection, WsFrame frame) {
    final from = frame.payload['from'] as String?;
    final to = frame.payload['to'] as String?;
    if (from == null || to == null) {
      logger.warning('Hub: signal from ${connection.id} missing from/to');
      return;
    }
    if (!connection.endpointIds.contains(from)) {
      logger.warning('Hub: ${connection.id} tried to signal as $from');
      return;
    }

    final target = _connectionForEndpoint(to);
    if (target == null) {
      logger.fine('Hub: no connection for signal target $to');
      return;
    }
    // Re-encoded rather than forwarded byte for byte so `from` is the endpoint
    // the hub verified, not whatever the sender wrote.
    target.send(
      WsFrame(WsControl.signal, {
        'from': from,
        'to': to,
        'payload': frame.payload['payload'],
      }).encode(),
    );
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

  /// Closes a live connection and tears down everything it held.
  Future<void> _drop(_Connection connection, int code, String reason) async {
    _onDisconnected(connection);
    await connection.socket.close(code, reason);
  }

  void _onSocketClosed(String id) {
    final pending = _pending.remove(id);
    if (pending != null) {
      pending.deadline.cancel();
      return;
    }
    final connection = _connections[id];
    if (connection != null) _onDisconnected(connection);
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
    _ttlTimer?.cancel();
    _ttlTimer = null;
    for (final pending in _pending.values.toList(growable: false)) {
      pending.deadline.cancel();
      await pending.socket.close();
    }
    _pending.clear();
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
