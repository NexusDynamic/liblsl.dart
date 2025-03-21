import 'dart:async';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/stream_inlet.dart';
import 'package:liblsl/src/lsl/stream_outlet.dart';
import 'package:liblsl/src/lsl/stream_resolver.dart';
import 'package:liblsl/src/lsl/structs.dart';

/// Interface to the LSL library.
///
/// This class provides a high-level interface to the LSL library, allowing
/// you to create and manage streams, outlets, and inlets.
class LSL {
  LSLStreamInfo? _streamInfo;
  LSLStreamOutlet? _streamOutlet;
  LSLStreamInlet? _streamInlet;
  LSL();

  /// Creates a new [LSLStreamInfo] object.
  ///
  /// [streamName] is the name of the stream.
  /// [streamType] is the [LSLContentType] of the stream (e.g. EEG, mocap, ...).
  /// [channelCount] is the number of channels in the stream.
  /// [streamType] is the stream's [LSLChannelFormat] (e.g. string, int8).
  /// [sourceId] is the source ID of the stream which should be unique.
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

  /// Returns the version of the LSL library.
  int get version => lsl_library_version();

  /// Returns the [LSLStreamInfo] object.
  LSLStreamInfo? get info => _streamInfo;

  /// Returns the [LSLStreamInlet] object.
  LSLStreamOutlet? get outlet => _streamOutlet;

  /// Creates a new [LSLStreamOutlet] object.
  ///
  /// [chunkSize] is the size of the chunk to be sent.
  /// [maxBuffer] is the maximum number of samples to be buffered.
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

  /// Creates a new [LSLStreamInlet] object.
  ///
  /// [streamInfo] is the [LSLStreamInfo] object to be used. Probably obtained
  ///   from a [LSLStreamResolver].
  /// [maxBufferSize] is the size of the buffer to be used.
  /// [maxChunkLength] is the maximum number of samples to be buffered.
  /// [recover] is whether to recover from lost samples.
  Future<LSLStreamInlet> createInlet({
    required LSLStreamInfo streamInfo,
    int maxBufferSize = 0,
    int maxChunkLength = 0,
    bool recover = true,
  }) async {
    if (_streamInlet != null) {
      throw LSLException('Inlet already created');
    }

    if (!streamInfo.created) {
      throw LSLException('StreamInfo not created');
    }

    switch (streamInfo.channelFormat.dartType) {
      case const (double):
        _streamInlet = LSLStreamInlet<double>(
          streamInfo,
          maxBufferSize: maxBufferSize,
          maxChunkLength: maxChunkLength,
          recover: recover,
        );
        break;
      case const (int):
        _streamInlet = LSLStreamInlet<int>(
          streamInfo,
          maxBufferSize: maxBufferSize,
          maxChunkLength: maxChunkLength,
          recover: recover,
        );
        break;
      case const (String):
        _streamInlet = LSLStreamInlet<String>(
          streamInfo,
          maxBufferSize: maxBufferSize,
          maxChunkLength: maxChunkLength,
          recover: recover,
        );
        break;
      default:
        throw LSLException('Invalid channel format');
    }

    _streamInlet?.create();
    return _streamInlet!;
  }

  /// Resolves streams available on the network.
  ///
  /// [waitTime] is the time to wait for streams to resolve.
  /// [maxStreams] is the maximum number of streams to resolve.
  /// [forgetAfter] is the time to forget streams that are not seen.
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

  /// Returns the local clock time, used to calculate offsets.
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
