import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/push_sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:ffi/ffi.dart' show Utf8, StringUtf8Pointer;

// todo: change this to use a similar method to the inlet

/// Representation of the lsl_outlet_struct_ from the LSL C API.
class LSLStreamOutlet extends LSLObj {
  final LSLStreamInfo streamInfo;
  final int chunkSize;
  final int maxBuffer;
  late final LslPushSample _pushFn;
  lsl_outlet? _streamOutlet;

  /// Creates a new LSLStreamOutlet object.
  ///
  /// The [streamInfo] parameter is used to determine the type of data for the
  /// given outlet and other LSL parameters.
  /// The [chunkSize] parameter (in samples) determines how to hand off samples
  /// to the buffer, 0 creates a chunk for each push.
  /// network level buffer which is fine for recording applications.
  /// The [maxBuffer] parameter determines the the size of the buffer that
  /// stores incoming samples. NOTE: This is in seconds, if the stream has
  /// a sample rate, otherwise it is in 100s of samples (maxBuffer * 10^2).
  /// High values will use more memory, low values may lose samples, this should
  /// be set as close as possible to the rate of consumption.
  LSLStreamOutlet({
    required this.streamInfo,
    this.chunkSize = 0,
    this.maxBuffer = 360,
  }) {
    if (streamInfo.streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _pushFn = LSLMapper().streamPush(streamInfo);
  }

  @override
  create() {
    _streamOutlet = lsl_create_outlet(
      streamInfo.streamInfo!,
      chunkSize,
      maxBuffer,
    );
    if (_streamOutlet == null) {
      throw LSLException('Error creating outlet');
    }
    super.create();
    return this;
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
    streamInfo.destroy();
    super.destroy();
  }

  /// Waits for a consumer (e.g. LabRecorder, another inlet) to connect to the
  /// outlet.
  ///
  /// The [timeout] parameter determines the maximum time to wait for a
  /// consumer to connect.
  ///
  /// If [exception] is true, an exception will be thrown if no consumer is
  /// found within the timeout period. This should be the default way to use
  /// this method.
  Future<void> waitForConsumer({
    double timeout = 60,
    bool exception = true,
  }) async {
    final consumerFound = lsl_wait_for_consumers(_streamOutlet!, timeout);
    if (consumerFound == 0 && exception) {
      throw LSLTimeout('No consumer found within $timeout seconds');
    }
  }

  // this can be made more efficient, just create the function during create.

  /// Allocates a sample of the appropriate type for the given data.
  ///
  /// The [data] parameter is a list of dynamic values that will be used to
  /// initialize the sample. The type should match the channel format.
  ///
  /// @todo: implement in the same way as inlet.
  Pointer _allocSample(List<dynamic> data) {
    switch (streamInfo.channelFormat.ffiType) {
      case const (Float):
        final ptr = allocate<Float>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Double):
        final ptr = allocate<Double>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int8):
        final ptr = allocate<Int8>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int16):
        final ptr = allocate<Int16>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int32):
        final ptr = allocate<Int32>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int64):
        final ptr = allocate<Int64>(streamInfo.channelCount);
        for (var i = 0; i < streamInfo.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Pointer<Char>):
        if (data.every((item) => item is String)) {
          // For a single string in a single channel
          final stringArray = allocate<Pointer<Char>>(streamInfo.channelCount);
          for (var i = 0; i < streamInfo.channelCount; i++) {
            // Convert the string to a native UTF8 string and store the pointer
            final Pointer<Utf8> utf8String = (data[i] as String).toNativeUtf8(
              allocator: allocate,
            );
            stringArray[i] = utf8String.cast<Char>();
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

  /// Pushes a sample to the outlet.
  ///
  /// The [data] parameter is a list of dynamic values that will be used to
  /// initialize the sample. The type should match the channel format.
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
      if (LSLObj.error(result)) {
        throw LSLException('Error pushing sample: $result');
      }
      return result;
    } finally {
      samplePtr.free();
    }
  }

  lsl_outlet? get streamOutlet => _streamOutlet;

  @override
  String toString() {
    return 'LSLStreamOutlet{streamInfo: $streamInfo, chunkSize: $chunkSize, maxBuffer: $maxBuffer}';
  }
}
