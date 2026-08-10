import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/in_memory.dart';

/// Shared implementation for in-memory coordination and data streams.
///
/// Publishing is `bus.publish`; subscribing is a routing-table entry. There is
/// no isolate and no polling: the LSL transport needs both because liblsl is a
/// blocking FFI library, but an in-process bus is already event-driven.
mixin InMemoryStreamMixin<T extends NetworkStreamConfig, M extends IMessage>
    on NetworkStream<T, M> {
  InMemoryBus get bus;
  String get sessionName;
  Node get streamNode;

  final StreamController<M> _incoming = StreamController<M>.broadcast();
  final StreamController<M> _outgoing = StreamController<M>();
  StreamSubscription<BusEnvelope>? _busSubscription;
  StreamSubscription<M>? _outgoingSubscription;

  bool _created = false;
  bool _disposed = false;
  bool _started = false;
  bool _publishing = false;
  IResourceManager? _manager;

  /// The subscriptions this stream has taken out, so they can be torn down.
  final Set<String> _subscribedProducers = {};

  /// This stream's identity on the bus.
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

    _busSubscription = bus.connect(endpointId).listen(_onEnvelope);
    _outgoingSubscription = _outgoing.stream.listen((message) {
      unawaited(Future.sync(() => sendMessage(message)));
    });
  }

  void _onEnvelope(BusEnvelope envelope) {
    if (_disposed || paused || !_started) return;
    final payload = envelope.payload;
    if (payload is M) _incoming.add(payload);
  }

  @override
  Future<void> createOutlet() async {
    if (_disposed) return;
    _publishing = true;
    bus.registry.attach(descriptor);
  }

  @override
  Future<void> recreateOutlet() async {
    if (_disposed) return;
    // The relay analogue of tearing down and rebuilding an LSL outlet: the
    // node's role is part of its published descriptor, and election changes it.
    if (!_publishing) return createOutlet();
    bus.registry.attach(descriptor);
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

    bus.routing.subscribe(
      streamName: config.name,
      producerEndpointId: producer,
      subscriberEndpointId: endpointId,
    );
    await handle.dispose();
  }

  @override
  Future<void> createInletsForNodes(
    Iterable<Node> nodes, {
    Duration resolveTimeout = const Duration(seconds: 10),
  }) async {
    if (nodes.isEmpty) return;
    final deadline = DateTime.now().add(resolveTimeout);
    final wanted = nodes.map((n) => n.uId).toSet();

    while (true) {
      final found = bus.registry
          .match(
            PeerQueries.streamPublishers(
              streamName: config.name,
              sessionName: sessionName,
            ),
          )
          .where((p) => wanted.contains(p.nodeUId))
          .toList(growable: false);

      if (found.length >= wanted.length) {
        for (final descriptor in found) {
          await addInlet(InMemoryPeerHandle(descriptor));
        }
        return;
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw StateError(
          'Timed out resolving ${wanted.length} publisher(s) of '
          '"${config.name}"; found ${found.length}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  void updateNode(Node newNode) {
    if (newNode.uId != streamNode.uId) {
      throw ArgumentError('newNode must have the same uId');
    }
    setStreamNode(newNode);
  }

  /// Implemented by the concrete stream, which owns the mutable field.
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
    for (final producer in _subscribedProducers) {
      bus.routing.unsubscribe(
        streamName: config.name,
        producerEndpointId: producer,
        subscriberEndpointId: endpointId,
      );
    }
    _subscribedProducers.clear();
    if (_publishing) {
      bus.registry.detach(endpointId);
      _publishing = false;
    }
  }

  @override
  FutureOr<void> sendMessage(M message) {
    if (_disposed || !_started || paused) return null;
    bus.publish(
      streamName: config.name,
      fromEndpointId: endpointId,
      payload: message,
    );
    return null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await destroyStream();
    _disposed = true;
    _created = false;
    await _busSubscription?.cancel();
    await _outgoingSubscription?.cancel();
    bus.disconnect(endpointId);
    unawaited(_incoming.close());
    unawaited(_outgoing.close());
  }
}

/// Coordination stream over an [InMemoryBus].
class InMemoryCoordinationStream
    extends CoordinationStream<CoordinationStreamConfig, StringMessage>
    with
        InstanceUID,
        InMemoryStreamMixin<CoordinationStreamConfig, StringMessage> {
  InMemoryCoordinationStream({
    required CoordinationStreamConfig config,
    required this.bus,
    required this.sessionName,
    required Node streamNode,
  }) : _streamNode = streamNode,
       super(config);

  @override
  final InMemoryBus bus;

  @override
  final String sessionName;

  Node _streamNode;

  @override
  String? get description =>
      'In-memory coordination stream "${config.name}" for node ${_streamNode.id}';

  @override
  Node get streamNode => _streamNode;

  @override
  void setStreamNode(Node node) => _streamNode = node;
}

/// Data stream over an [InMemoryBus].
class InMemoryDataStream extends DataStream<DataStreamConfig, IMessage>
    with InstanceUID, InMemoryStreamMixin<DataStreamConfig, IMessage> {
  InMemoryDataStream({
    required DataStreamConfig config,
    required this.bus,
    required this.sessionName,
    required Node streamNode,
  }) : _streamNode = streamNode,
       super(config);

  @override
  final InMemoryBus bus;

  @override
  final String sessionName;

  Node _streamNode;

  @override
  String? get description =>
      'In-memory data stream "${config.name}" for node ${_streamNode.id}';

  @override
  Node get streamNode => _streamNode;

  @override
  void setStreamNode(Node node) => _streamNode = node;

  @override
  Future<void> sendData(Iterable<dynamic> data) async {
    if (!started) throw StateError('Stream not started');
    config.validateSample(data);
    await sendMessage(_toMessage(IList<dynamic>(data)));
  }

  @override
  Future<void> sendDataTyped<S>(Iterable<S> data) async {
    if (!started) throw StateError('Stream not started');
    config.validateSample(data);
    await sendMessage(_toMessage(IList<dynamic>(data)));
  }

  IMessage _toMessage(IList<dynamic> data) {
    final timestamp = DateTime.now();
    switch (config.dataType) {
      case StreamDataType.float32:
      case StreamDataType.double64:
        return MessageFactory.double64Message(
          data: IList(data.map((v) => (v as num).toDouble())),
          channels: config.channels,
          timestamp: timestamp,
        );
      case StreamDataType.int8:
      case StreamDataType.int16:
      case StreamDataType.int32:
      case StreamDataType.int64:
        return MessageFactory.int64Message(
          data: IList(data.cast<int>()),
          channels: config.channels,
          timestamp: timestamp,
        );
      case StreamDataType.string:
        return MessageFactory.stringMessage(
          data: IList(data.cast<String>()),
          channels: config.channels,
          timestamp: timestamp,
        );
    }
  }
}

/// Builds in-memory streams for a session.
class InMemoryNetworkStreamFactory extends NetworkStreamFactory {
  InMemoryNetworkStreamFactory(this.bus);

  final InMemoryBus bus;

  @override
  Future<InMemoryDataStream> createDataStream(
    DataStreamConfig config,
    CoordinationSession session,
  ) async => InMemoryDataStream(
    config: config,
    bus: bus,
    sessionName: session.config.name,
    streamNode: session.thisNode,
  );

  @override
  Future<InMemoryCoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config,
    CoordinationSession session,
  ) async => InMemoryCoordinationStream(
    config: config,
    bus: bus,
    sessionName: session.config.name,
    streamNode: session.thisNode,
  );
}
