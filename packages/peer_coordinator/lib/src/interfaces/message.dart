import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:peer_coordinator/data.dart';
import 'package:peer_coordinator/interfaces.dart';

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
  IList get data;

  /// Transport-observed timing for this message, or null when the transport
  /// could not supply it (or the message has not been over a wire at all).
  ///
  /// Unlike [timestamp], which is a local wall-clock reading, this carries the
  /// sender's clock and the offset needed to interpret it, so a receiver can
  /// characterise the actual network transit. See [MessageTiming].
  MessageTiming? get timing;
}
