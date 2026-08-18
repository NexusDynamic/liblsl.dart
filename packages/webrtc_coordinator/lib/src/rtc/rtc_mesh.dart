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
  final _peerLost = StreamController<String>.broadcast();
  StreamSubscription<WsSignal>? _signalSubscription;
  bool _closed = false;

  /// Node uIds whose connection has gone away.
  ///
  /// The coordination layer learns about departures through heartbeats, which
  /// is slower; this is the transport noticing first.
  Stream<String> get peerLost => _peerLost.stream;

  /// Node uIds with a live link.
  Iterable<String> get connectedPeers => _peers.keys;

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

    final existing = entry.channels[streamName];
    if (existing != null) return existing;

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
    await adapter.close();
    await _peerLost.close();
  }

  // ---------------------------------------------------------------------------
  // Dialling
  // ---------------------------------------------------------------------------

  Future<_PeerEntry> _entryFor(String peerNodeUId) async {
    final existing = _peers[peerNodeUId];
    if (existing != null) return existing;

    final link = await adapter.createLink(peerNodeUId, iceServers: iceServers);
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
    await entry.dispose();
    if (!_peerLost.isClosed) _peerLost.add(peerNodeUId);
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
      _logger.warning('Dropping unparseable signal from ${wire.fromEndpointId}');
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
          await _peers[signal.fromNodeUId]?.link.acceptAnswer(signal.payload);
        case RtcSignalKind.candidate:
          await _peers[signal.fromNodeUId]?.link.addCandidate(signal.payload);
        case RtcSignalKind.bye:
          await _onLinkClosed(signal.fromNodeUId);
      }
    } catch (e) {
      _logger.warning(
        'Failed to handle ${signal.kind.name} from ${signal.fromNodeUId}: $e',
      );
    }
  }

  Future<void> _onOffer(RtcSignal signal) async {
    final peerNodeUId = signal.fromNodeUId;
    if (shouldOffer(peerNodeUId)) {
      // Glare, or a peer that does not know the rule. The lower uId offers, and
      // that is us — so this offer is not one we should answer. Dropping it is
      // safe: our own offer is either already out or about to be.
      _logger.info('Ignoring offer from $peerNodeUId; this node is the offerer');
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
}

class _PeerEntry {
  _PeerEntry({required this.peerNodeUId, required this.link});

  final String peerNodeUId;
  final RtcPeerLink link;

  /// streamName -> channel.
  final Map<String, RtcChannel> channels = {};

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
    streamByChannelId.clear();
    await link.close();
  }
}
