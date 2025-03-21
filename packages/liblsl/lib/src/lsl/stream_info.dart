import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, Utf8, Utf8Pointer;
import 'package:liblsl/liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/ffi/mem.dart';

class LSLStreamInfo extends LSLObj {
  final String streamName;
  final LSLContentType streamType;
  final int channelCount;
  final double sampleRate;
  final LSLChannelFormat channelFormat;
  final String sourceId;
  lsl_streaminfo? _streamInfo;

  LSLStreamInfo({
    this.streamName = "DartLSLStream",
    this.streamType = LSLContentType.eeg,
    this.channelCount = 16,
    this.sampleRate = 250.0,
    this.channelFormat = LSLChannelFormat.float32,
    this.sourceId = "DartLSL",
    lsl_streaminfo? streamInfo,
  }) : _streamInfo = streamInfo {
    if (streamInfo != null) {
      _streamInfo = streamInfo;
      super.create();
    }
  }

  lsl_streaminfo? get streamInfo => _streamInfo;

  @override
  create() {
    if (created) {
      throw LSLException('StreamInfo already created');
    }
    final streamNamePtr =
        streamName.toNativeUtf8(allocator: allocate).cast<Char>();
    final sourceIdPtr = sourceId.toNativeUtf8(allocator: allocate).cast<Char>();
    final streamTypePtr = streamType.charPtr;

    addAllocList([streamNamePtr, sourceIdPtr, streamTypePtr]);
    _streamInfo = lsl_create_streaminfo(
      streamNamePtr,
      streamTypePtr,
      channelCount,
      sampleRate,
      channelFormat.lslFormat,
      sourceIdPtr,
    );
    super.create();
    return this;
  }

  factory LSLStreamInfo.fromStreamInfo(lsl_streaminfo streamInfo) {
    // get all the values
    final Pointer<Utf8> streamName = lsl_get_name(streamInfo) as Pointer<Utf8>;
    final Pointer<Utf8> streamType = lsl_get_type(streamInfo) as Pointer<Utf8>;
    final int channelCount = lsl_get_channel_count(streamInfo);
    final double sampleRate = lsl_get_nominal_srate(streamInfo);
    final lsl_channel_format_t channelFormat = lsl_get_channel_format(
      streamInfo,
    );
    final Pointer<Utf8> sourceId =
        lsl_get_source_id(streamInfo) as Pointer<Utf8>;

    final info = LSLStreamInfo(
      streamName: streamName.toDartString(),
      streamType: LSLContentType.values.firstWhere(
        (e) => e.value == streamType.toDartString(),
      ),
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: LSLChannelFormat.values.firstWhere(
        (e) => e.lslFormat == channelFormat,
      ),
      sourceId: sourceId.toDartString(),
      streamInfo: streamInfo,
    );
    info.addAllocList([streamName, streamType, sourceId]);
    return info;
  }

  @override
  void destroy() {
    if (destroyed) {
      return;
    }
    if (_streamInfo != null) {
      lsl_destroy_streaminfo(_streamInfo!);
      //allocate.free(_streamInfo!);
      _streamInfo = null;
    }
    super.destroy();
  }

  @override
  String toString() {
    return 'LSLStreamInfo{streamName: $streamName, streamType: $streamType, channelCount: $channelCount, sampleRate: $sampleRate, channelFormat: $channelFormat, sourceId: $sourceId}';
  }
}
