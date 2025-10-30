import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';
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

/// Transport-specific extensions to stream configuration.
abstract class TransportStreamConfig implements IConfig {}

/// Transport-specific extensions to coordination stream configuration.
abstract class TransportCoordinationStreamConfig
    extends TransportStreamConfig {}

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

  /// Transport-specific configuration for the stream.
  TransportStreamConfig? get transportConfig => _transportConfig;

  abstract final TransportStreamConfig? _transportConfig;

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
    if (transportConfig != null &&
        !transportConfig!.validate(throwOnError: throwOnError)) {
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
      'transportConfig': transportConfig?.toMap(),
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
    TransportStreamConfig? transportConfig,
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

  /// Transport-specific configuration for the data stream.
  @override
  final TransportStreamConfig? _transportConfig;

  /// Defines who should participate in this data stream
  final StreamParticipationMode participationMode;

  /// Whether precise polling is enabled for this data stream.
  /// i.e. with the LSL transport, it will use busy-waiting to achieve lower
  /// latency at the cost of higher CPU usage.
  /// Defaults to true.
  final bool precisePolling;

  /// Transport-specific configuration for the data stream.
  @override
  TransportStreamConfig? get transportConfig => _transportConfig;

  /// Creates a data stream configuration.
  /// The number of channels, sample rate, and data type must be specified.
  /// Optionally, transport-specific configuration can be provided.
  DataStreamConfig({
    required super.name,
    required super.channels,
    required super.sampleRate,
    required super.dataType,
    this.participationMode = StreamParticipationMode.sendAllReceiveCoordinator,
    this.precisePolling = true,
    TransportStreamConfig? transportConfig,
  }) : _transportConfig = transportConfig;

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
        other.precisePolling == precisePolling &&
        other.transportConfig == transportConfig;
  }

  @override
  int get hashCode => Object.hash(
    name,
    channels,
    sampleRate,
    dataType,
    participationMode,
    precisePolling,
    transportConfig,
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
      transportConfig: null, // Needs proper handling
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
  @override
  final TransportCoordinationStreamConfig? _transportConfig;

  /// Transport-specific configuration for the coordination stream.
  @override
  TransportCoordinationStreamConfig? get transportConfig => _transportConfig;

  /// Creates a coordination stream configuration.
  /// Coordination streams default to 1 channel and string data type.
  /// The sample rate can be specified.
  /// Optionally, transport-specific configuration can be provided.
  CoordinationStreamConfig({
    required super.name,
    super.sampleRate = 50.0,
    TransportCoordinationStreamConfig? transportConfig,
  }) : _transportConfig = transportConfig,
       super(
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
        other.dataType == dataType &&
        other.transportConfig == transportConfig;
  }

  @override
  int get hashCode =>
      Object.hash(name, channels, sampleRate, dataType, transportConfig);
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

  @mustBeOverridden
  FutureOr<void> sendMessage(M message) {
    throw UnimplementedError('sendMessage must be implemented by subclasses');
  }

  @mustBeOverridden
  StreamSink<M> get outbox =>
      throw UnimplementedError('outbox must be implemented by subclasses');

  @mustBeOverridden
  Stream<M> get inbox =>
      throw UnimplementedError('inbox must be implemented by subclasses');
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
  @mustBeOverridden
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
  @mustBeOverridden
  FutureOr<void> sendMessage(M message) {
    // Default implementation does nothing.
    // Subclasses should override this method to provide actual functionality.
    throw UnimplementedError('sendMessage must be implemented by subclasses');
  }
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
