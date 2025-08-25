import 'package:liblsl_coordinator/data.dart';
import 'package:liblsl_coordinator/interfaces.dart';

/// Base mapping class for message types.
abstract class MessageTypeMapping<T> implements IMessageType<T> {
  @override
  StreamDataType get type;
  @override
  int get channels;
  @override
  String get description;

  const MessageTypeMapping();

  /// Returns a map representation of the message type mapping for
  /// serialization.
  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.toString(),
      'channels': channels,
    };
  }

  @override
  String toString() {
    return '$runtimeType(id: $id, name: $name, description: $description, type: $type, channels: $channels)';
  }
}

abstract class IntMessageTypeMapping extends MessageTypeMapping<int> {
  int get minValue;
  int get maxValue;

  const IntMessageTypeMapping();
}

/// implementation of a [IMessageType] for string data.
class StringMapping extends MessageTypeMapping<String> {
  @override
  final StreamDataType type = StreamDataType.string;
  @override
  final int channels;

  @override
  String get id => 'string-message';
  @override
  String get name => 'StringMessage';
  @override
  String get description => 'A message containing string data';

  const StringMapping({this.channels = 1});
}

/// implementation of a [IMessageType] for int8 data.
class Int8Mapping extends IntMessageTypeMapping {
  @override
  final StreamDataType type = StreamDataType.int8;
  @override
  final int channels;
  @override
  String get id => 'int8-message';
  @override
  String get name => 'Int8Message';
  @override
  String get description => 'A message containing int8 data (-128 to 127)';

  const Int8Mapping({this.channels = 1});

  @override
  final int minValue = -0x80;
  @override
  final int maxValue = 0x7F;
}

/// Implementation of a [IMessageType] for int16 data.
class Int16Mapping extends IntMessageTypeMapping {
  @override
  final StreamDataType type = StreamDataType.int16;
  @override
  final int channels;
  @override
  String get id => 'int16-message';
  @override
  String get name => 'Int16Message';
  @override
  String get description => 'A message containing int16 data';
  const Int16Mapping({this.channels = 1});

  @override
  final int minValue = -0x8000;
  @override
  final int maxValue = 0x7FFF;
}

/// Implementation of a [IMessageType] for int32 data.
class Int32Mapping extends IntMessageTypeMapping {
  @override
  final StreamDataType type = StreamDataType.int32;
  @override
  final int channels;
  @override
  String get id => 'int32-message';
  @override
  String get name => 'Int32Message';
  @override
  String get description => 'A message containing int32 data';
  const Int32Mapping({this.channels = 1});

  @override
  final int minValue = -0x80000000;
  @override
  final int maxValue = 0x7FFFFFFF;
}

/// Implementation of a [IMessageType] for int64 data.
class Int64Mapping extends IntMessageTypeMapping {
  @override
  final StreamDataType type = StreamDataType.int64;
  @override
  final int channels;
  @override
  String get id => 'int64-message';
  @override
  String get name => 'Int64Message';
  @override
  String get description => 'A message containing int64 data';
  const Int64Mapping({this.channels = 1});

  @override
  final int minValue = -0x8000000000000000;
  @override
  final int maxValue = 0x7FFFFFFFFFFFFFFF;
}

/// Implementation of a [IMessageType] for float32 data.
class Float32Mapping extends MessageTypeMapping<double> {
  @override
  final StreamDataType type = StreamDataType.float32;
  @override
  final int channels;
  @override
  String get id => 'float32-message';
  @override
  String get name => 'Float32Message';
  @override
  String get description => 'A message containing float32 data';
  const Float32Mapping({this.channels = 1});
}

/// Implementation of a [IMessageType] for double64 data.
class Double64Mapping extends MessageTypeMapping<double> {
  @override
  final StreamDataType type = StreamDataType.double64;
  @override
  final int channels;
  @override
  String get id => 'double64-message';
  @override
  String get name => 'Double64Message';
  @override
  String get description => 'A message containing double64 data';
  const Double64Mapping({this.channels = 1});
}

/// Generic reusable message type wrapper for a specific data type [Type] and
/// [MessageTypeMapping].
class MessageType<T, M extends MessageTypeMapping<T>>
    implements IMessageType<T> {
  final M _mapping;

  @override
  StreamDataType get type => _mapping.type;
  @override
  int get channels => _mapping.channels;
  @override
  String get id => _mapping.id;
  @override
  String get name => _mapping.name;
  @override
  String get description => _mapping.description;

  const MessageType(this._mapping);

  @override
  Map<String, dynamic> toMap() {
    return _mapping.toMap();
  }
}

/// Implementation of a message with specific data and type.
class Message<D, M extends MessageTypeMapping<D>, T extends MessageType<D, M>>
    implements IMessage<T> {
  @override
  final T messageType;
  @override
  final List<D> data;
  @override
  final String uId;
  @override
  final DateTime timestamp;
  @override
  Map<String, dynamic> get metadata => _metadata;

  final Map<String, String> _metadata = {};

  /// The internal mapping used for validation and metadata.
  final M _mapping;

  @override
  String get id => _mapping.id;
  @override
  String get name => _mapping.name;
  @override
  String get description => _mapping.description;

  /// Creates a new [Message] with the given parameters.
  /// The [messageType] parameter specifies the [MessageType] of the message.
  /// The [data] parameter must be a list of data with length equal to the
  /// number of channels specified in the [messageType].
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  Message({
    String? uId,
    required this.messageType,
    required this.data,
    required M mapping,
    DateTime? timestamp,
  }) : _mapping = mapping,
       uId = uId ??= generateUid(),
       timestamp = timestamp ?? DateTime.now() {
    if (data.length != mapping.channels) {
      validate();
    }
  }

  /// Validates the message data against the [MessageTypeMapping].
  /// Throws an [ArgumentError] if the data is invalid.
  void validate() {
    if (data.length != _mapping.channels) {
      throw ArgumentError.value(
        data,
        'data',
        'Data length (${data.length}) does not match the number of channels (${_mapping.channels})',
      );
    }
  }

  @override
  dynamic getMetadata(String key, {dynamic defaultValue}) =>
      _metadata[key] ?? defaultValue;

  void setMetadata(String key, String value) {
    _metadata[key] = value;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'uId': uId,
      'messageType': {
        'type': messageType.type.toString(),
        'channels': messageType.channels,
      },
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

// Convienince type aliases for common message types
/// String [Message] type alias, with [StringMapping] and String [MessageType].
typedef StringMessage =
    Message<String, StringMapping, MessageType<String, StringMapping>>;

/// Int8 [Message] type alias with [Int8Mapping] and Int [MessageType].
typedef Int8Message = Message<int, Int8Mapping, MessageType<int, Int8Mapping>>;

/// Int16 [Message] type alias with [Int16Mapping] and Int [MessageType].
typedef Int16Message =
    Message<int, Int16Mapping, MessageType<int, Int16Mapping>>;

/// Int32 [Message] type alias with [Int32Mapping] and Int [MessageType].
typedef Int32Message =
    Message<int, Int32Mapping, MessageType<int, Int32Mapping>>;

/// Int64 [Message] type alias with [Int64Mapping] and Int [MessageType].
typedef Int64Message =
    Message<int, Int64Mapping, MessageType<int, Int64Mapping>>;

/// Float32 [Message] type alias with [Float32Mapping] and Double [MessageType].
typedef Float32Message =
    Message<double, Float32Mapping, MessageType<double, Float32Mapping>>;

/// Double64 [Message] type alias with [Double64Mapping] and Double [MessageType].
typedef Double64Message =
    Message<double, Double64Mapping, MessageType<double, Double64Mapping>>;

// @TODO: Implement validators if it ends up being useful.
// extension IntValidator<M extends MessageTypeMapping<int>>
//     on Message<int, M, MessageType<int, M>> {}

/// Factory for creating messages of various types.
class MessageFactory {
  /// Creates a new [StringMessage] with the given parameters.
  /// The [channels] parameter specifies the number of channels in the message.
  /// The [data] parameter must be a list of strings with length equal to
  /// [channels].
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  static StringMessage stringMessage({
    String? uId,
    required List<String> data,
    int channels = 1,
    DateTime? timestamp,
  }) {
    final mapping = StringMapping(channels: channels);
    final messageType = MessageType<String, StringMapping>(mapping);
    return StringMessage(
      uId: uId,
      data: data,
      messageType: messageType,
      mapping: mapping,
      timestamp: timestamp,
    );
  }

  /// Creates a new [Int8Message] with the given parameters.
  /// The [channels] parameter specifies the number of channels in the message.
  /// The [data] parameter must be a list of integers with length equal to
  /// [channels]. Each integer must be in the range -128 to 127.
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  static Int8Message int8Message({
    String? uId,
    required List<int> data,
    int channels = 1,
    DateTime? timestamp,
  }) {
    final mapping = Int8Mapping(channels: channels);
    final type = MessageType<int, Int8Mapping>(mapping);
    return Int8Message(
      uId: uId,
      data: data,
      messageType: type,
      mapping: mapping,
      timestamp: timestamp,
    );
  }

  /// Creates a new [Int16Message] with the given parameters.
  /// The [channels] parameter specifies the number of channels in the message.
  /// The [data] parameter must be a list of integers with length equal to
  /// [channels]. Each integer must be in the range -32768 to 32767.
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  static Int16Message int16Message({
    String? uId,
    required List<int> data,
    int channels = 1,
    DateTime? timestamp,
  }) {
    final mapping = Int16Mapping(channels: channels);
    final type = MessageType<int, Int16Mapping>(mapping);
    return Int16Message(
      uId: uId,
      data: data,
      messageType: type,
      mapping: mapping,
      timestamp: timestamp,
    );
  }

  /// Creates a new [Int32Message] with the given parameters.
  /// The [channels] parameter specifies the number of channels in the message.
  /// The [data] parameter must be a list of integers with length equal to
  /// [channels]. Each integer must be in the range -2147483648 to 2147483647.
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  static Int32Message int32Message({
    String? uId,
    required List<int> data,
    int channels = 1,
    DateTime? timestamp,
  }) {
    final mapping = Int32Mapping(channels: channels);
    final type = MessageType<int, Int32Mapping>(mapping);
    return Int32Message(
      uId: uId,
      data: data,
      messageType: type,
      mapping: mapping,
      timestamp: timestamp,
    );
  }

  /// Creates a new [Int64Message] with the given parameters.
  /// The [channels] parameter specifies the number of channels in the message.
  /// The [data] parameter must be a list of integers with length equal to
  /// [channels]. Each integer must be in the range -9223372036854775808 to
  /// 9223372036854775807.
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  static Int64Message int64Message({
    String? uId,
    required List<int> data,
    int channels = 1,
    DateTime? timestamp,
  }) {
    final mapping = Int64Mapping(channels: channels);
    final type = MessageType<int, Int64Mapping>(mapping);
    return Int64Message(
      uId: uId,
      data: data,
      messageType: type,
      mapping: mapping,
      timestamp: timestamp,
    );
  }

  /// Creates a new [Float32Message] with the given parameters.
  /// The [channels] parameter specifies the number of channels in the message.
  /// The [data] parameter must be a list of doubles with length equal to
  /// [channels].
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  static Float32Message float32Message({
    String? uId,
    required List<double> data,
    int channels = 1,
    DateTime? timestamp,
  }) {
    final mapping = Float32Mapping(channels: channels);
    final type = MessageType<double, Float32Mapping>(mapping);
    return Float32Message(
      uId: uId,
      data: data,
      messageType: type,
      mapping: mapping,
      timestamp: timestamp,
    );
  }

  /// Creates a new [Double64Message] with the given parameters.
  /// The [channels] parameter specifies the number of channels in the message.
  /// The [data] parameter must be a list of doubles with length equal to
  /// [channels].
  /// The [uId] parameter is optional and will be generated if not provided.
  /// The [timestamp] parameter is optional and will be set to the current time
  /// if not provided.
  static Double64Message double64Message({
    String? uId,
    required List<double> data,
    int channels = 1,
    DateTime? timestamp,
  }) {
    final mapping = Double64Mapping(channels: channels);
    final type = MessageType<double, Double64Mapping>(mapping);
    return Double64Message(
      uId: uId,
      data: data,
      messageType: type,
      mapping: mapping,
      timestamp: timestamp,
    );
  }
}
