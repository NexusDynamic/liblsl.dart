import 'package:lsl_core/lsl_core.dart' show LSLChannelFormat;
import 'package:peer_coordinator/framework.dart' show StreamDataType;

extension LSLType on StreamDataType {
  /// Converts a [StreamDataType] to the corresponding LSL channel format.
  LSLChannelFormat toLSLChannelFormat() {
    switch (this) {
      case StreamDataType.int8:
        return LSLChannelFormat.int8;
      case StreamDataType.int16:
        return LSLChannelFormat.int16;
      case StreamDataType.int32:
        return LSLChannelFormat.int32;
      case StreamDataType.int64:
        return LSLChannelFormat.int64;
      case StreamDataType.float32:
        return LSLChannelFormat.float32;
      case StreamDataType.double64:
        return LSLChannelFormat.double64;
      case StreamDataType.string:
        return LSLChannelFormat.string;
    }
  }
}
