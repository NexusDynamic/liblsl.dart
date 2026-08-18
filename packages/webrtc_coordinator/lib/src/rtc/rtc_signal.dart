/// The signalling envelope carried inside `WsControl.signal`.
///
/// The hub forwards these verbatim without looking inside — it verifies only
/// that the sender owns the `from` endpoint — so the shape is entirely between
/// the two peers.
library;

/// What a signal is.
///
/// [open] is the one kind with no WebRTC counterpart. Data channels here are
/// `negotiated: true`, so neither end learns about the other's channel from the
/// connection itself, and a producer in an asymmetric participation mode has no
/// reason of its own to open one. [open] is a subscriber saying "open your half
/// of stream S" — which is also, and deliberately, the only subscribe this
/// transport has: the hub is not routing, so the far end's channel list *is*
/// the routing table.
enum RtcSignalKind { offer, answer, candidate, open, bye }

/// One signalling message between two peers.
///
/// [fromNodeUId] is carried explicitly rather than parsed back out of the
/// hub-verified endpoint id. The two must agree — `RtcMesh` checks that they do
/// — but the transport keys everything on node uIds, and an envelope that
/// states its own sender is one less positional parse in the hot path of
/// connection setup.
class RtcSignal {
  const RtcSignal({
    required this.kind,
    required this.fromNodeUId,
    this.payload = const {},
  });

  final RtcSignalKind kind;
  final String fromNodeUId;

  /// An SDP map for offer/answer, a candidate map for candidate, a
  /// `{'s': streamName, 'id': channelId, 'o': ordered, 'r': maxRetransmits}`
  /// map for open, empty for bye.
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'k': kind.name,
    'from': fromNodeUId,
    if (payload.isNotEmpty) 'p': payload,
  };

  /// Parses a payload that arrived over the hub.
  ///
  /// Returns null rather than throwing on anything unrecognised: this decodes
  /// data from another peer, and one malformed frame must not take down the
  /// signalling listener for every other peer.
  static RtcSignal? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kindName = raw['k'];
    final from = raw['from'];
    if (kindName is! String || from is! String || from.isEmpty) return null;
    final kind = RtcSignalKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    if (kind == null) return null;
    final payload = raw['p'];
    return RtcSignal(
      kind: kind,
      fromNodeUId: from,
      payload: payload is Map
          ? payload.map((k, v) => MapEntry(k.toString(), v))
          : const {},
    );
  }
}
