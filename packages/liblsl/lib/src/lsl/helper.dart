import 'dart:ffi';
import 'package:liblsl/liblsl.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/push_sample.dart';
// import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/structs.dart';
// import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;

class LSLMapper {
  static LSLMapper? _instance;

  final Map<LSLChannelFormat, LslPushSample> _pushSampleMap = {
    LSLChannelFormat.float32: LslPushSample<Float>(lsl_push_sample_f),
    LSLChannelFormat.double64: LslPushSample<Double>(lsl_push_sample_d),
    LSLChannelFormat.int8: LslPushSample<Char>(lsl_push_sample_c),
    LSLChannelFormat.int16: LslPushSample<Int16>(lsl_push_sample_s),
    LSLChannelFormat.int32: LslPushSample<Int32>(lsl_push_sample_i),
    LSLChannelFormat.int64: LslPushSample<Int64>(lsl_push_sample_l),
    LSLChannelFormat.string: LslPushSample<Pointer<Char>>(lsl_push_sample_str),
    LSLChannelFormat.undefined: LslPushSample<Void>(lsl_push_sample_v),
  };

  final Map<LSLChannelFormat, LslPullSample> _pullSampleMap = {
    LSLChannelFormat.float32: LslPullSampleFloat(lsl_pull_sample_f),
    LSLChannelFormat.double64: LslPullSampleDouble(lsl_pull_sample_d),
    LSLChannelFormat.int8: LslPullSampleInt8(lsl_pull_sample_c),
    LSLChannelFormat.int16: LslPullSampleInt16(lsl_pull_sample_s),
    LSLChannelFormat.int32: LslPullSampleInt32(lsl_pull_sample_i),
    LSLChannelFormat.int64: LslPullSampleInt64(lsl_pull_sample_l),
    LSLChannelFormat.string: LslPullSampleString(lsl_pull_sample_str),
    LSLChannelFormat.undefined: LslPullSampleUndefined(lsl_pull_sample_v),
  };

  LSLMapper._();

  factory LSLMapper() {
    _instance ??= LSLMapper._();
    return _instance!;
  }

  Map<LSLChannelFormat, LslPushSample> get pushSampleMap => _pushSampleMap;
  Map<LSLChannelFormat, LslPullSample> get pullSampleMap => _pullSampleMap;

  LslPushSample streamPush(LSLStreamInfo streamInfo) {
    final LSLChannelFormat channelFormat = streamInfo.channelFormat;
    if (_pushSampleMap.containsKey(channelFormat)) {
      return _pushSampleMap[channelFormat]!;
    } else {
      throw LSLException('Unsupported channel format: $channelFormat');
    }
  }

  LslPullSample streamPull(LSLStreamInfo streamInfo) {
    final LSLChannelFormat channelFormat = streamInfo.channelFormat;
    if (_pullSampleMap.containsKey(channelFormat)) {
      return _pullSampleMap[channelFormat]!;
    } else {
      throw LSLException('Unsupported channel format: $channelFormat');
    }
  }
}
