import 'dart:ffi';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/push_sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/structs.dart';

/// LSLMapper type mapping.
///
/// Handles a lot of the complexity of converting between the
/// LSL / FFI [NativeType] types and dart [Type] types.
/// @note This class is a singleton, so it should be used as a static class.
class LSLMapper {
  static LSLMapper? _instance;

  /// Map of [StreamInfo.channelFormat] to [LSLPushSample].
  static final Map<LSLChannelFormat, LSLPushSample> _pushSampleMap = {
    LSLChannelFormat.float32: LSLPushSampleFloat(),
    LSLChannelFormat.double64: LSLPushSampleDouble(),
    LSLChannelFormat.int8: LSLPushSampleInt8(),
    LSLChannelFormat.int16: LSLPushSampleInt16(),
    LSLChannelFormat.int32: LSLPushSampleInt32(),
    LSLChannelFormat.int64: LSLPushSampleInt64(),
    LSLChannelFormat.string: LSLPushSampleString(),
    LSLChannelFormat.undefined: LSLPushSampleVoid(),
  };

  /// Map of [StreamInfo.channelFormat] to [LSLPullSample].
  static final Map<LSLChannelFormat, LSLPullSample> _pullSampleMap = {
    LSLChannelFormat.float32: LSLPullSampleFloat(),
    LSLChannelFormat.double64: LSLPullSampleDouble(),
    LSLChannelFormat.int8: LSLPullSampleInt8(),
    LSLChannelFormat.int16: LSLPullSampleInt16(),
    LSLChannelFormat.int32: LSLPullSampleInt32(),
    LSLChannelFormat.int64: LSLPullSampleInt64(),
    LSLChannelFormat.string: LSLPullSampleString(),
    LSLChannelFormat.undefined: LSLPullSampleUndefined(),
  };

  LSLMapper._();

  factory LSLMapper() {
    _instance ??= LSLMapper._();
    return _instance!;
  }

  Map<LSLChannelFormat, LSLPushSample> get pushSampleMap => _pushSampleMap;
  Map<LSLChannelFormat, LSLPullSample> get pullSampleMap => _pullSampleMap;

  /// Gets the [LSLPushSample] for the given [LSLStreamInfo].
  LSLPushSample streamPush(LSLStreamInfo streamInfo) {
    final LSLChannelFormat channelFormat = streamInfo.channelFormat;
    if (_pushSampleMap.containsKey(channelFormat)) {
      return _pushSampleMap[channelFormat]!;
    } else {
      throw LSLException('Unsupported channel format: $channelFormat');
    }
  }

  /// Gets the [LSLPullSample] for the given [LSLStreamInfo].
  LSLPullSample streamPull(LSLStreamInfo streamInfo) {
    final LSLChannelFormat channelFormat = streamInfo.channelFormat;
    if (_pullSampleMap.containsKey(channelFormat)) {
      return _pullSampleMap[channelFormat]!;
    } else {
      throw LSLException('Unsupported channel format: $channelFormat');
    }
  }
}
