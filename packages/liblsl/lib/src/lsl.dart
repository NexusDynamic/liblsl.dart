import 'dart:async';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/isolated_inlet.dart';
import 'package:liblsl/src/lsl/isolated_outlet.dart';
import 'package:liblsl/src/lsl/stream_resolver.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;

// Export LSL constants for public use
export 'package:liblsl/native_liblsl.dart' show LSL_FOREVER, LSL_IRREGULAR_RATE;

/// Interface to the LSL library.
///
/// This class provides a high-level interface to the LSL library, allowing
/// you to create and manage streams, outlets, and inlets.
class LSL {
  /// Don't use this constructor directly, use [LSL.createStreamInfo],
  /// [LSL.createOutlet], or [LSL.createInlet] instead.
  LSL._();

  /// Creates a new [LSLStreamInfo] object.
  ///
  /// [streamName] is the name of the stream.
  /// [streamType] is the [LSLContentType] of the stream (e.g. EEG, mocap, ...).
  /// [channelCount] is the number of channels in the stream.
  /// [streamType] is the stream's [LSLChannelFormat] (e.g. string, int8).
  /// [sourceId] is the source ID of the stream which should be unique.
  static Future<LSLStreamInfo> createStreamInfo({
    String streamName = "DartLSLStream",
    LSLContentType streamType = LSLContentType.eeg,
    int channelCount = 1,
    double sampleRate = 150.0,
    LSLChannelFormat channelFormat = LSLChannelFormat.float32,
    String sourceId = "DartLSL",
  }) async {
    final streamInfo = LSLStreamInfo(
      streamName: streamName,
      streamType: streamType,
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: channelFormat,
      sourceId: sourceId,
    );
    streamInfo.create();
    return streamInfo;
  }

  /// Returns the version of the LSL library.
  static int get version => lsl_library_version();

  /// Creates a new outlet object.
  ///
  /// [chunkSize] determines how to hand off samples to the buffer,
  /// 0 creates a chunk for each push.
  ///
  /// [maxBuffer] determines the size of the buffer that stores incoming
  /// samples. NOTE: This is in seconds, if the stream has a sample rate,
  /// otherwise it is in 100s of samples (maxBuffer * 10^2).
  /// High values will use more memory, low values may lose samples,
  /// this should be set as close as possible to the rate of consumption.
  static Future<LSLIsolatedOutlet> createOutlet({
    required LSLStreamInfo streamInfo,
    int chunkSize = 0,
    int maxBuffer = 360,
  }) async {
    final streamOutlet = LSLIsolatedOutlet(
      streamInfo: streamInfo,
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
    );
    await streamOutlet.create();

    return streamOutlet;
  }

  /// Creates a new inlet object.
  ///
  /// [streamInfo] is the [LSLStreamInfo] object to be used. Probably obtained
  ///   from a [LSLStreamResolver].
  /// [maxBufferSize] this is the either seconds (if [streamInfo].sampleRate
  /// is specified) or 100s of samples (if not).
  /// [maxChunkLength] is the maximum number of samples. If 0, the default
  ///  chunk length from the stream is used.
  /// [recover] is whether to recover from lost samples.
  static Future<LSLIsolatedInlet> createInlet<T>({
    required LSLStreamInfo streamInfo,
    int maxBufferSize = 360,
    int maxChunkLength = 0,
    bool recover = true,
    double createTimeout = LSL_FOREVER,
  }) async {
    if (!streamInfo.created) {
      throw LSLException('StreamInfo not created');
    }

    Type dataType;
    switch (streamInfo.channelFormat.dartType) {
      case const (double):
        dataType = double;
        break;
      case const (int):
        dataType = int;
        break;
      case const (String):
        dataType = String;
        break;
      default:
        throw LSLException('Invalid channel format');
    }

    // Check if the generic type matches the expected data type
    if (T != dynamic && T != dataType) {
      throw LSLException(
        'Generic type $T does not match expected data type $dataType for channel format ${streamInfo.channelFormat}',
      );
    }

    // Use isolated implementation
    if (dataType == double) {
      final inlet = LSLIsolatedInlet<double>(
        streamInfo,
        maxBufferSize: maxBufferSize,
        maxChunkLength: maxChunkLength,
        recover: recover,
        createTimeout: createTimeout,
      );
      await inlet.create();
      return inlet;
    } else if (dataType == int) {
      final inlet = LSLIsolatedInlet<int>(
        streamInfo,
        maxBufferSize: maxBufferSize,
        maxChunkLength: maxChunkLength,
        recover: recover,
        createTimeout: createTimeout,
      );
      await inlet.create();
      return inlet;
    } else if (dataType == String) {
      final inlet = LSLIsolatedInlet<String>(
        streamInfo,
        maxBufferSize: maxBufferSize,
        maxChunkLength: maxChunkLength,
        recover: recover,
        createTimeout: createTimeout,
      );
      await inlet.create();
      return inlet;
    }

    throw LSLException('Unsupported data type: $dataType');
  }

  /// Resolves streams available on the network.
  ///
  /// [waitTime] is the time to wait for streams to resolve.
  /// [maxStreams] is the maximum number of streams to resolve.
  /// [forgetAfter] is the time to forget streams that are not seen.
  static Future<List<LSLStreamInfo>> resolveStreams({
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
    resolver.destroy();
    // these stream info pointers remain until they are destroyed
    return streams;
  }

  /// Returns the local clock time, used to calculate offsets.
  static double localClock() => lsl_local_clock();

  static String libraryInfo() {
    final version = lsl_library_info();
    if (version.isNullPointer) {
      throw LSLException('Failed to get library info');
    }
    final versionString = version.cast<Utf8>().toDartString();
    return versionString;
  }

  /// Cleans up all resources.
  void destroy() {}

  @override
  String toString() {
    return 'LSL{version: $version}';
  }
}
