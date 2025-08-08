import 'dart:async';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/api_config.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/inlet.dart';
import 'package:liblsl/src/lsl/outlet.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/stream_resolver.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer, StringUtf8Pointer;

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

  /// Sets the configuration filename for the LSL library.
  ///
  /// @param [filename] The path to the configuration file.
  ///
  /// @note: This should be called before any other LSL operations.
  /// @note: see https://labstreaminglayer.readthedocs.io/info/lslapicfg.html#configuration-file-contents
  static void setConfigFilename(String filename) {
    final filenamePtr = filename.toNativeUtf8();
    lsl_set_config_filename(filenamePtr.cast());
    filenamePtr.free();
  }

  /// Sets the configuration for the LSL library.
  ///
  /// @param [content] The configuration [LSLApiConfig].
  ///
  /// @note: This should be called before any other LSL operations.
  /// @note: see https://labstreaminglayer.readthedocs.io/info/lslapicfg.html#configuration-file-contents
  static void setConfigContent(LSLApiConfig content) {
    final contentPtr = content.toIniString().toNativeUtf8();
    lsl_set_config_content(contentPtr.cast());
    contentPtr.free();
  }

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
  /// [useIsolates] determines whether to use isolates for thread safety.
  /// If true, the outlet will use isolates to ensure thread safety.
  /// Important: If you do not use isolates, you must ensure that you deal with
  /// the consequences of blocking operations which will block the main dart
  /// isolate.
  static Future<LSLOutlet> createOutlet({
    required LSLStreamInfo streamInfo,
    int chunkSize = 1,
    int maxBuffer = 360,
    bool useIsolates = true,
  }) async {
    final streamOutlet = LSLOutlet(
      streamInfo,
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
      useIsolates: useIsolates,
    );
    await streamOutlet.create();

    return streamOutlet;
  }

  /// Creates a new inlet object.
  ///
  /// [streamInfo] is the [LSLStreamInfo] object to be used. Probably obtained
  ///   from a [LSLStreamResolver].
  /// [maxBuffer] this is the either seconds (if [streamInfo].sampleRate
  /// is specified) or 100s of samples (if not).
  /// [chunkSize] is the maximum number of samples. If 0, the default
  ///  chunk length from the stream is used.
  /// [recover] is whether to recover from lost samples.
  /// [createTimeout] is the timeout for creating the inlet.
  /// [useIsolates] determines whether to use isolates for thread safety.
  /// If true, the inlet will use isolates to ensure thread safety.
  /// Important: If you do not use isolates, you must ensure that you deal with
  /// the consequences of blocking operations which will block the main dart
  /// isolate.
  static Future<LSLInlet> createInlet<T>({
    required LSLStreamInfo streamInfo,
    int maxBuffer = 360,
    int chunkSize = 0,
    bool recover = true,
    double createTimeout = LSL_FOREVER,
    bool useIsolates = true,
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
      final inlet = LSLInlet<double>(
        streamInfo,
        maxBuffer: maxBuffer,
        chunkSize: chunkSize,
        recover: recover,
        createTimeout: createTimeout,
        useIsolates: useIsolates,
      );
      await inlet.create();
      return inlet;
    } else if (dataType == int) {
      final inlet = LSLInlet<int>(
        streamInfo,
        maxBuffer: maxBuffer,
        chunkSize: chunkSize,
        recover: recover,
        createTimeout: createTimeout,
        useIsolates: useIsolates,
      );
      await inlet.create();
      return inlet;
    } else if (dataType == String) {
      final inlet = LSLInlet<String>(
        streamInfo,
        maxBuffer: maxBuffer,
        chunkSize: chunkSize,
        recover: recover,
        createTimeout: createTimeout,
        useIsolates: useIsolates,
      );
      await inlet.create();
      return inlet;
    }

    throw LSLException('Unsupported data type: $dataType');
  }

  /// Resolves streams available on the network immediately.
  ///
  /// [waitTime] is the time to wait for streams to resolve.
  /// [maxStreams] is the maximum number of streams to resolve.
  /// [forgetAfter] is the time to forget streams that are not seen.
  ///
  /// This method is not the most efficient way to resolve streams,
  /// but if you need a one-off resolution of streams, this is ok.
  /// It is recommended to use [LSLStreamResolverContinuous] for continuous
  /// stream resolution, which runs in the background and you can call
  /// [LSLStreamResolverContinuous.resolve] to get the latest streams.
  static Future<List<LSLStreamInfo>> resolveStreams({
    double waitTime = 5.0,
    int maxStreams = 5,
    double forgetAfter = 5.0,
  }) async {
    final resolver = createContinuousStreamResolver(
      forgetAfter: forgetAfter,
      maxStreams: maxStreams,
    );
    final streams = await resolver.resolve(waitTime: waitTime);
    // free the resolver
    resolver.destroy();
    // these stream info pointers remain until they are destroyed
    return streams;
  }

  /// Creates a new [LSLStreamResolverContinuous] for continuous stream
  /// resolution. It allocates and starts resolving immediately.
  /// You can use [LSLStreamResolverContinuous.resolve] to get the latest
  /// streams.
  ///
  /// [forgetAfter] is the time to forget streams that are not seen.
  /// [maxStreams] is the maximum number of streams to resolve.
  ///
  /// @note: You must call [LSLStreamResolverContinuous.destroy] to free the
  /// resources when you are done with the resolver.
  static LSLStreamResolverContinuous createContinuousStreamResolver({
    double forgetAfter = 5.0,
    int maxStreams = 5,
  }) {
    return LSLStreamResolverContinuous(
      forgetAfter: forgetAfter,
      maxStreams: maxStreams,
    )..create();
  }

  /// Returns the local clock time, used to calculate offsets.
  static double localClock() => lsl_local_clock();

  /// Returns the version of the LSL library.
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
