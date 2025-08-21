import 'package:liblsl/lsl.dart';
import '../../../session/stream_config.dart';

/// LSL-specific implementation of ChannelFormat
class CoordinatorLSLChannelFormat implements ChannelFormat {
  final LSLChannelFormat _lslFormat;
  
  const CoordinatorLSLChannelFormat._(this._lslFormat);
  
  // Static instances for common formats
  static const CoordinatorLSLChannelFormat float32 = CoordinatorLSLChannelFormat._(LSLChannelFormat.float32);
  static const CoordinatorLSLChannelFormat double64 = CoordinatorLSLChannelFormat._(LSLChannelFormat.double64);
  static const CoordinatorLSLChannelFormat int8 = CoordinatorLSLChannelFormat._(LSLChannelFormat.int8);
  static const CoordinatorLSLChannelFormat int16 = CoordinatorLSLChannelFormat._(LSLChannelFormat.int16);
  static const CoordinatorLSLChannelFormat int32 = CoordinatorLSLChannelFormat._(LSLChannelFormat.int32);
  static const CoordinatorLSLChannelFormat int64 = CoordinatorLSLChannelFormat._(LSLChannelFormat.int64);
  static const CoordinatorLSLChannelFormat string = CoordinatorLSLChannelFormat._(LSLChannelFormat.string);
  
  /// Get the underlying LSL channel format
  LSLChannelFormat get lslFormat => _lslFormat;
  
  @override
  String get name => _lslFormat.name;
  
  @override
  int get bytesPerSample {
    switch (_lslFormat) {
      case LSLChannelFormat.float32:
        return 4;
      case LSLChannelFormat.double64:
        return 8;
      case LSLChannelFormat.int8:
        return 1;
      case LSLChannelFormat.int16:
        return 2;
      case LSLChannelFormat.int32:
        return 4;
      case LSLChannelFormat.int64:
        return 8;
      case LSLChannelFormat.string:
        return -1; // Variable size
      default:
        return 0;
    }
  }
  
  @override
  bool supportsType<T>() {
    switch (_lslFormat) {
      case LSLChannelFormat.float32:
      case LSLChannelFormat.double64:
        return T == double || T == num;
      case LSLChannelFormat.int8:
      case LSLChannelFormat.int16:
      case LSLChannelFormat.int32:
      case LSLChannelFormat.int64:
        return T == int || T == num;
      case LSLChannelFormat.string:
        return T == String;
      default:
        return false;
    }
  }
  
  /// Create CoordinatorLSLChannelFormat from the liblsl enum
  factory CoordinatorLSLChannelFormat.fromLSL(LSLChannelFormat format) {
    switch (format) {
      case LSLChannelFormat.float32:
        return CoordinatorLSLChannelFormat.float32;
      case LSLChannelFormat.double64:
        return CoordinatorLSLChannelFormat.double64;
      case LSLChannelFormat.int8:
        return CoordinatorLSLChannelFormat.int8;
      case LSLChannelFormat.int16:
        return CoordinatorLSLChannelFormat.int16;
      case LSLChannelFormat.int32:
        return CoordinatorLSLChannelFormat.int32;
      case LSLChannelFormat.int64:
        return CoordinatorLSLChannelFormat.int64;
      case LSLChannelFormat.string:
        return CoordinatorLSLChannelFormat.string;
      default:
        throw ArgumentError('Unsupported LSL channel format: $format');
    }
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) || 
      other is CoordinatorLSLChannelFormat && other._lslFormat == _lslFormat;
  
  @override
  int get hashCode => _lslFormat.hashCode;
  
  @override
  String toString() => 'CoordinatorLSLChannelFormat($_lslFormat)';
}