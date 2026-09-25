/// The boundary between this transport and a real WebRTC implementation.
///
/// `flutter_webrtc` is a Flutter plugin with native code behind it: it cannot
/// run in a headless `dart test` VM, and depending on it would make this
/// package Flutter-only. Every call into it therefore goes through the
/// interfaces in this file, with a pure-Dart fake ([FakeRtcPeerAdapter]) on the
/// other side for tests. That is what makes the dial state machine, glare
/// resolution, channel routing and framing testable without a device — which is
/// nearly all of the transport.
///
/// The rule that keeps the seam honest: **no `flutter_webrtc` type may appear in
/// any signature here.** Session descriptions and ICE candidates cross as plain
/// JSON maps — the shape they already serialise to for signalling — and
/// connection state crosses as [RtcLinkState] rather than
/// `RTCPeerConnectionState`. A binding that needs to leak a native type is a
/// binding whose abstraction is wrong.
library;

import 'dart:typed_data';

/// Creates and owns peer connections.
///
/// One adapter per transport instance; one [RtcPeerLink] per remote peer.
abstract interface class RtcPeerAdapter {
  /// Builds a connection to one peer. Does not begin negotiation.
  ///
  /// [peerKey] identifies the remote peer — a node uId, not an endpoint id.
  /// One link is shared by every stream between this pair.
  ///
  /// [iceServers] is in the standard `{'urls': ..., 'username': ...}` form.
  /// Empty means host candidates only: pure LAN peer-to-peer, no third party
  /// involved. See `RtcTransportConfig.iceServers` for why that is the default.
  Future<RtcPeerLink> createLink(
    String peerKey, {
    List<Map<String, Object?>> iceServers = const [],
  });

  /// Closes every link this adapter created.
  Future<void> close();
}

/// A connection to one peer.
///
/// The negotiation methods are deliberately raw — offer, answer, candidate —
/// rather than a single `connect()`. Signalling has to travel over the hub
/// socket, which is above this seam, so the link cannot drive it itself.
abstract interface class RtcPeerLink {
  /// This peer's key, as passed to [RtcPeerAdapter.createLink].
  String get peerKey;

  /// Produces an offer and applies it locally.
  Future<Map<String, Object?>> createOffer();

  /// Applies [remoteOffer], produces an answer, and applies that locally.
  Future<Map<String, Object?>> createAnswer(Map<String, Object?> remoteOffer);

  /// Applies an answer to an offer this link made.
  Future<void> acceptAnswer(Map<String, Object?> remoteAnswer);

  /// Adds a candidate the remote peer gathered.
  ///
  /// Candidates that arrive before the remote description does must be
  /// buffered by the implementation, not dropped — ICE routinely delivers them
  /// out of order relative to the answer.
  Future<void> addCandidate(Map<String, Object?> candidate);

  /// Candidates gathered locally, for the caller to signal to the peer.
  Stream<Map<String, Object?>> get localCandidates;

  /// Connection state changes. Broadcast.
  Stream<RtcLinkState> get states;

  /// The most recent [RtcLinkState].
  RtcLinkState get state;

  /// Opens a pre-negotiated data channel.
  ///
  /// [id] must be agreed by both ends without exchanging metadata — see
  /// `rtcChannelIdFor`. `negotiated: true` is not optional here: in-band
  /// negotiation would need an `ondatachannel` handshake per stream, and the
  /// stream contract has no place to wait for one.
  ///
  /// [ordered] false with [maxRetransmits] 0 is the unreliable, unordered mode
  /// that makes this transport worth having for latency-critical sampling — a
  /// relay cannot offer it at all.
  Future<RtcChannel> openChannel(
    int id, {
    bool ordered = true,
    int? maxRetransmits,
  });

  /// Closes the connection and every channel on it.
  Future<void> close();
}

/// One data channel, carrying one [NetworkStream]'s traffic to one peer.
abstract interface class RtcChannel {
  /// The channel id both ends agreed on.
  int get id;

  /// Whether the channel is open for sending.
  bool get isOpen;

  /// Completes when the channel is open, or with an error if it never opens.
  Future<void> get ready;

  /// Inbound payloads: [String] for control traffic, [Uint8List] for samples.
  ///
  /// Broadcast — the stream mixin and its diagnostics both read it.
  Stream<Object> get messages;

  /// Sends a [String] or a [Uint8List]. Silently drops if not open, matching
  /// the publish-side guards on every existing transport.
  void send(Object payload);

  Future<void> close();
}

/// Connection state, reduced to what the transport actually branches on.
///
/// `RTCPeerConnectionState` has six values; the transport cares about three
/// things — can I send, is it over, is it over permanently — so the seam
/// carries three. Mapping the plugin's enum down happens in the binding.
enum RtcLinkState {
  /// Negotiating, or reconnecting after a transient ICE failure.
  connecting,

  /// Usable. Channels opened on it can send.
  connected,

  /// Gone. The transport releases the link and every channel on it.
  ///
  /// Terminal by construction: a peer that comes back gets a fresh node uId and
  /// is therefore a different peer, so there is nothing to reconnect to.
  closed,
}

/// The data-channel id for [streamName], derived identically on both peers.
///
/// `negotiated: true` requires both ends to pick the same integer without
/// exchanging anything, and the only thing both ends provably agree on before
/// the channel exists is the stream's name.
///
/// **Collision properties, stated plainly.** This is a hash into
/// `[reservedIds, maxChannelId]`, so two differently-named streams *can* collide,
/// and the consequence would be two streams silently sharing a channel. That is
/// a corruption bug, not a performance one, so `RtcMesh` asserts on collision at
/// open time rather than trusting the hash — within one process a collision
/// fails loudly instead of crossing the wire. A session whose streams collide
/// must rename one; there are 65024 ids and sessions have a handful of streams,
/// so this is a guard, not a workflow.
int rtcChannelIdFor(String streamName) {
  if (streamName == coordinationChannelName) return coordinationChannelId;
  // FNV-1a, 32-bit. Chosen for being short, stable across Dart versions and
  // platforms, and dependency-free — `streamName.hashCode` is none of those.
  var hash = 0x811c9dc5;
  for (final unit in streamName.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final span = maxChannelId - reservedChannelIds + 1;
  return reservedChannelIds + (hash % span);
}

/// The coordination stream's name, pinned to [coordinationChannelId].
///
/// The coordination stream is the one channel that must exist before anything
/// else can be agreed, so it does not go through the hash.
const String coordinationChannelName = 'coordination';

/// The coordination stream's reserved channel id.
const int coordinationChannelId = 0;

/// Ids below this are reserved; [rtcChannelIdFor] never returns one.
const int reservedChannelIds = 512;

/// The highest legal SCTP stream id.
const int maxChannelId = 65535;
