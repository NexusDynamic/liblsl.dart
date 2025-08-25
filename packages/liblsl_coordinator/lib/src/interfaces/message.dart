import 'package:liblsl_coordinator/data.dart';
import 'package:liblsl_coordinator/interfaces.dart';

/// Interface representing a message type with specific data characteristics.
abstract interface class IMessageType<T> implements IIdentity, ISerializable {
  /// The data type of the stream message
  StreamDataType get type;

  /// The number of channels in the stream message
  int get channels;
}

/// Interface representing a message with a specific type and associated data.
abstract interface class IMessage<T extends IMessageType>
    implements IUniqueIdentity, ITimestamped, ISerializable, IHasMetadata {
  /// The type of the message
  T get messageType;

  /// The data associated with the message
  List get data;
}
