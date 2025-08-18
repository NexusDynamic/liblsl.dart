/// Abstract interface for channel data formats across different transports
abstract class ChannelFormat {
  /// Human-readable name of the format
  String get name;
  
  /// Number of bytes per sample for this format
  int get bytesPerSample;
  
  /// Whether this format supports the given data type
  bool supportsType<T>();
}

/// Abstract configuration for data streams, transport-agnostic
abstract class StreamConfig {
  /// Unique identifier for this stream
  String get id;
  
  /// Maximum sample rate in Hz (actual rate may be lower based on data availability)
  double get maxSampleRate;
  
  /// Preferred polling frequency for consumers in Hz (can be different from sample rate)
  double get pollingFrequency;
  
  /// Number of channels in the stream
  int get channelCount;
  
  /// Data format for channels
  ChannelFormat get channelFormat;
  
  /// Protocol defining producer/consumer behavior
  StreamProtocol get protocol;
  
  /// Optional metadata for stream discovery and filtering
  Map<String, dynamic> get metadata;
}

/// Protocol defining how nodes interact with data streams
abstract class StreamProtocol {
  /// Whether this node produces data for this stream
  bool get isProducer;
  
  /// Whether this node consumes data from this stream
  bool get isConsumer;
  
  /// Whether this node relays/forwards data (implies both producer and consumer)
  bool get isRelay;
  
  /// Optional data transformation during relay
  T? transformData<T>(T input) => input;
}

/// Common stream protocols
class ProducerOnlyProtocol implements StreamProtocol {
  const ProducerOnlyProtocol();
  
  @override
  bool get isProducer => true;
  
  @override
  bool get isConsumer => false;
  
  @override
  bool get isRelay => false;
  
  @override
  T? transformData<T>(T input) => input;
}

class ConsumerOnlyProtocol implements StreamProtocol {
  const ConsumerOnlyProtocol();
  
  @override
  bool get isProducer => false;
  
  @override
  bool get isConsumer => true;
  
  @override
  bool get isRelay => false;
  
  @override
  T? transformData<T>(T input) => input;
}

class ProducerConsumerProtocol implements StreamProtocol {
  const ProducerConsumerProtocol();
  
  @override
  bool get isProducer => true;
  
  @override
  bool get isConsumer => true;
  
  @override
  bool get isRelay => false;
  
  @override
  T? transformData<T>(T input) => input;
}

class RelayProtocol implements StreamProtocol {
  final T? Function<T>(T)? _transformer;
  
  const RelayProtocol([this._transformer]);
  
  @override
  bool get isProducer => true;
  
  @override
  bool get isConsumer => true;
  
  @override
  bool get isRelay => true;
  
  @override
  T? transformData<T>(T input) => _transformer?.call(input) ?? input;
}