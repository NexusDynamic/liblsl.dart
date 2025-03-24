import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// Representation of the lsl_continuous_resolver_ from the LSL C API.
///
/// Stream resolution means finding streams available on the network for
/// consumption.
class LSLStreamResolverContinuous extends LSLObj {
  int maxStreams;
  final double forgetAfter;
  Pointer<lsl_streaminfo>? _streamInfoBuffer;
  lsl_continuous_resolver? _resolver;

  /// Creates a new LSLStreamResolverContinuous object.
  ///
  /// The [forgetAfter] parameter determines how long the resolver should
  /// remember streams after they have not been seen.
  /// The [maxStreams] parameter determines the maximum number of streams
  /// to resolve, ideally, this would be the exact number of streams you expect
  /// to be available.
  LSLStreamResolverContinuous({this.forgetAfter = 5.0, this.maxStreams = 5});

  @override
  create() {
    if (created) {
      throw LSLException('Resolver already created');
    }
    _streamInfoBuffer = allocate<lsl_streaminfo>(maxStreams);
    _resolver = lsl_create_continuous_resolver(forgetAfter);
    super.create();
    return this;
  }

  /// Resolves streams available on the network.
  ///
  /// The [waitTime] parameter determines how long to wait for streams to
  /// resolve.
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
    if (destroyed) {
      return;
    }
    if (_streamInfoBuffer != null) {
      _streamInfoBuffer?.free();
      _streamInfoBuffer = null;
    }
    if (_resolver != null) {
      lsl_destroy_continuous_resolver(_resolver!);
      _resolver = null;
    }
    super.destroy();
  }

  @override
  String toString() {
    return 'LSLStreamResolverContinuous{maxStreams: $maxStreams, forgetAfter: $forgetAfter}';
  }
}
