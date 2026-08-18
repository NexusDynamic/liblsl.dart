/// The WebRTC transport: a hub for discovery and signalling, data direct.
library;

import 'dart:async';

import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/websocket.dart';

import '../rtc/rtc_adapter.dart';
import '../rtc/rtc_mesh.dart';
import '../streams/rtc_stream.dart';

/// Builds the WebRTC implementation for one node.
///
/// [selfNodeUId] is the key the remote side will name this peer by, and is what
/// a binding should use for any per-process WebRTC identity it needs.
typedef RtcAdapterFactory = RtcPeerAdapter Function(String selfNodeUId);

/// Configuration for the WebRTC transport.
class RtcTransportConfig implements ITransportConfig {
  RtcTransportConfig({
    required this.hubUri,
    required this.adapterFactory,
    this.iceServers = const [],
    this.connectTimeout = const Duration(seconds: 10),
    this.channelTimeout = const Duration(seconds: 15),
    this.dataOrdered = true,
    this.dataMaxRetransmits,
  });

  /// Where the signalling hub is listening, e.g. `ws://127.0.0.1:8080`.
  ///
  /// The same `peer_coordinator` hub the WebSocket transport uses — this
  /// transport simply stops sending it data. It still carries discovery
  /// queries and the offer/answer/candidate traffic, because two peers that
  /// have never met cannot exchange an offer over the connection the offer is
  /// for.
  final Uri hubUri;

  /// Builds the [RtcPeerAdapter] this node dials with.
  ///
  /// A factory rather than an instance because the adapter is keyed on this
  /// node's uId, which does not exist until a session is running — and because
  /// it is the one seam that keeps `flutter_webrtc` out of this package. Pass
  /// `FakeRtcPeerAdapter.new`-style closures in tests;
  /// `webrtc_coordinator_flutter` exports one backed by the plugin.
  final RtcAdapterFactory adapterFactory;

  /// ICE servers, in the standard `{'urls': ...}` form.
  ///
  /// Empty by default: host candidates only, which is pure LAN
  /// peer-to-peer with no third party involved and covers the open-network
  /// case this transport exists for. Add STUN to cross a NAT.
  ///
  /// **TURN reintroduces a relay.** A TURN-relayed connection is peer-to-peer
  /// in name only — the bytes go through someone else's server, exactly as
  /// they do through the hub — so the halved hop count this transport is for
  /// does not survive it. "Genuinely peer-to-peer" here means host and srflx
  /// candidates.
  final List<Map<String, Object?>> iceServers;

  /// How long to wait for the hub socket.
  final Duration connectTimeout;

  /// How long to wait for a data channel to a peer to open.
  ///
  /// Longer than [connectTimeout] because it covers an ICE handshake, not a
  /// single TCP connect.
  final Duration channelTimeout;

  /// Whether data-stream channels are ordered. Coordination is always ordered
  /// and reliable regardless — it carries election and topology decisions, and
  /// a lost one splits the session.
  final bool dataOrdered;

  /// Retransmission budget for data-stream channels. Null means fully
  /// reliable; `0` with [dataOrdered] false is fire-and-forget, which is the
  /// mode a latency-critical sampling stream wants and which no relay can
  /// offer at all.
  final int? dataMaxRetransmits;

  @override
  String get id => 'rtc_transport_config';

  @override
  String get name => 'WebRTC Transport Configuration';

  @override
  String get description =>
      'Coordination over direct WebRTC data channels, signalled through a hub';

  @override
  ITransport createTransport() => RtcTransport(this);

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
    if (dataMaxRetransmits != null && dataMaxRetransmits! < 0) {
      if (throwOnError) {
        throw ArgumentError.value(
          dataMaxRetransmits,
          'dataMaxRetransmits',
          'must not be negative',
        );
      }
      return false;
    }
    return true;
  }

  @override
  RtcTransportConfig copyWith({
    Uri? hubUri,
    RtcAdapterFactory? adapterFactory,
    List<Map<String, Object?>>? iceServers,
    Duration? connectTimeout,
    Duration? channelTimeout,
    bool? dataOrdered,
    int? dataMaxRetransmits,
  }) => RtcTransportConfig(
    hubUri: hubUri ?? this.hubUri,
    adapterFactory: adapterFactory ?? this.adapterFactory,
    iceServers: iceServers ?? this.iceServers,
    connectTimeout: connectTimeout ?? this.connectTimeout,
    channelTimeout: channelTimeout ?? this.channelTimeout,
    dataOrdered: dataOrdered ?? this.dataOrdered,
    dataMaxRetransmits: dataMaxRetransmits ?? this.dataMaxRetransmits,
  );

  /// Serialised form.
  ///
  /// [adapterFactory] is deliberately absent: it is a closure, so it has no
  /// serialised form, and a config read back from a map has to be given one by
  /// the application anyway — which is the same decision as choosing a
  /// platform.
  @override
  Map<String, dynamic> toMap() => {
    'type': 'webrtc',
    'hubUri': hubUri.toString(),
    'iceServers': iceServers,
    'connectTimeoutMs': connectTimeout.inMilliseconds,
    'channelTimeoutMs': channelTimeout.inMilliseconds,
    'dataOrdered': dataOrdered,
    'dataMaxRetransmits': dataMaxRetransmits,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtcTransportConfig &&
          other.hubUri == hubUri &&
          other.adapterFactory == adapterFactory &&
          other.connectTimeout == connectTimeout &&
          other.channelTimeout == channelTimeout &&
          other.dataOrdered == dataOrdered &&
          other.dataMaxRetransmits == dataMaxRetransmits &&
          _sameIceServers(other.iceServers, iceServers);

  @override
  int get hashCode => Object.hash(
    hubUri,
    adapterFactory,
    connectTimeout,
    channelTimeout,
    dataOrdered,
    dataMaxRetransmits,
    iceServers.length,
  );

  static bool _sameIceServers(
    List<Map<String, Object?>> a,
    List<Map<String, Object?>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (final entry in a[i].entries) {
        if (b[i][entry.key] != entry.value) return false;
      }
    }
    return true;
  }
}

/// Coordination over direct WebRTC data channels.
///
/// The hub is still here, and still required, but only for discovery queries
/// and for signalling. No message and no sample crosses it: once two peers have
/// exchanged an offer and an answer through it, everything else goes down the
/// data channel between them. That is one network hop instead of two, and it
/// makes unreliable, unordered delivery available — which a relay cannot offer
/// at all.
///
/// Web-safe: nothing here touches `dart:io`. The plugin binding that does is in
/// `webrtc_coordinator_flutter`, behind [RtcAdapterFactory].
class RtcTransport extends ManagedResource
    implements ITransport<RtcTransportConfig>, IResourceManager {
  RtcTransport(this.config)
    : _connection = WsConnection(config.hubUri),
      super(id: 'rtc_transport');

  @override
  final RtcTransportConfig config;

  final WsConnection _connection;

  /// The socket this node holds to the hub, for discovery and signalling.
  WsConnection get connection => _connection;

  /// Peer clock offsets for this process.
  ///
  /// Non-null, and now measuring something worth measuring: with the hub off
  /// the data path, [ClockSyncService]'s round trip is the real peer-to-peer
  /// path rather than two relay hops.
  @override
  final PeerClockOffsets clockOffsets = PeerClockOffsets();

  final Map<String, IResource> _resources = {};
  RtcMesh? _mesh;
  RtcNetworkStreamFactory? _streamFactory;
  bool _initialized = false;

  @override
  String get name => 'WebRTC Transport';

  @override
  String get description =>
      'Coordination over direct WebRTC data channels, signalled through a hub';

  @override
  bool get initialized => _initialized;

  /// The mesh, once a session has built one. Null before the first stream.
  RtcMesh? get mesh => _mesh;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    config.validate(throwOnError: true);
    await _connection.connect(timeout: config.connectTimeout);
    _initialized = true;
  }

  /// Builds the mesh, or returns the one already built.
  ///
  /// Deferred to here rather than done in [initialize] because the mesh is
  /// keyed on this node's uId and addressed by the coordination stream's name,
  /// and neither exists until a [CoordinationSession] is running: `initialize`
  /// runs with only a transport config in hand.
  ///
  /// [coordinationStreamName] is required on the first call and ignored
  /// afterwards. Only `createCoordinationStream` can supply it, which is why
  /// the order in `CoordinationController.initialize` matters: the coordination
  /// stream is built before discovery and before any data stream, so by the
  /// time anything else asks, the mesh exists.
  RtcMesh meshFor(
    CoordinationSession session, {
    String? coordinationStreamName,
  }) {
    final existing = _mesh;
    if (existing != null) return existing;
    if (coordinationStreamName == null) {
      throw StateError(
        'The WebRTC mesh is addressed by the coordination stream\'s name, so '
        'it cannot be built before that stream exists. Reaching this means a '
        'data stream was created on a session that never built a coordination '
        'stream.',
      );
    }
    return _mesh = RtcMesh(
      adapter: config.adapterFactory(session.thisNode.uId),
      connection: _connection,
      selfNodeUId: session.thisNode.uId,
      sessionName: session.config.name,
      coordinationStreamName: coordinationStreamName,
      iceServers: config.iceServers,
      connectTimeout: config.channelTimeout,
    );
  }

  @override
  NetworkStreamFactory get streamFactory =>
      _streamFactory ??= RtcNetworkStreamFactory(this);

  @override
  Future<IDiscovery> createDiscovery({
    required NetworkStreamConfig streamConfig,
    required CoordinationConfig coordinationConfig,
    required String id,
  }) async {
    // Verbatim reuse. Discovery and the data path are independent in
    // `ITransport` — nothing links the `streamFactory` to `createDiscovery` —
    // so the hub keeps doing the half it is good at.
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
    // Before the socket: `releasePeer` sends a courtesy `bye` through it.
    await _mesh?.close();
    _mesh = null;
    await _connection.close();
    await super.dispose();
  }
}
