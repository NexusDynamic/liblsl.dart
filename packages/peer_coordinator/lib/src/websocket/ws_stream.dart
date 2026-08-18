import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/src/websocket/ws_connection.dart';
import 'package:peer_coordinator/src/websocket/ws_discovery.dart';
import 'package:peer_coordinator/src/websocket/ws_protocol.dart';

/// Shared behaviour for WebSocket-backed streams.
///
/// Publishing is a frame to the hub; subscribing is a `subscribe` control
/// frame that installs a route there. No isolate and no polling: unlike
/// liblsl, a WebSocket is already non-blocking and event-driven.
mixin WsStreamMixin<T extends NetworkStreamConfig, M extends IMessage>
    on NetworkStream<T, M> {
  WsConnection get connection;
  String get sessionName;
  Node get streamNode;

  final StreamController<M> _incoming = StreamController<M>.broadcast();
  final StreamController<M> _outgoing = StreamController<M>();
  StreamSubscription<WsInbound>? _inboundSubscription;
  StreamSubscription<M>? _outgoingSubscription;

  bool _created = false;
  bool _disposed = false;
  bool _started = false;
  bool _publishing = false;
  IResourceManager? _manager;

  /// Hub slot for this stream's own endpoint, learned from `welcome`.
  int? _slot;

  /// Producers we are subscribed to, and their slots (for binary demuxing).
  final Set<String> _subscribedProducers = {};

  /// Hub slot -> the node uId that owns it, for producers we subscribed to.
  ///
  /// A map rather than a set of slots because a sample frame identifies its
  /// producer only by slot, and a slot means nothing to a consumer trying to
  /// look up that peer's clock offset or report who sent a sample. The uId is
  /// already in hand on the [WsPeerHandle] at subscription time; it just used to
  /// be discarded here.
  final Map<int, String> _slotOwners = {};

  /// nodeUId -> the producer endpoint id this stream subscribed to.
  ///
  /// [removeInlet] is keyed on nodeUId (the only identifier stable across a
  /// role change on every transport), but the hub routes on endpoint ids, so
  /// the translation has to be remembered at subscribe time.
  final Map<String, String> _producerByNodeUId = {};

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

    // Claim a routing identity up front. A stream that only consumes never
    // calls createOutlet, and without this the hub would have no way to
    // deliver to it.
    _slot = await connection.announce(descriptor, publish: false);
    _inboundSubscription = connection.inbound.listen(_onInbound);
    _outgoingSubscription = _outgoing.stream.listen((message) {
      unawaited(Future.sync(() => sendMessage(message)));
    });
  }

  void _onInbound(WsInbound inbound) {
    if (_disposed || paused || !_started) return;
    final payload = inbound.payload;

    if (payload is Uint8List) {
      // Binary sample. Only ours if it came from a producer we subscribed to.
      if (!WsSampleFrame.isSample(payload)) return;
      if (!_slotOwners.containsKey(WsSampleFrame.sourceSlotOf(payload))) {
        return;
      }
      final message = decodeSample(payload);
      if (message != null) _incoming.add(message);
      return;
    }

    if (inbound.streamName != config.name) return;
    if (!_subscribedProducers.contains(inbound.fromEndpointId)) return;
    final message = decodeControlPayload(payload);
    if (message != null) _incoming.add(message);
  }

  /// Builds a message from a binary sample frame. Null for streams that do
  /// not carry samples.
  M? decodeSample(Uint8List frame) => null;

  /// Builds a message from a relayed JSON payload.
  M? decodeControlPayload(Object payload);

  @override
  Future<void> createOutlet() async {
    if (_disposed) return;
    _publishing = true;
    _slot = await connection.announce(descriptor);
  }

  @override
  Future<void> recreateOutlet() async {
    if (_disposed) return;
    // Republish: the node's role is part of its descriptor and election
    // changes it. The hub treats a repeat registration as an update.
    _slot = await connection.announce(descriptor);
    _publishing = true;
  }

  @override
  Future<void> addInlet(PeerHandle handle) async {
    if (_disposed) return;
    if (!handle.taken) handle.take();

    final producer = handle.descriptor.endpointId;
    // Deliberately no self-check here. Whether a node consumes its own
    // output is decided by StreamParticipationMode via
    // PeerSession.getProducersForStream — allNodes, coordinatorOnly and
    // sendAllReceiveCoordinator all legitimately include the local node — and
    // `consumeCoordinationStreamAsCoordinator` has the coordinator subscribe
    // to its own coordination stream on purpose. A transport that silently
    // skipped self would override those decisions.
    if (!_subscribedProducers.add(producer)) return;
    if (handle is WsPeerHandle && handle.slot != null) {
      _slotOwners[handle.slot!] = handle.descriptor.nodeUId;
    }
    _producerByNodeUId[handle.descriptor.nodeUId] = producer;

    connection.subscribe(
      streamName: config.name,
      subscriberEndpointId: endpointId,
      producerEndpointIds: [producer],
    );
    await handle.dispose();
  }

  @override
  Future<void> removeInlet(String nodeUId) async {
    final producer = _producerByNodeUId.remove(nodeUId);
    if (producer == null) return;
    _subscribedProducers.remove(producer);
    _slotOwners.removeWhere((_, owner) => owner == nodeUId);
    if (_disposed) return;
    // Both halves matter. Dropping the producer locally stops delivery even if
    // the frame never lands; the frame stops the hub spending bandwidth on it.
    connection.unsubscribe(
      streamName: config.name,
      subscriberEndpointId: endpointId,
      producerEndpointIds: [producer],
    );
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
              slot: entry['slot'] as int?,
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
    _subscribedProducers.clear();
    _slotOwners.clear();
    _producerByNodeUId.clear();
    _publishing = false;
  }

  @override
  FutureOr<void> sendMessage(M message) {
    if (_disposed || !_started || paused || !_publishing) return null;
    connection.publishMessage(
      streamName: config.name,
      fromEndpointId: endpointId,
      payload: encodeForWire(message),
    );
    return null;
  }

  /// JSON-encodable form of [message] for the control path.
  Object encodeForWire(M message);

  /// Publishes a sample using the binary framing.
  void publishSample(List<Object?> channels) {
    final slot = _slot;
    if (slot == null || _disposed || !_started || paused) return;
    connection.publishSample(
      WsSampleFrame.encode(
        dataType: config.dataType,
        streamSlot: slot,
        srcSlot: slot,
        // PeerClock, not DateTime.now(): the receiver reads this to measure
        // transit, and a wall clock can be stepped by NTP mid-session, which
        // would surface as a latency spike that never happened.
        senderMicros: PeerClock.nowMicros().toDouble(),
        channels: channels,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await destroyStream();
    _disposed = true;
    _created = false;
    await _inboundSubscription?.cancel();
    await _outgoingSubscription?.cancel();
    unawaited(_incoming.close());
    unawaited(_outgoing.close());
  }
}

/// Coordination stream over a hub. Reliable, ordered, JSON.
class WsCoordinationStream
    extends CoordinationStream<CoordinationStreamConfig, StringMessage>
    with InstanceUID, WsStreamMixin<CoordinationStreamConfig, StringMessage> {
  WsCoordinationStream({
    required CoordinationStreamConfig config,
    required this.connection,
    required this.sessionName,
    required this._streamNode,
  }) : super(config);

  @override
  final WsConnection connection;

  @override
  final String sessionName;

  Node _streamNode;

  @override
  Node get streamNode => _streamNode;

  @override
  void setStreamNode(Node node) => _streamNode = node;

  @override
  String? get description =>
      'WebSocket coordination stream "${config.name}" for ${_streamNode.id}';

  @override
  Object encodeForWire(StringMessage message) => message.data.first;

  @override
  StringMessage? decodeControlPayload(Object payload) {
    if (payload is! String) return null;
    return MessageFactory.stringMessage(
      data: IList([payload]),
      channels: 1,
      // Only the local half. The control path is JSON with no envelope to hang
      // a sender clock on, so the sender stamps one inside the coordination
      // payload instead and the controller pairs the two up. See
      // CoordinationMessage.senderClockKey.
      timing: MessageTiming(receivedClock: PeerClock.now()),
    );
  }
}

/// Data stream over a hub.
///
/// Samples use the binary framing: data streams are the latency-critical path
/// and their shape is fixed by the negotiated config, so JSON would be pure
/// overhead on every sample.
class WsDataStream extends DataStream<DataStreamConfig, IMessage>
    with InstanceUID, WsStreamMixin<DataStreamConfig, IMessage> {
  WsDataStream({
    required DataStreamConfig config,
    required this.connection,
    required this.sessionName,
    required this._streamNode,
    this.clockOffsets,
  }) : super(config);

  @override
  final WsConnection connection;

  @override
  final String sessionName;

  /// Per-peer clock offsets, estimated on the coordination stream and shared
  /// across every stream on this socket. Null when nothing is estimating them,
  /// in which case samples arrive with an unknown offset.
  final PeerClockOffsets? clockOffsets;

  Node _streamNode;

  @override
  Node get streamNode => _streamNode;

  @override
  void setStreamNode(Node node) => _streamNode = node;

  @override
  String? get description =>
      'WebSocket data stream "${config.name}" for ${_streamNode.id}';

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
  IMessage? decodeSample(Uint8List frame) {
    final channels = WsSampleFrame.decodeChannels(frame, config.channels);
    final timestamp = DateTime.now();
    // The frame carries the sender's clock at offset 6. Turning that into a
    // transit time needs the sender's identity, which is why the subscription
    // map keeps slot -> nodeUId: the offset is estimated per peer on the
    // coordination stream, and this is where a data sample claims its share.
    final peerUId = _slotOwners[WsSampleFrame.sourceSlotOf(frame)];
    final offsets = clockOffsets;
    final timing = MessageTiming(
      sourceClock: WsSampleFrame.senderMicrosOf(frame) / 1e6,
      // Null until the estimator has accepted a burst for this peer, which
      // keeps transitSeconds null rather than reporting the difference of two
      // unrelated monotonic clocks.
      clockOffset: offsets?.offsetFor(peerUId),
      uncertainty: offsets?.uncertaintyFor(peerUId),
      receivedClock: PeerClock.now(),
      sourceId: peerUId,
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
  Object encodeForWire(IMessage message) => jsonEncode(message.data.toList());

  @override
  IMessage? decodeControlPayload(Object payload) => null;
}

/// Builds WebSocket streams for a session.
class WsNetworkStreamFactory extends NetworkStreamFactory {
  WsNetworkStreamFactory(this.connection, {this.clockOffsets});

  final WsConnection connection;

  /// Shared per-peer clock offsets, so a data stream can turn a sample's
  /// producer slot into a real transit time.
  final PeerClockOffsets? clockOffsets;

  @override
  Future<WsDataStream> createDataStream(
    DataStreamConfig config,
    CoordinationSession session,
  ) async => WsDataStream(
    config: config,
    connection: connection,
    sessionName: session.config.name,
    streamNode: session.thisNode,
    clockOffsets: clockOffsets,
  );

  @override
  Future<WsCoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config,
    CoordinationSession session,
  ) async => WsCoordinationStream(
    config: config,
    connection: connection,
    sessionName: session.config.name,
    streamNode: session.thisNode,
  );
}
