/// Streams whose data goes directly between peers.
///
/// The shape is `WsStreamMixin`'s, with exactly four hub calls replaced:
/// `announce` stays (discovery still runs through the hub), but `subscribe`,
/// `publishMessage` and `publishSample` become writes to a data channel.
///
/// Two consequences worth stating, because they are what a reader coming from
/// the WebSocket transport will expect and not find:
///
/// * **There is no slot.** A hub frame identifies its producer by a numeric
///   slot the hub assigns; a data channel identifies its producer by being that
///   channel. `WsSampleFrame` is still used verbatim for samples — the encoders
///   and `decodeChannels` are worth sharing — with its slot fields written as
///   zero and never read.
/// * **Routing is local.** `RelayRouting` in the hub becomes
///   `RtcMesh.subscribersFor`, filled by the `open` signal a subscriber sends.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/websocket.dart';

import '../rtc/rtc_adapter.dart';
import '../rtc/rtc_mesh.dart';
import '../transport/rtc_transport.dart';

/// Shared behaviour for streams carried on WebRTC data channels.
mixin RtcStreamMixin<T extends NetworkStreamConfig, M extends IMessage>
    on NetworkStream<T, M> {
  /// The hub socket, for announcing and for resolving publishers.
  WsConnection get connection;

  /// The peer connections this stream's channels live on.
  RtcMesh get mesh;

  String get sessionName;
  Node get streamNode;

  /// Whether this stream's channels are ordered.
  bool get channelOrdered => true;

  /// This stream's retransmission budget; null for fully reliable.
  int? get channelMaxRetransmits => null;

  final StreamController<M> _incoming = StreamController<M>.broadcast();
  final StreamController<M> _outgoing = StreamController<M>();
  StreamSubscription<M>? _outgoingSubscription;
  StreamSubscription<RtcChannelEvent>? _channelSubscription;
  StreamSubscription<String>? _peerLostSubscription;

  /// peer node uId -> its subscription to that peer's channel messages.
  final Map<String, StreamSubscription<Object>> _channelSubscriptions = {};

  /// Peers this stream has an inlet on, by node uId.
  ///
  /// Inbound is filtered against this and not against the channel's existence,
  /// because a channel is bidirectional and shared: a peer that subscribed to
  /// us gets a channel we can send on, and that channel is not licence for it
  /// to send to us.
  final Set<String> _subscribedPeers = {};

  /// Whether this node subscribed to its own output.
  ///
  /// Legitimate and load-bearing: `consumeCoordinationStreamAsCoordinator` has
  /// the coordinator read its own coordination stream, and several
  /// participation modes include the local node in the producer set. Through a
  /// hub this arrives as an ordinary relayed frame; with no hub it has to be
  /// looped back here.
  bool _selfSubscribed = false;

  bool _created = false;
  bool _disposed = false;
  bool _started = false;
  bool _publishing = false;
  IResourceManager? _manager;

  String get endpointId => descriptor.endpointId;

  PeerDescriptor get descriptor => PeerDescriptor.forNode(
    node: streamNode,
    streamName: config.name,
    sessionName: sessionName,
  );

  @override
  bool get created => _created;

  @override
  bool get disposed => _disposed;

  @override
  bool get started => _started;

  @override
  IResourceManager? get manager => _manager;

  @override
  void updateManager(IResourceManager? newManager) {
    _manager = resolveManagerUpdate(
      current: _manager,
      next: newManager,
      disposed: _disposed,
    );
  }

  @override
  Stream<M> get inbox => _incoming.stream;

  @override
  StreamSink<M> get outbox => _outgoing.sink;

  @override
  Future<void> create() async {
    if (_created) return;
    if (_disposed) throw StateError('Cannot create a disposed stream');
    _created = true;

    // Still announced to the hub, and for the same reason as on the WebSocket
    // transport: discovery, election and `createInletsForNodes` all resolve
    // peers by query. `publish: false` because this stream is not producing
    // yet — and, here, because the hub will never route a byte of it either
    // way.
    await connection.announce(descriptor, publish: false);

    // Channels arrive from both directions: one this node opened by
    // subscribing, and one a peer opened by subscribing to this node. Both
    // have to be listened to — the first to receive, the second so a peer that
    // subscribes later than we started is not silently ignored.
    _channelSubscription = mesh.channelOpened.listen((event) {
      if (event.streamName != config.name) return;
      _attach(event.peerNodeUId, event.channel);
    });
    for (final MapEntry(key: peer, value: channel)
        in mesh.channelsForStream(config.name).entries) {
      _attach(peer, channel);
    }

    // The transport notices a departure before the coordination layer's
    // heartbeats do, and holds a real connection behind every inlet, so it
    // releases its own rather than waiting to be told.
    _peerLostSubscription = mesh.peerLost.listen((peerNodeUId) {
      _subscribedPeers.remove(peerNodeUId);
      unawaited(_channelSubscriptions.remove(peerNodeUId)?.cancel());
    });

    _outgoingSubscription = _outgoing.stream.listen((message) {
      unawaited(Future.sync(() => sendMessage(message)));
    });
  }

  void _attach(String peerNodeUId, RtcChannel channel) {
    if (_disposed) return;
    if (_channelSubscriptions.containsKey(peerNodeUId)) return;
    _channelSubscriptions[peerNodeUId] = channel.messages.listen(
      (payload) => _onPayload(peerNodeUId, payload),
    );
  }

  void _onPayload(String peerNodeUId, Object payload) {
    if (_disposed || paused || !_started) return;
    if (!_subscribedPeers.contains(peerNodeUId)) return;

    if (payload is Uint8List) {
      if (!WsSampleFrame.isSample(payload)) return;
      final message = decodeSample(payload, peerNodeUId);
      if (message != null) _incoming.add(message);
      return;
    }
    final message = decodeControlPayload(payload);
    if (message != null) _incoming.add(message);
  }

  /// Builds a message from a binary sample frame sent by [fromNodeUId].
  ///
  /// The sender's identity is a parameter here rather than read out of the
  /// frame, as the WebSocket transport reads it out of the slot: the channel
  /// the frame arrived on already names its peer, exactly and without a lookup
  /// table.
  M? decodeSample(Uint8List frame, String fromNodeUId) => null;

  /// Builds a message from a control payload. Null for streams that carry none.
  M? decodeControlPayload(Object payload);

  @override
  Future<void> createOutlet() async {
    if (_disposed) return;
    _publishing = true;
    await connection.announce(descriptor);
  }

  @override
  Future<void> recreateOutlet() async {
    if (_disposed) return;
    // Republish: the node's role is part of its descriptor and election
    // changes it. The hub treats a repeat registration as an update.
    await connection.announce(descriptor);
    _publishing = true;
  }

  @override
  Future<void> addInlet(PeerHandle handle) async {
    if (_disposed) return;
    if (!handle.taken) handle.take();

    final peerNodeUId = handle.descriptor.nodeUId;
    try {
      // Self is not a dial. Whether a node consumes its own output is decided
      // above the transport by StreamParticipationMode, and several modes say
      // yes; a peer connection to oneself is not how to honour that.
      if (peerNodeUId == streamNode.uId) {
        _selfSubscribed = true;
        return;
      }
      if (!_subscribedPeers.add(peerNodeUId)) return;
      try {
        await mesh.channelFor(
          peerNodeUId: peerNodeUId,
          streamName: config.name,
          ordered: channelOrdered,
          maxRetransmits: channelMaxRetransmits,
        );
      } catch (_) {
        // A half-added inlet would filter inbound as if connected while
        // holding nothing, which reads as a silent delivery failure.
        _subscribedPeers.remove(peerNodeUId);
        rethrow;
      }
    } finally {
      await handle.dispose();
    }
  }

  @override
  Future<void> removeInlet(String nodeUId) async {
    if (nodeUId == streamNode.uId) {
      _selfSubscribed = false;
      return;
    }
    if (!_subscribedPeers.remove(nodeUId)) return;
    await _channelSubscriptions.remove(nodeUId)?.cancel();
    if (_disposed) return;
    // The point of the whole `removeInlet` contract: this releases an
    // `RTCPeerConnection`, and on the last stream between the pair the mesh
    // closes the connection itself. Without it a departed peer leaks until the
    // session is disposed.
    await mesh.releaseChannel(peerNodeUId: nodeUId, streamName: config.name);
  }

  @override
  Future<void> createInletsForNodes(
    Iterable<Node> nodes, {
    Duration resolveTimeout = const Duration(seconds: 10),
  }) async {
    if (nodes.isEmpty) return;
    final wanted = nodes.map((n) => n.uId).toSet();
    final deadline = DateTime.now().add(resolveTimeout);

    while (true) {
      final found = await _resolvePublishers(wanted);
      if (found.length >= wanted.length) {
        for (final handle in found) {
          await addInlet(handle);
        }
        return;
      }
      for (final handle in found) {
        await handle.dispose();
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw StateError(
          'Timed out resolving ${wanted.length} publisher(s) of '
          '"${config.name}"; found ${found.length}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<List<WsPeerHandle>> _resolvePublishers(Set<String> wanted) async {
    final query = PeerQueries.streamPublishers(
      streamName: config.name,
      sessionName: sessionName,
    );
    final completer = Completer<List<WsPeerHandle>>();
    final qid = connection.query(query);
    final subscription = connection.control.listen((frame) {
      if (frame.type != WsControl.queryResult) return;
      if (frame.payload['qid'] != qid) return;
      if (completer.isCompleted) return;
      completer.complete([
        for (final entry in (frame.payload['peers'] as List))
          if (wanted.contains(
            ((entry as Map<String, dynamic>)['peer']
                as Map<String, dynamic>)['nodeUId'],
          ))
            WsPeerHandle(
              PeerDescriptor.fromJson(entry['peer'] as Map<String, dynamic>),
            ),
      ]);
    });
    try {
      return await completer.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => const [],
      );
    } finally {
      await subscription.cancel();
    }
  }

  @override
  void updateNode(Node newNode) {
    if (newNode.uId != streamNode.uId) {
      throw ArgumentError('newNode must have the same uId');
    }
    setStreamNode(newNode);
  }

  void setStreamNode(Node node);

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
  }

  @override
  Future<void> stop() async {
    if (!_started || _disposed) return;
    _started = false;
    if (!paused) await pause();
  }

  @override
  Future<void> destroyStream() async {
    if (_disposed) return;
    await stop();
    for (final peerNodeUId in _subscribedPeers.toList(growable: false)) {
      await removeInlet(peerNodeUId);
    }
    _subscribedPeers.clear();
    _selfSubscribed = false;
    _publishing = false;
  }

  @override
  FutureOr<void> sendMessage(M message) {
    if (_disposed || !_started || paused || !_publishing) return null;
    final payload = encodeForWire(message);
    _broadcast(payload);
    if (_selfSubscribed) _loopback(() => decodeControlPayload(payload));
    return null;
  }

  /// Wire form of [message] for the control path.
  String encodeForWire(M message);

  /// Publishes a sample using the shared binary framing.
  void publishSample(List<Object?> channels) {
    if (_disposed || !_started || paused) return;
    final frame = WsSampleFrame.encode(
      dataType: config.dataType,
      // Slots exist for the hub to demultiplex a shared socket. There is no
      // shared socket here — the channel is the demultiplexer — so these are
      // written as zero and never read back.
      streamSlot: 0,
      srcSlot: 0,
      // PeerClock, not DateTime.now(): the receiver reads this to measure
      // transit, and a wall clock can be stepped by NTP mid-session, which
      // would surface as a latency spike that never happened.
      senderMicros: PeerClock.nowMicros().toDouble(),
      channels: channels,
    );
    _broadcast(frame);
    if (_selfSubscribed) {
      _loopback(() => decodeSample(frame, streamNode.uId));
    }
  }

  /// Writes [payload] to every peer that asked for this stream.
  void _broadcast(Object payload) {
    for (final peerNodeUId in mesh.subscribersFor(config.name)) {
      mesh
          .existingChannel(peerNodeUId: peerNodeUId, streamName: config.name)
          ?.send(payload);
    }
  }

  /// Delivers a message this node sent to this node, asynchronously.
  ///
  /// The hop matters. Through a relay this arrives as an ordinary inbound
  /// frame on a later turn of the event loop, and a synchronous loopback would
  /// let a caller observe its own message before `sendData` returned —
  /// behaviour no real transport has.
  void _loopback(M? Function() decode) {
    scheduleMicrotask(() {
      if (_disposed || paused || !_started) return;
      final message = decode();
      if (message != null && !_incoming.isClosed) _incoming.add(message);
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await destroyStream();
    _disposed = true;
    _created = false;
    await _channelSubscription?.cancel();
    await _peerLostSubscription?.cancel();
    await _outgoingSubscription?.cancel();
    for (final subscription in _channelSubscriptions.values) {
      await subscription.cancel();
    }
    _channelSubscriptions.clear();
    unawaited(_incoming.close());
    unawaited(_outgoing.close());
  }
}

/// Coordination stream over a data channel. Reliable, ordered, JSON.
///
/// Reliability is not configurable here, unlike on a data stream: this carries
/// election and topology decisions, and a lost or reordered one splits the
/// session.
class RtcCoordinationStream
    extends CoordinationStream<CoordinationStreamConfig, StringMessage>
    with InstanceUID, RtcStreamMixin<CoordinationStreamConfig, StringMessage> {
  RtcCoordinationStream({
    required CoordinationStreamConfig config,
    required this.connection,
    required this.mesh,
    required this.sessionName,
    required Node streamNode,
  }) : _streamNode = streamNode,
       super(config);

  @override
  final WsConnection connection;

  @override
  final RtcMesh mesh;

  @override
  final String sessionName;

  Node _streamNode;

  @override
  Node get streamNode => _streamNode;

  @override
  void setStreamNode(Node node) => _streamNode = node;

  @override
  String? get description =>
      'WebRTC coordination stream "${config.name}" for ${_streamNode.id}';

  @override
  String encodeForWire(StringMessage message) => message.data.first;

  @override
  StringMessage? decodeControlPayload(Object payload) {
    if (payload is! String) return null;
    return MessageFactory.stringMessage(
      data: IList([payload]),
      channels: 1,
      // Only the local half. The control path has no envelope to hang a sender
      // clock on, so the sender stamps one inside the coordination payload
      // instead and the controller pairs the two up. See
      // CoordinationMessage.senderClockKey.
      timing: MessageTiming(receivedClock: PeerClock.now()),
    );
  }
}

/// Data stream over a data channel.
///
/// Samples use the binary framing shared with the WebSocket transport: data
/// streams are the latency-critical path and their shape is fixed by the
/// negotiated config, so JSON would be pure overhead on every sample.
class RtcDataStream extends DataStream<DataStreamConfig, IMessage>
    with InstanceUID, RtcStreamMixin<DataStreamConfig, IMessage> {
  RtcDataStream({
    required DataStreamConfig config,
    required this.connection,
    required this.mesh,
    required this.sessionName,
    required Node streamNode,
    this.clockOffsets,
    this.channelOrdered = true,
    this.channelMaxRetransmits,
  }) : _streamNode = streamNode,
       super(config);

  @override
  final WsConnection connection;

  @override
  final RtcMesh mesh;

  @override
  final String sessionName;

  /// Per-peer clock offsets, estimated on the coordination stream and shared
  /// across every stream on this transport.
  final PeerClockOffsets? clockOffsets;

  @override
  final bool channelOrdered;

  @override
  final int? channelMaxRetransmits;

  Node _streamNode;

  @override
  Node get streamNode => _streamNode;

  @override
  void setStreamNode(Node node) => _streamNode = node;

  @override
  String? get description =>
      'WebRTC data stream "${config.name}" for ${_streamNode.id}';

  @override
  Future<void> sendData(Iterable<dynamic> data) async {
    if (!started) throw StateError('Stream not started');
    config.validateSample(data);
    publishSample(data.toList(growable: false));
  }

  @override
  Future<void> sendDataTyped<S>(Iterable<S> data) async {
    if (!started) throw StateError('Stream not started');
    config.validateSample(data);
    publishSample(data.toList(growable: false));
  }

  @override
  IMessage? decodeSample(Uint8List frame, String fromNodeUId) {
    final channels = WsSampleFrame.decodeChannels(frame, config.channels);
    final timestamp = DateTime.now();
    final offsets = clockOffsets;
    final timing = MessageTiming(
      sourceClock: WsSampleFrame.senderMicrosOf(frame) / 1e6,
      // Null until the estimator has accepted a burst for this peer, which
      // keeps transitSeconds null rather than reporting the difference of two
      // unrelated monotonic clocks.
      clockOffset: offsets?.offsetFor(fromNodeUId),
      uncertainty: offsets?.uncertaintyFor(fromNodeUId),
      receivedClock: PeerClock.now(),
      sourceId: fromNodeUId,
    );
    switch (config.dataType) {
      case StreamDataType.float32:
      case StreamDataType.double64:
        return MessageFactory.double64Message(
          data: IList(channels.map((v) => (v! as num).toDouble())),
          channels: config.channels,
          timestamp: timestamp,
          timing: timing,
        );
      case StreamDataType.int8:
      case StreamDataType.int16:
      case StreamDataType.int32:
      case StreamDataType.int64:
        return MessageFactory.int64Message(
          data: IList(channels.cast<int>()),
          channels: config.channels,
          timestamp: timestamp,
          timing: timing,
        );
      case StreamDataType.string:
        return MessageFactory.stringMessage(
          data: IList(channels.cast<String>()),
          channels: config.channels,
          timestamp: timestamp,
          timing: timing,
        );
    }
  }

  @override
  String encodeForWire(IMessage message) => jsonEncode(message.data.toList());

  @override
  IMessage? decodeControlPayload(Object payload) => null;
}

/// Builds WebRTC streams for a session.
///
/// Also where the mesh is built: this is the first place a session object is in
/// hand, and the mesh cannot exist before one — it is keyed on this node's uId
/// and addressed by the coordination stream's name.
class RtcNetworkStreamFactory extends NetworkStreamFactory {
  RtcNetworkStreamFactory(this.transport);

  final RtcTransport transport;

  @override
  Future<RtcDataStream> createDataStream(
    DataStreamConfig config,
    CoordinationSession session,
  ) async => RtcDataStream(
    config: config,
    connection: transport.connection,
    mesh: transport.meshFor(session),
    sessionName: session.config.name,
    streamNode: session.thisNode,
    clockOffsets: transport.clockOffsets,
    channelOrdered: transport.config.dataOrdered,
    channelMaxRetransmits: transport.config.dataMaxRetransmits,
  );

  @override
  Future<RtcCoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config,
    CoordinationSession session,
  ) async => RtcCoordinationStream(
    config: config,
    connection: transport.connection,
    mesh: transport.meshFor(session, coordinationStreamName: config.name),
    sessionName: session.config.name,
    streamNode: session.thisNode,
  );
}
