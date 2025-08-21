import 'package:liblsl_coordinator/interfaces.dart';
import 'package:liblsl_coordinator/network.dart';

enum StreamDataType { float32, double64, int8, int16, int32, int64, string }

class StreamConfig implements IConfig {
  /// @TODO: implement filtering by node type/role/capabilities/name

  /// Human-readable name for the stream.
  final String name;

  /// Number of channels in the stream.
  final int channelCount;

  /// Sample rate of the stream.
  final double sampleRate;

  /// Data type of the stream.
  /// This is a [StreamDataType] enum value.
  final StreamDataType dataType;

  StreamConfig({
    required this.name,
    required this.channelCount,
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
    if (channelCount <= 0) {
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
      'channelCount': channelCount,
      'sampleRate': sampleRate,
      'dataType': dataType.toString(),
    };
  }

  @override
  String toString() {
    return 'StreamConfig(name: $name, channelCount: $channelCount, sampleRate: $sampleRate, dataType: $dataType)';
  }

  @override
  StreamConfig copyWith({
    String? id,
    String? name,
    int? channelCount,
    double? sampleRate,
    StreamDataType? dataType,
  }) {
    return StreamConfig(
      name: name ?? this.name,
      channelCount: channelCount ?? this.channelCount,
      sampleRate: sampleRate ?? this.sampleRate,
      dataType: dataType ?? this.dataType,
    );
  }
}

class CoordinationStreamConfig extends StreamConfig {
  CoordinationStreamConfig({required super.name, super.sampleRate = 50.0})
    : super(
        channelCount: 1, // Default to 1 channel for coordination streams
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
}

abstract class Stream<T extends StreamConfig>
    implements IConfigurable<T>, IUniqueIdentity, IResource {
  /// Unique identifier for the stream.
  @override
  String get id => config.hashCode.toString();

  /// Human-readable name for the stream.
  @override
  String get name => config.name;

  /// Configuration for the stream.
  /// This is a [StreamConfig] object.
  @override
  final T config;

  /// Number of channels in the stream.
  int get channelCount => config.channelCount;

  /// Sample rate of the stream.
  double get sampleRate => config.sampleRate;

  /// Data type of the stream.
  /// This is a [StreamDataType] enum value.
  StreamDataType get dataType => config.dataType;

  final Map<String, Node> _nodes = {};
  final List<String> _producers = [];
  final List<String> _consumers = [];

  bool get hasProducers => _producers.isNotEmpty;
  bool get hasConsumers => _consumers.isNotEmpty;

  /// List of producer node IDs.
  List<String> get producers => List.unmodifiable(_producers);

  /// List of consumer node IDs.
  List<String> get consumers => List.unmodifiable(_consumers);

  bool isProducer(Node node) => _producers.contains(node.uId);
  bool isConsumer(Node node) => _consumers.contains(node.uId);

  Stream(this.config, {List<Node>? producers, List<Node>? consumers}) {
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

  /// Adds a producer node to the stream.
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

  /// Adds a consumer node to the stream.
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
}

abstract class CoordinationStream<T extends CoordinationStreamConfig>
    extends Stream<T> {
  /// Configuration for the coordination stream.

  CoordinationStream(CoordinationStreamConfig super.config);
}

abstract class DataStream<T extends StreamConfig> extends Stream<T> {
  /// Creates a data stream with the given configuration.
  DataStream(super.config, {super.producers, super.consumers});
}
