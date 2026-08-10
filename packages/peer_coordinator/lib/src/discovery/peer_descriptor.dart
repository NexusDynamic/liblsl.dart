import 'package:peer_coordinator/framework.dart';

/// A peer discovered on the network, described in transport-neutral terms.
///
/// Every transport resolves peers in its own way — LSL by multicast-resolving
/// stream metadata, a WebSocket hub by listing connected clients — but they all
/// produce the same facts, and [DiscoveryQuery] filters on exactly these
/// fields.
class PeerDescriptor {
  const PeerDescriptor({
    required this.streamName,
    required this.sessionName,
    required this.nodeId,
    required this.nodeUId,
    required this.nodeRole,
    required this.endpointId,
    this.capabilities = const {},
    this.randomRoll,
    this.startedAt,
    this.extra = const {},
  });

  /// Name of the stream this peer publishes (`coordination`, `TestData`, ...).
  final String streamName;

  /// Session the peer belongs to. Peers in other sessions are not ours.
  final String sessionName;

  /// Human-facing node id. Not guaranteed unique — use [nodeUId] for identity.
  final String nodeId;

  /// The node's unique identity. This is the key everything else joins on.
  final String nodeUId;

  /// Current role, as [NodeCapability.shortString].
  final String nodeRole;

  /// Capabilities the node declares it *could* take on, which is not the same
  /// as the role it currently holds.
  final Set<String> capabilities;

  /// Election tie-breaker; null if the peer did not publish one.
  final double? randomRoll;

  /// ISO-8601 start time. Lexicographic order is chronological order.
  final String? startedAt;

  /// Transport-specific extras (hostname, ports, connection id, ...).
  ///
  /// Never interpreted by the coordination layer — purely for diagnostics.
  final Map<String, String> extra;

  /// Stable per-endpoint dedupe key.
  ///
  /// LSL uses the raw `source_id`; hub-based transports use
  /// `<session>/<nodeUId>/<streamName>`. Two descriptors for the same endpoint
  /// must produce the same value, and no two live endpoints may collide.
  final String endpointId;

  /// Whether this peer holds the coordinator role right now.
  bool get isCoordinator => nodeRole == NodeCapability.coordinator.shortString;

  /// Builds the descriptor a node publishes for one of its own streams.
  factory PeerDescriptor.forNode({
    required Node node,
    required String streamName,
    required String sessionName,
    String? endpointId,
    Map<String, String> extra = const {},
  }) {
    final roll = node.getMetadata(PeerMetadataKeys.randomRoll);
    return PeerDescriptor(
      streamName: streamName,
      sessionName: sessionName,
      nodeId: node.id,
      nodeUId: node.uId,
      nodeRole: node.role,
      capabilities: node.capabilities.map((c) => c.shortString).toSet(),
      randomRoll: roll is String ? double.tryParse(roll) : roll as double?,
      startedAt: node.getMetadata(PeerMetadataKeys.nodeStartedAt) as String?,
      endpointId: endpointId ?? '$sessionName/${node.uId}/$streamName',
      extra: extra,
    );
  }

  /// The legacy LSL `source_id` encoding: `stream//role//uId//nodeId`.
  ///
  /// Kept byte-identical to the original format so a node running this code
  /// still interoperates with one running the previous version.
  ///
  /// The encoding is positional with no escaping, so a `//` inside any
  /// component corrupts parsing. [assertSourceIdSafe] catches that at the
  /// point the value is chosen rather than at parse time on a remote machine.
  String toSourceId() => '$streamName//$nodeRole//$nodeUId//$nodeId';

  /// Parses the LSL `source_id` encoding.
  ///
  /// [desc] carries the richer fields that LSL publishes as stream XML
  /// metadata and that `source_id` has no room for.
  factory PeerDescriptor.fromSourceId(
    String sourceId, {
    Map<String, String> desc = const {},
    Map<String, String> extra = const {},
  }) {
    final parts = sourceId.split('//');
    if (parts.length < 4) {
      throw FormatException('Invalid source_id format: $sourceId', sourceId);
    }
    if (parts.length > 4) {
      // Positional parsing cannot recover from this; failing loudly beats
      // silently attributing a stream to the wrong node.
      throw FormatException(
        'source_id has ${parts.length} "//"-separated segments, expected 4. '
        'A stream name, role, uId or node id contains "//": $sourceId',
        sourceId,
      );
    }
    final roll = desc['random_roll'];
    return PeerDescriptor(
      streamName: parts[0],
      nodeRole: parts[1],
      nodeUId: parts[2],
      nodeId: parts[3],
      sessionName: desc['session'] ?? '',
      capabilities:
          desc['node_capabilities']
              ?.split(',')
              .where((c) => c.isNotEmpty)
              .toSet() ??
          const {},
      randomRoll: roll == null ? null : double.tryParse(roll),
      startedAt: desc['node_started_at'],
      endpointId: sourceId,
      extra: extra,
    );
  }

  /// Throws if [value] cannot survive the positional `source_id` encoding.
  ///
  /// Call this when a stream name or node id is *chosen*, so the failure lands
  /// on the machine that made the bad choice.
  static void assertSourceIdSafe(String value, String what) {
    if (value.contains('//')) {
      throw ArgumentError.value(
        value,
        what,
        'must not contain "//" — it is the source_id field separator',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'streamName': streamName,
    'sessionName': sessionName,
    'nodeId': nodeId,
    'nodeUId': nodeUId,
    'nodeRole': nodeRole,
    'capabilities': capabilities.toList(),
    if (randomRoll != null) 'randomRoll': randomRoll,
    if (startedAt != null) 'startedAt': startedAt,
    'endpointId': endpointId,
    if (extra.isNotEmpty) 'extra': extra,
  };

  factory PeerDescriptor.fromJson(Map<String, dynamic> json) => PeerDescriptor(
    streamName: json['streamName'] as String,
    sessionName: json['sessionName'] as String,
    nodeId: json['nodeId'] as String,
    nodeUId: json['nodeUId'] as String,
    nodeRole: json['nodeRole'] as String,
    capabilities:
        (json['capabilities'] as List?)?.map((c) => c as String).toSet() ??
        const {},
    randomRoll: (json['randomRoll'] as num?)?.toDouble(),
    startedAt: json['startedAt'] as String?,
    endpointId: json['endpointId'] as String,
    extra:
        (json['extra'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
        const {},
  );

  PeerDescriptor copyWith({String? nodeRole, Map<String, String>? extra}) =>
      PeerDescriptor(
        streamName: streamName,
        sessionName: sessionName,
        nodeId: nodeId,
        nodeUId: nodeUId,
        nodeRole: nodeRole ?? this.nodeRole,
        capabilities: capabilities,
        randomRoll: randomRoll,
        startedAt: startedAt,
        endpointId: endpointId,
        extra: extra ?? this.extra,
      );

  @override
  String toString() =>
      'PeerDescriptor($nodeId/$nodeUId role=$nodeRole '
      'stream=$streamName session=$sessionName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerDescriptor &&
          other.endpointId == endpointId &&
          other.nodeUId == nodeUId &&
          other.nodeRole == nodeRole &&
          other.streamName == streamName &&
          other.sessionName == sessionName;

  @override
  int get hashCode =>
      Object.hash(endpointId, nodeUId, nodeRole, streamName, sessionName);
}
