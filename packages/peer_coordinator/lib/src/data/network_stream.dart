import 'dart:async';

import 'package:peer_coordinator/framework.dart';
import 'package:meta/meta.dart';

enum StreamDataType { float32, double64, int8, int16, int32, int64, string }

/// Defines who should participate in a data stream
enum StreamParticipationMode {
  /// Only coordinator receives data from all nodes (hierarchical)
  coordinatorOnly,

  /// All nodes send data, all nodes receive data (fully connected)
  allNodes,

  /// All nodes send data, only coordinator receives (default)
  sendParticipantsReceiveCoordinator,

  /// All nodes (including coordinator) send data, only coordinator receives
  sendAllReceiveCoordinator,

  /// Custom participation based on node configuration
  custom,
}

// There used to be `TransportStreamConfig` / `TransportCoordinationStreamConfig`
// hooks here for per-stream transport options. Nothing ever implemented them,
// and the hook could not have worked: the coordinator broadcasts a stream's
// config to participants inside `CreateStreamMessage`, and
// `DataStreamConfigFactory.fromMap` dropped the field outright, so any option
// set there would silently fail to reach the other nodes.
//
// Put transport options on the `ITransportConfig` instead, where they are
// chosen locally by each node and never need to cross the wire. If per-stream
// options are genuinely needed later, they have to round-trip through
// `toMap`/`fromMap`, which means a discriminator so the deserialiser knows
// which transport's config to rebuild.

/// Base class for all network stream configurations.
abstract class NetworkStreamConfig implements IConfig {
  /// Human-readable name for the stream.
  @override
  final String name;

  /// Number of channels in the stream.
  final int channels;

  /// Sample rate of the stream.
  final double sampleRate;

  /// Data type of the stream.
  /// This is a [StreamDataType] enum value.
  final StreamDataType dataType;

  NetworkStreamConfig({
    required this.name,
    required this.channels,
    required this.sampleRate,
    required this.dataType,
  }) {
    validate(throwOnError: true);
  }

  /// Validates the configuration.
  @override
  bool validate({bool throwOnError = false}) {
    if (name.isEmpty) {
      if (throwOnError) {
        throw ArgumentError('Stream name cannot be empty');
      }
      return false;
    }
    if (channels <= 0) {
      if (throwOnError) {
        throw ArgumentError('Channel count must be greater than 0');
      }
      return false;
    }
    if (sampleRate <= 0) {
      if (throwOnError) {
        throw ArgumentError('Sample rate must be greater than 0');
      }
      return false;
    }
    if (!StreamDataType.values.contains(dataType)) {
      if (throwOnError) {
        throw ArgumentError('Invalid data type: $dataType');
      }
      return false;
    }
    return true;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'channelCount': channels,
      'sampleRate': sampleRate,
      'dataType': dataType.toString(),
    };
  }

  @override
  String toString() {
    return 'StreamConfig(name: $name, channelCount: $channels, sampleRate: $sampleRate, dataType: $dataType)';
  }

  /// Creates a copy of this configuration with the given fields replaced.
  @override
  NetworkStreamConfig copyWith({
    String? id,
    String? name,
    int? channelCount,
    double? sampleRate,
    StreamDataType? dataType,
  }) {
    throw UnimplementedError(
      'copyWith is not implemented for abstract NetworkStreamConfig. '
      'Please implement in subclasses.',
    );
  }
}

class DataStreamConfig extends NetworkStreamConfig {
  @override
  String get id => 'data_stream_config_${hashCode.toString()}';
  @override
  String? get description => 'Configuration for data stream $name (id: $id)';

  /// Defines who should participate in this data stream
  final StreamParticipationMode participationMode;

  /// Whether precise polling is enabled for this data stream.
  /// i.e. with the LSL transport, it will use busy-waiting to achieve lower
  /// latency at the cost of higher CPU usage.
  /// Defaults to true.
  final bool precisePolling;

  /// Creates a data stream configuration.
  /// The number of channels, sample rate, and data type must be specified.
  DataStreamConfig({
    required super.name,
    required super.channels,
    required super.sampleRate,
    required super.dataType,
    this.participationMode = StreamParticipationMode.sendAllReceiveCoordinator,
    this.precisePolling = true,
  });

  /// Checks that [data] is a valid sample for this stream.
  ///
  /// A sample is exactly [NetworkStreamConfig.channels] values whose runtime
  /// types match [NetworkStreamConfig.dataType]. Transport-neutral, so every
  /// backend rejects the same inputs with the same message instead of each
  /// discovering the mismatch in its own way (or not at all).
  ///
  /// Throws [ArgumentError] describing the first problem found.
  void validateSample(Iterable<dynamic> data) {
    if (data.length != channels) {
      throw ArgumentError(
        'Data length ${data.length} does not match channels $channels '
        'on stream "$name"',
      );
    }
    for (final value in data) {
      switch (dataType) {
        case StreamDataType.float32:
        case StreamDataType.double64:
          if (value is! num) {
            throw ArgumentError(
              'Expected numeric value, got ${value.runtimeType}',
            );
          }
        case StreamDataType.int8:
        case StreamDataType.int16:
        case StreamDataType.int32:
        case StreamDataType.int64:
          if (value is! int) {
            throw ArgumentError('Expected int value, got ${value.runtimeType}');
          }
        case StreamDataType.string:
          if (value is! String) {
            throw ArgumentError(
              'Expected String value, got ${value.runtimeType}',
            );
          }
      }
    }
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map['participationMode'] = participationMode.toString();
    map['precisePolling'] = precisePolling;

    return map;
  }

  @override
  String toString() {
    return 'DataStreamConfig(${super.toString()})';
  }

  @override
  operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DataStreamConfig &&
        other.runtimeType == runtimeType &&
        other.name == name &&
        other.channels == channels &&
        other.sampleRate == sampleRate &&
        other.dataType == dataType &&
        other.participationMode == participationMode &&
        other.precisePolling == precisePolling;
  }

  @override
  int get hashCode => Object.hash(
    name,
    channels,
    sampleRate,
    dataType,
    participationMode,
    precisePolling,
  );
}

class DataStreamConfigFactory implements IConfigFactory<DataStreamConfig> {
  /// Returns a standard/default data stream configuration.
  /// This can be used as a starting point for custom configurations.
  /// The default configuration has:
  /// - name: "Default Data Stream"
  /// - channelCount: 8
  /// - sampleRate: 256.0 Hz
  /// - dataType: StreamDataType.float32
  @override
  DataStreamConfig defaultConfig() => DataStreamConfig(
    name: 'Default Data Stream',
    channels: 8,
    sampleRate: 256.0,
    dataType: StreamDataType.float32,
  );

  /// Creates a data stream configuration from a map.
  @override
  DataStreamConfig fromMap(Map<String, dynamic> map) {
    return DataStreamConfig(
      name: map['name'] ?? 'Default Data Stream',
      channels: map['channelCount'] ?? 8,
      sampleRate: (map['sampleRate'] as num?)?.toDouble() ?? 256.0,
      dataType: StreamDataType.values.firstWhere(
        (e) => e.toString() == map['dataType'],
        orElse: () => StreamDataType.float32,
      ),
      participationMode: StreamParticipationMode.values.firstWhere(
        (e) => e.toString() == map['participationMode'],
        orElse: () =>
            StreamParticipationMode.sendParticipantsReceiveCoordinator,
      ),
      precisePolling: map['precisePolling'] ?? true,
    );
  }
}

/// Configuration for a coordination stream used for network coordination tasks.
class CoordinationStreamConfig extends NetworkStreamConfig {
  @override
  String get id => 'coordination_stream_config_${hashCode.toString()}';
  @override
  String? get description =>
      'Configuration for coordination stream $name (id: $id)';

  /// Transport-specific configuration for the coordination stream.
  /// Transport-specific configuration for the coordination stream.
  /// Creates a coordination stream configuration.
  /// Coordination streams default to 1 channel and string data type.
  /// The sample rate can be specified.
  /// Optionally, transport-specific configuration can be provided.
  CoordinationStreamConfig({required super.name, super.sampleRate = 50.0})
    : super(
        channels: 1, // Default to 1 channel for coordination streams
        dataType: StreamDataType.string, // Default data type
      );

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    return map;
  }

  @override
  String toString() {
    return 'CoordinationStreamConfig(${super.toString()})';
  }

  @override
  operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoordinationStreamConfig &&
        other.runtimeType == runtimeType &&
        other.name == name &&
        other.channels == channels &&
        other.sampleRate == sampleRate &&
        other.dataType == dataType;
  }

  @override
  int get hashCode => Object.hash(name, channels, sampleRate, dataType);
}

/// Factory for creating coordination stream configurations.
class CoordinationStreamConfigFactory
    implements IConfigFactory<CoordinationStreamConfig> {
  /// Returns a standard/default coordination stream configuration.
  /// This can be used as a starting point for custom configurations.
  /// The default configuration has:
  /// - name: "Default Coordination Stream"
  /// - sampleRate: 50.0 Hz
  /// - channelCount: 1
  /// - dataType: StreamDataType.string
  @override
  CoordinationStreamConfig defaultConfig() => CoordinationStreamConfig(
    name: 'Default Coordination Stream',
    sampleRate: 50.0,
  );

  /// Creates a coordination stream configuration from a map.
  @override
  CoordinationStreamConfig fromMap(Map<String, dynamic> map) {
    return CoordinationStreamConfig(
      name: map['name'] ?? 'Default Coordination Stream',
      sampleRate: (map['sampleRate'] as num?)?.toDouble() ?? 50.0,
    );
  }
}

/// Configuration for a coordination session used to manage network nodes.
abstract class NetworkStream<T extends NetworkStreamConfig, M extends IMessage>
    implements IConfigurable<T>, IUniqueIdentity, IResource, IPausable {
  /// Identifier for the stream, derived from the config hash code.
  @override
  String get id => config.hashCode.toString();

  /// Human-readable name for the stream.
  @override
  String get name => config.name;

  /// Configuration for the stream.
  /// This is a [NetworkStreamConfig] object.
  @override
  final T config;

  bool _paused = false;

  @override
  bool get paused => _paused;

  /// Number of channels in the stream.
  int get channelCount => config.channels;

  /// Sample rate of the stream.
  double get sampleRate => config.sampleRate;

  /// Data type of the stream.
  /// This is a [StreamDataType] enum value.
  StreamDataType get dataType => config.dataType;

  /// Map of node IDs to Node objects that are part of this stream.
  final Map<String, Node> _nodes = {};

  /// List of producer node IDs.
  final List<String> _producers = [];

  /// List of consumer node IDs.
  final List<String> _consumers = [];

  /// Whether the stream has any current producers.
  bool get hasProducers => _producers.isNotEmpty;

  /// Whether the stream has any current consumers.
  bool get hasConsumers => _consumers.isNotEmpty;

  Type get messageClass => M;

  /// List of producer node IDs.
  List<String> get producers => List.unmodifiable(_producers);

  /// List of consumer node IDs.
  List<String> get consumers => List.unmodifiable(_consumers);

  /// Creates a network stream with the given [NetworkStreamConfig].
  /// Optionally, initial lists of producer and consumer nodes can be provided.
  /// If a node is both a producer and consumer, it will be in both lists.
  NetworkStream(this.config, {List<Node>? producers, List<Node>? consumers}) {
    if (!config.validate()) {
      throw ArgumentError('Invalid stream configuration: ${config.toMap()}');
    }
    for (Node producer in producers ?? []) {
      _nodes[producer.uId] = producer;
      _producers.add(producer.uId);
    }
    for (Node consumer in consumers ?? []) {
      if (!_nodes.containsKey(consumer.uId)) {
        _nodes[consumer.uId] = consumer;
      }
      _consumers.add(consumer.uId);
    }
  }

  /// Checks if a given node is a producer for this stream.
  bool isProducer(Node node) => _producers.contains(node.uId);

  /// Checks if a given node is a consumer for this stream.
  bool isConsumer(Node node) => _consumers.contains(node.uId);

  /// Adds a producer node to this stream.
  void addProducer(Node producer) {
    if (!_nodes.containsKey(producer.uId)) {
      throw ArgumentError(
        'Producer node with ID ${producer.uId} is not part of this stream.',
      );
    }
    if (!isProducer(producer)) {
      _producers.add(producer.uId);
    }
  }

  @override
  @mustCallSuper
  FutureOr<void> pause() {
    _paused = true;
  }

  @override
  @mustCallSuper
  FutureOr<void> resume() {
    _paused = false;
  }

  /// Adds a consumer node to this stream.
  void addConsumer(Node consumer) {
    if (!_nodes.containsKey(consumer.uId)) {
      throw ArgumentError(
        'Consumer node with ID ${consumer.uId} is not part of this stream.',
      );
    }
    if (!isConsumer(consumer)) {
      _consumers.add(consumer.uId);
    }
  }

  // Not @mustBeOverridden: these are routinely supplied by a mixin
  // (LSLStreamMixin, InMemoryStreamMixin) rather than by the concrete class,
  // and the analyzer cannot see that, so the annotation only produced
  // `// ignore` comments on every transport.
  FutureOr<void> sendMessage(M message) {
    throw UnimplementedError('sendMessage must be implemented by subclasses');
  }

  StreamSink<M> get outbox =>
      throw UnimplementedError('outbox must be implemented by subclasses');

  /// Incoming messages from peers.
  ///
  /// Contract, uniform across transports: this is a **broadcast** stream. It
  /// may be listened to, cancelled, and listened to again — which consumers
  /// legitimately need across a stream stop/start cycle, since the stream
  /// object itself is cached per name and survives the cycle. Being broadcast,
  /// it buffers nothing: messages arriving with no listener are dropped.
  ///
  /// A stream is nevertheless expected to have exactly **one** consumer. Two
  /// concurrent listeners almost always means a subscription was not cancelled
  /// during teardown, and transports may log a warning when they see it.
  Stream<M> get inbox =>
      throw UnimplementedError('inbox must be implemented by subclasses');

  /// Clock-offset estimates for this stream's peers, as they are made.
  ///
  /// A **broadcast** stream, with the same listen/cancel/listen contract as
  /// [inbox]. Empty by default: a transport that does not estimate clock
  /// offsets has nothing to report, and a consumer should not have to know
  /// which transport it is on to write the subscription.
  ///
  /// This exists because [MessageTiming] can only describe estimates that
  /// happened to be attached to a message that happened to arrive. Drift over
  /// a session is a property of the clocks, not of the traffic, so it needs a
  /// channel that ticks on the estimate's own cadence.
  Stream<ClockSyncSample> get clockSyncs => const Stream.empty();

  /// Whether this transport already puts the sender's clock on the wire.
  ///
  /// LSL does: every sample carries the sending machine's `lsl_local_clock()`
  /// reading, which is what [MessageTiming.sourceClock] reports. Transports that
  /// return false get a [PeerClock] reading stamped into the message envelope by
  /// the layer above, so a receiver has *something* to compare against — but a
  /// transport that has its own, better sender clock must say so, or the two
  /// stamps disagree and the weaker one wins.
  bool get carriesSenderClock => false;

  /// Whether both ends of this stream read the same [PeerClock].
  ///
  /// True only for the in-memory transport, where "both peers" are objects in
  /// one process. It means a sender's clock reading needs no correction to be
  /// comparable with a local one — [MessageTiming.clockOffset] is a known zero
  /// rather than an unknown null, so transit times are exact.
  ///
  /// Any transport that crosses a process boundary must leave this false: two
  /// processes' monotonic clocks have unrelated epochs, and pretending
  /// otherwise yields a confident, meaningless number.
  bool get sharesSenderClockDomain => false;

  // ---------------------------------------------------------------------------
  // Transport contract
  //
  // Everything below used to exist only on LSLStreamMixin, which meant every
  // caller — the controller, the session, the stream-lifecycle handlers — had
  // to hold a concrete LSL type to do anything useful. Declaring it here is
  // what lets a second transport exist at all.
  //
  // The vocabulary is deliberately publish/subscribe rather than LSL's
  // outlet/inlet: `createOutlet` means "start publishing this node's data" and
  // `addInlet` means "subscribe to this peer".
  // ---------------------------------------------------------------------------

  /// Whether the stream is currently running.
  bool get started;

  /// Begins publishing and delivering. Idempotent.
  Future<void> start();

  /// Stops publishing and delivering, but keeps the stream usable.
  Future<void> stop();

  /// Creates this node's publishing endpoint.
  Future<void> createOutlet();

  /// Recreates the publishing endpoint to reflect a changed [Node].
  ///
  /// Required because a node's role is part of its published identity, and
  /// election changes that role after the endpoint already exists.
  Future<void> recreateOutlet();

  /// Subscribes to a peer found by discovery.
  ///
  /// Implementations must take ownership of [handle] (see [PeerHandle.take])
  /// before using it.
  Future<void> addInlet(PeerHandle handle);

  /// Unsubscribes from a peer, releasing whatever that inlet holds.
  ///
  /// Keyed on [nodeUId] rather than an endpoint id because an endpoint id is
  /// not stable across election on every transport: LSL's is its `source_id`,
  /// which encodes the node's role. [nodeUId] is the one identifier that
  /// survives a role change on all of them, and it is what the departure paths
  /// have in hand.
  ///
  /// Idempotent — removing an inlet that is not there is not an error.
  ///
  /// The default is a no-op, because on a relay transport a stale inlet is
  /// inert: it costs a routing entry that the hub drops anyway when the peer's
  /// socket closes. Transports holding a real per-peer resource — an LSL inlet,
  /// an `RTCPeerConnection` — must override, or a departed peer leaks until
  /// [dispose].
  Future<void> removeInlet(String nodeUId) async {}

  /// Subscribes to every node in [nodes], resolving their endpoints first.
  Future<void> createInletsForNodes(
    Iterable<Node> nodes, {
    Duration resolveTimeout = const Duration(seconds: 10),
  });

  /// Replaces the [Node] this stream publishes as.
  ///
  /// Call [recreateOutlet] afterwards for the change to reach the network.
  void updateNode(Node newNode);

  /// Resumes, optionally discarding data buffered while paused.
  ///
  /// [resume] exists on [IPausable] with no parameters, and an override cannot
  /// usefully widen it — callers holding the base type could never pass the
  /// flag. So the parameterised form is its own method and [resume] delegates
  /// here.
  @mustCallSuper
  Future<void> resumeWith({bool flushBeforeResume = true}) async {
    _paused = false;
  }

  /// Discards anything buffered.
  ///
  /// Default is a no-op: only transports with their own buffering (LSL's
  /// inlets) have anything to discard.
  Future<void> flushStreams() async {}

  /// Pauses, if running and not already paused.
  Future<void> pauseStream() async {
    if (!started || paused) return;
    await pause();
  }

  /// Resumes, if running and paused.
  Future<void> resumeStream({bool flushBeforeResume = true}) async {
    if (!started || !paused) return;
    await resumeWith(flushBeforeResume: flushBeforeResume);
  }

  /// Stops and releases the stream's endpoints.
  Future<void> destroyStream() async {
    await stop();
  }
}

/// A coordination stream used for network coordination tasks.
abstract class CoordinationStream<
  T extends CoordinationStreamConfig,
  M extends StringMessage
>
    extends NetworkStream<T, M> {
  /// Creates a coordination stream with the given [CoordinationStreamConfig].
  CoordinationStream(super.config);

  @override
  FutureOr<void> sendMessage(M message) {
    // Default implementation does nothing.
    // Subclasses should override this method to provide actual functionality.
    return Future.value();
  }
}

/// A data stream used for transmitting actual data samples.
abstract class DataStream<T extends DataStreamConfig, M extends IMessage>
    extends NetworkStream<T, M> {
  /// Creates a data stream with the given [DataStreamConfig].
  DataStream(super.config, {super.producers, super.consumers});

  @override
  FutureOr<void> sendMessage(M message) {
    // Default implementation does nothing.
    // Subclasses should override this method to provide actual functionality.
    throw UnimplementedError('sendMessage must be implemented by subclasses');
  }

  /// Publishes one sample: exactly [NetworkStream.channelCount] values whose
  /// runtime types match [NetworkStream.dataType].
  ///
  /// Validate with [DataStreamConfig.validateSample] before transmitting.
  Future<void> sendData(Iterable<dynamic> data);

  /// [sendData] for a statically known element type.
  Future<void> sendDataTyped<S>(Iterable<S> data);
}

/// Creates network streams.
abstract class NetworkStreamFactory<TSession extends CoordinationSession> {
  /// Creates a data stream with the given configuration and session context.
  FutureOr<DataStream> createDataStream(
    DataStreamConfig config,
    TSession session,
  );

  /// Creates a coordination stream with the given configuration and session context.
  FutureOr<CoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config,
    TSession session,
  );
}
