import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, Utf8, Utf8Pointer;
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/ffi/mem.dart';

extension StreamInfoList on List<LSLStreamInfo> {
  void destroy() {
    for (final streamInfo in this) {
      streamInfo.destroy();
    }
  }
}

/// Representation of the lsl_streaminfo_struct_ from the LSL C API.
class LSLStreamInfo extends LSLObj {
  final String streamName;
  final LSLContentType streamType;
  final int channelCount;
  final double sampleRate;
  final LSLChannelFormat channelFormat;
  final String sourceId;
  lsl_streaminfo? _streamInfo;

  /// Creates a new LSLStreamInfo object.
  ///
  /// The [streamName], [streamType], [channelCount], [sampleRate],
  /// [channelFormat], and [sourceId] parameters are used to create
  /// the stream info object.
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

  /// The [Pointer] to the underlying lsl_streaminfo_struct_.
  lsl_streaminfo? get streamInfo => _streamInfo;

  /// Creates the stream info object, allocates memory, etc.
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

  String? get uid {
    if (_streamInfo == null) {
      return null;
    }
    final Pointer<Char> uidp = lsl_get_uid(_streamInfo!);
    if (uidp.isNullPointer) {
      return null;
    }

    try {
      return uidp.cast<Utf8>().toDartString();
    } catch (e) {
      return null;
    }
  }

  String? get hostname {
    if (_streamInfo == null) {
      return null;
    }

    final Pointer<Char> hostPtr = lsl_get_hostname(_streamInfo!);
    if (hostPtr.isNullPointer) {
      return null;
    }

    try {
      return hostPtr.cast<Utf8>().toDartString();
    } catch (e) {
      return null;
    }
  }

  factory LSLStreamInfo.fromStreamInfoAddr(int address) {
    final streamInfo = lsl_streaminfo.fromAddress(address);
    if (streamInfo.isNullPointer) {
      throw LSLException('Invalid stream info address');
    }
    return LSLStreamInfo.fromStreamInfo(streamInfo);
  }

  /// Creates a new LSLStreamInfo object from an existing lsl_streaminfo.
  ///
  /// When constructing inlets, this creates the [LSLStreamInfo] object based
  /// on an existing [lsl_streaminfo] object, which can be retrieved from a
  /// stream resolver.
  factory LSLStreamInfo.fromStreamInfo(lsl_streaminfo streamInfo) {
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
    return 'LSLStreamInfo[$uid]{streamName: $streamName, streamType: $streamType, channelCount: $channelCount, sampleRate: $sampleRate, channelFormat: $channelFormat, sourceId: $sourceId, host: $hostname}';
  }
}
