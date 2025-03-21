import 'dart:ffi';
import 'package:liblsl/liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';

// import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;
/// @note The inlet makes a copy of the info object at its construction.
class LSLStreamInlet<T> extends LSLObj {
  lsl_inlet? _streamInlet;
  late final LSLStreamInfo streamInfo;
  int maxBufferSize;
  int maxChunkLength;
  bool recover;
  late final LslPullSample _pullFn;

  LSLStreamInlet(
    this.streamInfo, {
    this.maxBufferSize = 0,
    this.maxChunkLength = 0,
    this.recover = true,
  }) {
    if (streamInfo.streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _pullFn = LSLMapper().streamPull(streamInfo);
  }

  @override
  create() {
    if (created) {
      throw LSLException('Inlet already created');
    }
    _streamInlet = lsl_create_inlet(
      streamInfo.streamInfo!,
      maxBufferSize,
      maxChunkLength,
      recover as int,
    );
    if (_streamInlet == null) {
      throw LSLException('Error creating inlet');
    }
    super.create();
    return this;
  }

  /// Pull a sample from the inlet
  Future<LSLSample<T>> pullSample({
    double timeout = 0.0,
    int bufferSize = 0,
  }) async {
    if (_streamInlet == null) {
      throw LSLException('Inlet not created');
    }
    final ec = allocate<Int32>();
    final samplePtr = allocate<Pointer>(streamInfo.channelCount);
    final LSLSample sample = _pullFn(
      _streamInlet!,
      samplePtr,
      bufferSize,
      timeout,
      ec,
    );
    return sample as LSLSample<T>;
  }

  @override
  void destroy() {
    if (destroyed) {
      return;
    }
    if (_streamInlet != null) {
      lsl_destroy_inlet(_streamInlet!);
    }
    streamInfo.destroy();
    super.destroy();
  }
}
