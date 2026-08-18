/// The mesh of live peer connections, and the state machine that builds it.
///
/// This is where the transport's one genuinely awkward mismatch is resolved.
/// Signalling is addressed to **endpoint ids**, which are per-stream
/// (`'$sessionName/$nodeUId/$streamName'`), while an `RTCPeerConnection` is per
/// **peer pair**, shared by every stream between two nodes. So:
///
/// * links are keyed on **node uId** — the only identifier stable across a role
///   change, and the same key `PeerClockOffsets` uses;
/// * every signal for a pair travels via that pair's **coordination-stream**
///   endpoint id, regardless of which stream's channel triggered the dial. Both
///   ends can derive it from a node uId alone, so a receiver never has to know
///   why the offer arrived;
/// * the envelope names its sender explicitly, and the hub-verified `from`
///   endpoint is checked against it.
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:peer_coordinator/websocket.dart';

import 'rtc_adapter.dart';
import 'rtc_signal.dart';

final Logger _logger = Logger('webrtc_coordinator.mesh');

/// A data channel that has just come into existence.
///
/// Emitted for channels opened from either side — this node subscribing to a
/// peer, or a peer subscribing to this node — because a stream has to listen to
/// both. It sends on channels a peer asked for and receives on channels it
/// asked for, and those two sets are not the same in an asymmetric
/// participation mode.
class RtcChannelEvent {
  const RtcChannelEvent({
    required this.peerNodeUId,
    required this.streamName,
    required this.channel,
  });

  final String peerNodeUId;
  final String streamName;
  final RtcChannel channel;
}

/// Owns one [RtcPeerLink] per remote peer, and the channels on it.
class RtcMesh {
  RtcMesh({
    required this.adapter,
    required this.connection,
    required this.selfNodeUId,
    required this.sessionName,
    required this.coordinationStreamName,
    this.iceServers = const [],
    this.connectTimeout = const Duration(seconds: 15),
  }) {
    _signalSubscription = connection.signals.listen(_onSignal);
  }

  final RtcPeerAdapter adapter;
  final WsConnection connection;
  final String selfNodeUId;
  final String sessionName;

  /// The coordination stream's name, which fixes both the signalling address
  /// and the reserved channel id.
  final String coordinationStreamName;

  final List<Map<String, Object?>> iceServers;
  final Duration connectTimeout;

  final Map<String, _PeerEntry> _peers = {};

  /// Entries still being built, keyed by node uId.
  ///
  /// [_entryFor] awaits `adapter.createLink`, and two callers arriving inside
  /// that gap is the normal case rather than a rare one: this node's own
  /// `channelFor` and the peer's `open` or `offer` signal reach it at the same
  /// moment on every connection. Without memoising the *future*, both would
  /// see no entry, both would build one, and the second would displace the
  /// first — two `RTCPeerConnection`s for one peer, with the offer made on one
  /// and the answer applied to the other, which libwebrtc rejects as "Called
  /// in wrong state: stable" while the channel nobody is waiting on never
  /// opens.
  final Map<String, Future<_PeerEntry>> _pendingPeers = {};

  /// streamName -> node uIds that have asked to receive it from this node.
  ///
  /// The whole routing table. On the WebSocket transport this lives in the
  /// hub's `RelayRouting`; with no hub on the data path it lives here, filled
  /// by [RtcSignalKind.open] signals from subscribers.
  final Map<String, Set<String>> _subscribersByStream = {};

  final _peerLost = StreamController<String>.broadcast();
  final _channelOpened = StreamController<RtcChannelEvent>.broadcast();
  StreamSubscription<WsSignal>? _signalSubscription;
  bool _closed = false;

  /// Node uIds whose connection has gone away.
  ///
  /// The coordination layer learns about departures through heartbeats, which
  /// is slower; this is the transport noticing first.
  Stream<String> get peerLost => _peerLost.stream;

  /// Node uIds with a live link.
  Iterable<String> get connectedPeers => _peers.keys;

  /// Channels as they open, from either side. Broadcast.
  Stream<RtcChannelEvent> get channelOpened => _channelOpened.stream;

  /// Node uIds that have asked this node for [streamName].
  ///
  /// A producer sends on exactly these peers' channels. Empty is normal: a
  /// stream nobody subscribed to publishes nowhere, exactly as it does through
  /// a hub with no routes installed.
  Set<String> subscribersFor(String streamName) =>
      _subscribersByStream[streamName] ?? const <String>{};

  /// Every open channel carrying [streamName], keyed by peer node uId.
  Map<String, RtcChannel> channelsForStream(String streamName) => {
    for (final MapEntry(key: peer, value: entry) in _peers.entries)
      peer: ?entry.channels[streamName],
  };

  /// This node's signalling address.
  String get selfSignallingEndpoint => signallingEndpointFor(selfNodeUId);

  /// The endpoint id every signal to [nodeUId] is addressed to.
  String signallingEndpointFor(String nodeUId) =>
      '$sessionName/$nodeUId/$coordinationStreamName';

  /// The data-channel id for [streamName].
  ///
  /// The coordination stream is pinned to [coordinationChannelId] whatever it
  /// is called — a session may name it `coordination-<runId>` — because it is
  /// the one channel that must exist before anything else can be agreed.
  int channelIdFor(String streamName) => streamName == coordinationStreamName
      ? coordinationChannelId
      : rtcChannelIdFor(streamName);

  /// Whether this node makes the offer to [peerNodeUId].
  ///
  /// The lexicographically lower uId offers. Deterministic, so glare cannot
  /// happen between two correct peers and needs no negotiation to resolve.
  bool shouldOffer(String peerNodeUId) =>
      selfNodeUId.compareTo(peerNodeUId) < 0;

  /// Returns the channel carrying [streamName] to [peerNodeUId], dialling the
  /// peer if this is the first stream between them.
  ///
  /// Waits for the channel to open. Throws [StateError] if it does not within
  /// [connectTimeout] — a caller that cannot reach a producer must fail the way
  /// `createInletsForNodes` already fails on the other transports, not hang.
  Future<RtcChannel> channelFor({
    required String peerNodeUId,
    required String streamName,
    bool ordered = true,
    int? maxRetransmits,
  }) async {
    if (_closed) throw StateError('Mesh is closed');
    if (peerNodeUId == selfNodeUId) {
      throw ArgumentError.value(
        peerNodeUId,
        'peerNodeUId',
        'a node cannot dial itself; loopback streams are handled above the '
            'transport',
      );
    }

    final entry = await _entryFor(peerNodeUId);
    final id = channelIdFor(streamName);
    final channel = await _ensureChannel(
      entry,
      streamName,
      id,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    );

    // Ask the peer to open its half, and in doing so register as a subscriber
    // over there. Both halves are needed: `negotiated: true` channels do not
    // announce themselves, and the peer may have no reason of its own to open
    // one — in `sendAllReceiveCoordinator` the producers never subscribe back.
    //
    // This also has to be sent before the offer, so that a peer that is the
    // offerer for this pair knows to dial. It goes out on the same hub socket,
    // which preserves order.
    _send(
      peerNodeUId,
      RtcSignal(
        kind: RtcSignalKind.open,
        fromNodeUId: selfNodeUId,
        payload: {
          's': streamName,
          'id': id,
          'o': ordered,
          'r': ?maxRetransmits,
        },
      ),
    );

    // Only the offerer dials. The answerer has its channel open and waiting by
    // the time the offer arrives, which is the point of `negotiated: true`.
    if (shouldOffer(peerNodeUId)) await _dial(entry);

    try {
      await channel.ready.timeout(connectTimeout);
    } on TimeoutException {
      throw StateError(
        'Timed out after ${connectTimeout.inSeconds}s opening "$streamName" to '
        '$peerNodeUId (link state: ${entry.link.state.name})',
      );
    }
    return channel;
  }

  /// The already-open channel for [streamName] to [peerNodeUId], if any.
  RtcChannel? existingChannel({
    required String peerNodeUId,
    required String streamName,
  }) => _peers[peerNodeUId]?.channels[streamName];

  /// Releases one stream's channel to one peer.
  ///
  /// When the last channel to a peer goes, so does the connection. That is the
  /// whole reason `NetworkStream.removeInlet` exists: without it a departed
  /// peer's `RTCPeerConnection` survives until the session is disposed.
  Future<void> releaseChannel({
    required String peerNodeUId,
    required String streamName,
  }) async {
    final entry = _peers[peerNodeUId];
    if (entry == null) return;
    _subscribersByStream[streamName]?.remove(peerNodeUId);
    final channel = entry.channels.remove(streamName);
    if (channel == null) return;
    entry.streamByChannelId.remove(channel.id);
    await channel.close();
    if (entry.channels.isEmpty) await releasePeer(peerNodeUId);
  }

  /// Closes the connection to [peerNodeUId] and every channel on it.
  Future<void> releasePeer(String peerNodeUId) async {
    final entry = _peers.remove(peerNodeUId);
    if (entry == null) return;
    _forgetSubscriber(peerNodeUId);
    await entry.dispose();
    if (!_closed && connection.isConnected) {
      // Best-effort courtesy: lets the peer drop its half now rather than after
      // an ICE timeout. Its loss costs nothing but latency.
      _send(
        peerNodeUId,
        RtcSignal(kind: RtcSignalKind.bye, fromNodeUId: selfNodeUId),
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _signalSubscription?.cancel();
    _signalSubscription = null;
    for (final entry in _peers.values.toList(growable: false)) {
      await entry.dispose();
    }
    _peers.clear();
    _subscribersByStream.clear();
    await adapter.close();
    await _peerLost.close();
    await _channelOpened.close();
  }

  // ---------------------------------------------------------------------------
  // Dialling
  // ---------------------------------------------------------------------------

  /// The entry for [peerNodeUId], building it if this is the first mention.
  ///
  /// Deliberately not `async`: everything up to storing the in-flight future
  /// must run in one turn, or the memo does not close the window it exists to
  /// close. See [_pendingPeers].
  Future<_PeerEntry> _entryFor(String peerNodeUId) {
    final existing = _peers[peerNodeUId];
    if (existing != null) return Future.value(existing);
    return _pendingPeers[peerNodeUId] ??= _createEntry(peerNodeUId);
  }

  Future<_PeerEntry> _createEntry(String peerNodeUId) async {
    try {
      return await _buildEntry(peerNodeUId);
    } finally {
      _pendingPeers.remove(peerNodeUId);
    }
  }

  Future<_PeerEntry> _buildEntry(String peerNodeUId) async {
    final link = await adapter.createLink(peerNodeUId, iceServers: iceServers);
    // The mesh may have been closed while the link was being built, in which
    // case nothing will ever dispose this one but us.
    if (_closed) {
      await link.close();
      throw StateError('Mesh is closed');
    }
    final entry = _PeerEntry(peerNodeUId: peerNodeUId, link: link);
    _peers[peerNodeUId] = entry;

    entry.subscriptions.add(
      link.localCandidates.listen((candidate) {
        _send(
          peerNodeUId,
          RtcSignal(
            kind: RtcSignalKind.candidate,
            fromNodeUId: selfNodeUId,
            payload: candidate,
          ),
        );
      }),
    );
    entry.subscriptions.add(
      link.states.listen((state) {
        if (state != RtcLinkState.closed) return;
        // Terminal: a peer that comes back has a fresh node uId and is a
        // different peer, so there is nothing to reconnect to.
        _logger.info('Link to $peerNodeUId closed');
        unawaited(_onLinkClosed(peerNodeUId));
      }),
    );
    return entry;
  }

  Future<void> _onLinkClosed(String peerNodeUId) async {
    final entry = _peers.remove(peerNodeUId);
    if (entry == null) return;
    _forgetSubscriber(peerNodeUId);
    await entry.dispose();
    if (!_peerLost.isClosed) _peerLost.add(peerNodeUId);
  }

  void _forgetSubscriber(String peerNodeUId) {
    for (final subscribers in _subscribersByStream.values) {
      subscribers.remove(peerNodeUId);
    }
  }

  /// Opens [streamName]'s channel on [entry] if it is not already open.
  ///
  /// Memoised on the in-flight future for the same reason [_entryFor] is, and
  /// the collision here is worse: `channelFor` and the peer's `open` signal
  /// both ask for the coordination stream on every connection, so without this
  /// two data channels get opened with the same pre-negotiated id. One of them
  /// wins the map, the other is what `channelFor` is awaiting `ready` on, and
  /// the join fails on a timeout with the link still `connecting`.
  ///
  /// Not `async`, for the same reason.
  Future<RtcChannel> _ensureChannel(
    _PeerEntry entry,
    String streamName,
    int id, {
    required bool ordered,
    int? maxRetransmits,
  }) {
    final existing = entry.channels[streamName];
    if (existing != null) return Future.value(existing);
    return entry.pendingChannels[streamName] ??= _openChannel(
      entry,
      streamName,
      id,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    );
  }

  Future<RtcChannel> _openChannel(
    _PeerEntry entry,
    String streamName,
    int id, {
    required bool ordered,
    int? maxRetransmits,
  }) async {
    try {
      return await _buildChannel(
        entry,
        streamName,
        id,
        ordered: ordered,
        maxRetransmits: maxRetransmits,
      );
    } finally {
      entry.pendingChannels.remove(streamName);
    }
  }

  Future<RtcChannel> _buildChannel(
    _PeerEntry entry,
    String streamName,
    int id, {
    required bool ordered,
    int? maxRetransmits,
  }) async {
    // A collision would put two streams on one channel and silently interleave
    // them. Fail here, in this process, rather than let it cross the wire.
    final collision = entry.streamByChannelId[id];
    if (collision != null && collision != streamName) {
      throw StateError(
        'Data-channel id $id is claimed by both "$collision" and "$streamName". '
        'Channel ids are derived from stream names (see rtcChannelIdFor); '
        'rename one of these streams.',
      );
    }

    final channel = await entry.link.openChannel(
      id,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    );
    entry.channels[streamName] = channel;
    entry.streamByChannelId[id] = streamName;
    if (!_channelOpened.isClosed) {
      _channelOpened.add(
        RtcChannelEvent(
          peerNodeUId: entry.peerNodeUId,
          streamName: streamName,
          channel: channel,
        ),
      );
    }
    return channel;
  }

  Future<void> _dial(_PeerEntry entry) async {
    if (entry.offered) return;
    entry.offered = true;
    try {
      final offer = await entry.link.createOffer();
      _send(
        entry.peerNodeUId,
        RtcSignal(
          kind: RtcSignalKind.offer,
          fromNodeUId: selfNodeUId,
          payload: offer,
        ),
      );
    } catch (e) {
      entry.offered = false;
      _logger.warning('Failed to offer to ${entry.peerNodeUId}: $e');
      rethrow;
    }
  }

  void _send(String peerNodeUId, RtcSignal signal) {
    connection.sendSignal(
      fromEndpointId: selfSignallingEndpoint,
      toEndpointId: signallingEndpointFor(peerNodeUId),
      payload: signal.toJson(),
    );
  }

  // ---------------------------------------------------------------------------
  // Signalling
  // ---------------------------------------------------------------------------

  Future<void> _onSignal(WsSignal wire) async {
    if (_closed) return;
    final signal = RtcSignal.tryParse(wire.payload);
    if (signal == null) {
      _logger.warning(
        'Dropping unparseable signal from ${wire.fromEndpointId}',
      );
      return;
    }

    // `wire.fromEndpointId` is the one field the hub verified. The envelope's
    // claim about its own sender has to match it, or a peer could answer on
    // another peer's behalf.
    final claimed = signallingEndpointFor(signal.fromNodeUId);
    if (claimed != wire.fromEndpointId) {
      _logger.warning(
        'Dropping signal claiming to be from ${signal.fromNodeUId} but sent by '
        '${wire.fromEndpointId}',
      );
      return;
    }
    if (signal.fromNodeUId == selfNodeUId) return;

    try {
      switch (signal.kind) {
        case RtcSignalKind.offer:
          await _onOffer(signal);
        case RtcSignalKind.answer:
          final entry = await _knownEntry(signal.fromNodeUId);
          await entry?.link.acceptAnswer(signal.payload);
        case RtcSignalKind.candidate:
          final entry = await _knownEntry(signal.fromNodeUId);
          await entry?.link.addCandidate(signal.payload);
        case RtcSignalKind.open:
          await _onOpen(signal);
        case RtcSignalKind.bye:
          await _onLinkClosed(signal.fromNodeUId);
      }
    } catch (e) {
      _logger.warning(
        'Failed to handle ${signal.kind.name} from ${signal.fromNodeUId}: $e',
      );
    }
  }

  /// The entry for [peerNodeUId] if one exists or is on its way, else null.
  ///
  /// Answers and candidates must not *create* a link — an unsolicited signal
  /// from a peer this node never dialled is not a reason to connect — but they
  /// must not be dropped merely because the link they belong to is still a
  /// platform-channel round trip away from existing. That is the normal case
  /// for the candidates that trickle in immediately behind an offer, and
  /// dropping them leaves the answerer with no remote candidates at all.
  Future<_PeerEntry?> _knownEntry(String peerNodeUId) async {
    final existing = _peers[peerNodeUId];
    if (existing != null) return existing;
    final pending = _pendingPeers[peerNodeUId];
    if (pending == null) return null;
    try {
      return await pending;
    } catch (_) {
      // Whoever asked for the link reports its failure; this is a signal that
      // no longer has anywhere to go.
      return null;
    }
  }

  Future<void> _onOffer(RtcSignal signal) async {
    final peerNodeUId = signal.fromNodeUId;
    if (shouldOffer(peerNodeUId)) {
      // Glare, or a peer that does not know the rule. The lower uId offers, and
      // that is us — so this offer is not one we should answer. Dropping it is
      // safe: our own offer is either already out or about to be.
      _logger.info(
        'Ignoring offer from $peerNodeUId; this node is the offerer',
      );
      return;
    }
    final entry = await _entryFor(peerNodeUId);
    final answer = await entry.link.createAnswer(signal.payload);
    _send(
      peerNodeUId,
      RtcSignal(
        kind: RtcSignalKind.answer,
        fromNodeUId: selfNodeUId,
        payload: answer,
      ),
    );
  }

  /// A peer wants [streamName] from this node.
  Future<void> _onOpen(RtcSignal signal) async {
    final peerNodeUId = signal.fromNodeUId;
    final streamName = signal.payload['s'];
    if (streamName is! String || streamName.isEmpty) {
      _logger.warning('Dropping open signal from $peerNodeUId with no stream');
      return;
    }
    final ordered = signal.payload['o'] as bool? ?? true;
    final maxRetransmits = signal.payload['r'] as int?;

    // Derived locally rather than taken from the wire: trusting the sender's
    // arithmetic would let one mismatched peer put a stream on the wrong
    // channel. The advertised id is checked only so a divergence is loud.
    final id = channelIdFor(streamName);
    final advertised = signal.payload['id'];
    if (advertised is int && advertised != id) {
      _logger.warning(
        '$peerNodeUId derived channel id $advertised for "$streamName" but '
        'this node derived $id; the peers disagree about the coordination '
        'stream name and will not connect',
      );
    }

    (_subscribersByStream[streamName] ??= <String>{}).add(peerNodeUId);

    final entry = await _entryFor(peerNodeUId);
    await _ensureChannel(
      entry,
      streamName,
      id,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    );
    // The subscriber may be the answerer for this pair, in which case it is
    // waiting on us to dial and nothing else will trigger it.
    if (shouldOffer(peerNodeUId)) await _dial(entry);
  }
}

class _PeerEntry {
  _PeerEntry({required this.peerNodeUId, required this.link});

  final String peerNodeUId;
  final RtcPeerLink link;

  /// streamName -> channel.
  final Map<String, RtcChannel> channels = {};

  /// streamName -> the channel still being opened, so two callers asking for
  /// one stream at once get one channel. See `RtcMesh._ensureChannel`.
  final Map<String, Future<RtcChannel>> pendingChannels = {};

  /// channel id -> streamName, so a derivation collision is caught locally.
  final Map<int, String> streamByChannelId = {};

  final List<StreamSubscription<Object?>> subscriptions = [];
  bool offered = false;

  Future<void> dispose() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    channels.clear();
    pendingChannels.clear();
    streamByChannelId.clear();
    await link.close();
  }
}
