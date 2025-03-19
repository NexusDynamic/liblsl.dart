import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, Utf8, Utf8Pointer;
import 'package:liblsl/liblsl.dart';
import 'src/types.dart';
import 'src/ffi/mem.dart';

typedef DartLslPushSample<T extends NativeType> =
    int Function(lsl_outlet out, Pointer<T> data);

// Create a wrapper class to handle the different types
class LslPushSample<T extends NativeType> {
  final DartLslPushSample<T> _pushFn;

  const LslPushSample(this._pushFn);

  int call(lsl_outlet out, Pointer<T> data) {
    return _pushFn(out, data);
  }
}

enum LSLContentType {
  /// EEG (for Electroencephalogram)
  eeg("EEG"),

  /// MoCap (for Motion Capture)
  mocap("MoCap"),

  /// NIRS (Near-Infrared Spectroscopy)
  nirs("NIRS"),

  /// Gaze (for gaze / eye tracking parameters)
  gaze("Gaze"),

  /// VideoRaw (for uncompressed video)
  videoRaw("VideoRaw"),

  /// VideoCompressed (for compressed video)
  videoCompressed("VideoCompressed"),

  /// Audio (for PCM-encoded audio)
  audio("Audio"),

  /// Markers (for event marker streams)
  markers("Markers");

  final String value;

  const LSLContentType(this.value);

  Pointer<Char> get charPtr =>
      value.toNativeUtf8(allocator: allocate) as Pointer<Char>;
}

enum LSLChannelFormat {
  float32,
  double64,
  int8,
  int16,
  int32,
  int64,
  string,
  undefined;

  lsl_channel_format_t get lslFormat {
    switch (this) {
      case LSLChannelFormat.float32:
        return lsl_channel_format_t.cft_float32;
      case LSLChannelFormat.double64:
        return lsl_channel_format_t.cft_double64;
      case LSLChannelFormat.int8:
        return lsl_channel_format_t.cft_int8;
      case LSLChannelFormat.int16:
        return lsl_channel_format_t.cft_int16;
      case LSLChannelFormat.int32:
        return lsl_channel_format_t.cft_int32;
      case LSLChannelFormat.int64:
        return lsl_channel_format_t.cft_int64;
      case LSLChannelFormat.string:
        return lsl_channel_format_t.cft_string;
      case LSLChannelFormat.undefined:
        return lsl_channel_format_t.cft_undefined;
    }
  }

  Type get ffiType {
    switch (this) {
      case LSLChannelFormat.float32:
        return Float;
      case LSLChannelFormat.double64:
        return Double;
      case LSLChannelFormat.int8:
        return Int8;
      case LSLChannelFormat.int16:
        return Int16;
      case LSLChannelFormat.int32:
        return Int32;
      case LSLChannelFormat.int64:
        return Int64;
      case LSLChannelFormat.string:
        return Pointer<Char>;
      case LSLChannelFormat.undefined:
        return Void;
    }
  }

  LslPushSample get pushFn {
    switch (this) {
      case LSLChannelFormat.float32:
        return LslPushSample<Float>(lsl_push_sample_f);
      case LSLChannelFormat.double64:
        return LslPushSample<Double>(lsl_push_sample_d);
      case LSLChannelFormat.int8:
        return LslPushSample<Char>(lsl_push_sample_c);
      case LSLChannelFormat.int16:
        return LslPushSample<Int16>(lsl_push_sample_s);
      case LSLChannelFormat.int32:
        return LslPushSample<Int32>(lsl_push_sample_i);
      case LSLChannelFormat.int64:
        return LslPushSample<Int64>(lsl_push_sample_l);
      case LSLChannelFormat.string:
        return LslPushSample<Pointer<Char>>(lsl_push_sample_str);
      case LSLChannelFormat.undefined:
        return LslPushSample<Void>(lsl_push_sample_v);
    }
  }
}

// const Map<str, Function

/// Further bits of meta-data that can be associated with a stream are the following:

// Human-Subject Information
// Recording Environment Information
// Experiment Information
// Synchronization Information

abstract class MemManaged {
  final List<Pointer> _allocatedArgs = [];

  void freeArgs() {
    for (final arg in _allocatedArgs) {
      arg.free();
    }
    _allocatedArgs.clear();
  }
}

abstract class LSLObj extends MemManaged {
  dynamic create();
  void destroy();
  bool error(int code) {
    final e = lsl_error_code_t.fromValue(code);
    return e != lsl_error_code_t.lsl_no_error;
  }
}

class LSLSample<T extends NativeType> {
  final Pointer<T> data;

  LSLSample(this.data);
}

class LSLSampleTs<T extends NativeType> extends LSLSample<T> {
  final double timestamp;

  LSLSampleTs(super.data, this.timestamp);
}

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
    }
  }

  lsl_streaminfo? get streamInfo => _streamInfo;

  @override
  lsl_streaminfo create() {
    final streamNamePtr =
        streamName.toNativeUtf8(allocator: allocate) as Pointer<Char>;
    final sourceIdPtr =
        sourceId.toNativeUtf8(allocator: allocate) as Pointer<Char>;
    final streamTypePtr = streamType.charPtr;

    _allocatedArgs.addAll([streamNamePtr, sourceIdPtr, streamTypePtr]);
    _streamInfo = lsl_create_streaminfo(
      streamNamePtr,
      streamTypePtr,
      channelCount,
      sampleRate,
      channelFormat.lslFormat,
      sourceIdPtr,
    );
    return _streamInfo!;
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
    info._allocatedArgs.addAll([streamName, streamType, sourceId]);

    return info;
  }

  @override
  void destroy() {
    if (_streamInfo != null) {
      lsl_destroy_streaminfo(_streamInfo!);
      //allocate.free(_streamInfo!);
      _streamInfo = null;
    }
    freeArgs();
  }

  @override
  String toString() {
    return 'LSLStreamInfo{streamName: $streamName, streamType: $streamType, channelCount: $channelCount, sampleRate: $sampleRate, channelFormat: $channelFormat, sourceId: $sourceId}';
  }
}

class LSLStreamResolverContinuous extends LSLObj {
  int maxStreams;
  final double forgetAfter;
  Pointer<lsl_streaminfo>? _streamInfoBuffer;
  lsl_continuous_resolver? _resolver;

  LSLStreamResolverContinuous({this.forgetAfter = 5.0, this.maxStreams = 5});

  @override
  void create() {
    _streamInfoBuffer = allocate<lsl_streaminfo>(maxStreams);
    _resolver = lsl_create_continuous_resolver(forgetAfter);
  }

  /// Resolve streams
  Future<List<LSLStreamInfo>> resolve({double waitTime = 5.0}) async {
    if (_resolver == null) {
      throw LSLException('Resolver not created');
    }
    // pause for a bit
    await Future.delayed(Duration(milliseconds: (waitTime * 1000).toInt()));

    final int streamCount = lsl_resolver_results(
      _resolver!,
      _streamInfoBuffer!,
      maxStreams,
    );
    if (streamCount < 0) {
      throw LSLException('Error resolving streams: $streamCount');
    }
    final streams = <LSLStreamInfo>[];
    for (var i = 0; i < streamCount; i++) {
      final streamInfo = LSLStreamInfo.fromStreamInfo(_streamInfoBuffer![i]);
      streams.add(streamInfo);
    }
    return streams;
  }

  @override
  void destroy() {
    if (_streamInfoBuffer != null) {
      _streamInfoBuffer?.free();
      _streamInfoBuffer = null;
    }
    if (_resolver != null) {
      lsl_destroy_continuous_resolver(_resolver!);
      _resolver?.free();
      _resolver = null;
    }
    freeArgs();
  }

  @override
  String toString() {
    return 'LSLStreamResolverContinuous{maxStreams: $maxStreams, forgetAfter: $forgetAfter}';
  }
}

// class LSLStreamInlet extends LSLObj {
//   final lsl_inlet? _streamInlet;
//   late final LSLStreamInfo streamInfo;

//   LSLStreamInlet(this.streamInfo);

//   @override
//   lsl_inlet create() {
//     _streamInlet = lsl_create_inlet(streamInfo.streamInfo!);
//     return _streamInlet!;
//   }

//   @override
//   void destroy() {
//     if (_streamInlet != null) {
//       lsl_destroy_inlet(_streamInlet!);
//       _streamInlet?.free();
//     }
//     freeArgs();
//   }
// }

class LSLStreamOutlet extends LSLObj {
  final LSLStreamInfo streamInfo;
  final int chunkSize;
  final int maxBuffer;
  late final LslPushSample _pushFn;
  lsl_outlet? _streamOutlet;

  LSLStreamOutlet({
    required this.streamInfo,
    this.chunkSize = 0,
    this.maxBuffer = 1,
  }) {
    if (streamInfo.streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _pushFn = streamInfo.channelFormat.pushFn;
  }

  @override
  lsl_outlet create() {
    _streamOutlet = lsl_create_outlet(
      streamInfo.streamInfo!,
      chunkSize,
      maxBuffer,
    );
    return _streamOutlet!;
  }

  @override
  void destroy() {
    if (_streamOutlet != null) {
      lsl_destroy_outlet(_streamOutlet!);
      // i don't understand, i guess the pointer is freed in
      // lsl_destroy_outlet, but idk.
      // _streamOutlet?.free();
      _streamOutlet = null;
    }
    freeArgs();
  }

  Future<void> waitForConsumer({
    double timeout = 60,
    bool exception = true,
  }) async {
    final consumerFound = lsl_wait_for_consumers(_streamOutlet!, timeout);
    if (consumerFound == 0 && exception) {
      throw TimeoutException('No consumer found within $timeout seconds');
    }
  }

  // is this necessary? might slow down the process
  /// Check if the value is within the bounds of the type
  /// For example, if the type is Int8,
  /// the value should be between -128 and 127
  bool inTypeBounds(Type type, dynamic value) {
    switch (type) {
      case const (Float):
        return value is double;
      case const (Double):
        return value is double;
      case const (Int8):
        return value is int && value >= -128 && value <= 127;
      case const (Int16):
        return value is int && value >= -32768 && value <= 32767;
      case const (Int32):
        return value is int && value >= -2147483648 && value <= 2147483647;
      case const (Int64):
        return value is int &&
            value >= -9223372036854775808 &&
            value <= 9223372036854775807;
      default:
        return false;
    }
  }

  Pointer _allocSample(List<dynamic> data) {
    switch (streamInfo.channelFormat.ffiType) {
      case const (Float):
        final ptr = allocate<Float>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i].toDouble();
        }
        return ptr;
      case const (Double):
        final ptr = allocate<Double>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i].toDouble();
        }
        return ptr;
      case const (Int8):
        final ptr = allocate<Int8>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i].toInt();
        }
        return ptr;
      case const (Int16):
        final ptr = allocate<Int16>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i].toInt();
        }
        return ptr;
      case const (Int32):
        final ptr = allocate<Int32>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i].toInt();
        }
        return ptr;
      case const (Int64):
        final ptr = allocate<Int64>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i].toInt();
        }
        return ptr;
      case const (Pointer<Char>):
        if (data.every((item) => item is String)) {
          // For a single string in a single channel
          final stringArray = allocate<Pointer<Char>>(streamInfo.channelCount);
          for (var i = 0; i < streamInfo.channelCount; i++) {
            stringArray[i] = data[i].toString().toNativeUtf8().cast<Char>();
          }
          return stringArray;
        }
        throw LSLException('Invalid string data type');
      case const (Void):
        return nullPtr<Void>();
      default:
        throw LSLException('Invalid sample type');
    }
  }

  Future<int> pushSample(List<dynamic> data) async {
    if (data.length != streamInfo.channelCount) {
      throw LSLException(
        'Data length (${data.length}) does not match channel count (${streamInfo.channelCount})',
      );
    }
    final samplePtr = _allocSample(data);
    try {
      // Push the sample
      final int result = _pushFn(_streamOutlet!, samplePtr);
      if (error(result)) {
        throw LSLException('Error pushing sample: $result');
      }
      return result;
    } finally {
      if (streamInfo.channelFormat != LSLChannelFormat.string) {
        samplePtr.free();
      } else {
        // This is just a test
        Future.delayed(Duration(milliseconds: 100), () {
          samplePtr.free();
        });
      }
    }
  }

  @override
  String toString() {
    return 'LSLStreamOutlet{streamInfo: $streamInfo, chunkSize: $chunkSize, maxBuffer: $maxBuffer}';
  }
}

// need to implement full data types later
class LSL {
  LSLStreamInfo? _streamInfo;
  LSLStreamOutlet? _streamOutlet;
  // LSLStreamInlet? _streamInlet;
  LSL();

  Future<LSLStreamInfo> createStreamInfo({
    String streamName = "DartLSLStream",
    LSLContentType streamType = LSLContentType.eeg,
    int channelCount = 1,
    double sampleRate = 150.0,
    LSLChannelFormat channelFormat = LSLChannelFormat.float32,
    String sourceId = "DartLSL",
  }) async {
    _streamInfo = LSLStreamInfo(
      streamName: streamName,
      streamType: streamType,
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: channelFormat,
      sourceId: sourceId,
    );
    _streamInfo?.create();
    return _streamInfo!;
  }

  int get version => lsl_library_version();

  LSLStreamInfo? get info => _streamInfo;
  LSLStreamOutlet? get outlet => _streamOutlet;

  Future<LSLStreamOutlet> createOutlet({
    int chunkSize = 0,
    int maxBuffer = 1,
  }) async {
    if (_streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _streamOutlet = LSLStreamOutlet(
      streamInfo: _streamInfo!,
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
    );
    _streamOutlet?.create();
    return _streamOutlet!;
  }

  Future<List<LSLStreamInfo>> resolveStreams({
    double waitTime = 5.0,
    int maxStreams = 5,
    double forgetAfter = 5.0,
  }) async {
    final resolver = LSLStreamResolverContinuous(
      forgetAfter: forgetAfter,
      maxStreams: maxStreams,
    );
    resolver.create();
    final streams = await resolver.resolve(waitTime: waitTime);
    // free the resolver
    //resolver.destroy();
    // these stream info pointers remain until they are destroyed
    return streams;
  }

  double localClock() => lsl_local_clock();

  void destroy() {
    _streamInfo?.destroy();
    _streamOutlet?.destroy();
    // _streamInlet?.destroy();
  }

  @override
  String toString() {
    return 'LSL{streamInfo: $_streamInfo, streamOutlet: $_streamOutlet}';
  }
}
