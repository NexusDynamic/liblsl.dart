import 'dart:async';
import 'dart:ffi';

import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/bindings_ex.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/push_chunk.dart';
import 'package:liblsl/src/lsl/push_sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
import 'package:liblsl/src/meta/todo.dart';

/// Implementation of outlet functionality for the isolate
class LSLOutletIsolate extends LSLIsolateWorkerBase {
  lsl_outlet? _outlet;
  LSLStreamInfo? _streamInfo;
  late final LSLPushSample _pushFn;
  late final bool _isStreamInfoOwner;

  /// Resolved lazily: string streams have no chunk push and must still be
  /// able to create outlets.
  LSLPushChunk? _pushChunkFn;

  /// Creates a new outlet isolate worker
  /// The [sendPort] is used to communicate with the main isolate.
  LSLOutletIsolate(super.sendPort) : super();

  @override
  Future<dynamic> handleMessage(LSLMessage message) async {
    final type = message.type;
    final data = message.data;

    switch (type) {
      case LSLMessageType.createOutlet:
        return await _createOutlet(data);
      case LSLMessageType.waitForConsumer:
        return await _waitForConsumer(data);
      case LSLMessageType.pushSample:
        return await _pushSample(data);
      case LSLMessageType.pushChunk:
        return await _pushChunk(data);
      case LSLMessageType.destroy:
        _destroy();
        return null;
      default:
        throw LSLException('Unsupported message type: $type');
    }
  }

  @Todo('zeyus', 'Fix custom LSLContentType')
  Future<bool> _createOutlet(Map<String, dynamic> data) async {
    // Deserialize stream info
    final streamInfoData = data['streamInfo'] as Map<String, dynamic>;

    if (streamInfoData.containsKey('address') &&
        streamInfoData['address'] != null) {
      _isStreamInfoOwner = false;
      // Use existing stream info
      _streamInfo = LSLStreamInfo.fromStreamInfoAddr(
        streamInfoData['address'] as int,
      );
    } else {
      _isStreamInfoOwner = true;
      // Create new stream info
      _streamInfo = LSLStreamInfo(
        streamName: streamInfoData['streamName'] as String,
        //
        streamType: LSLContentType.values.firstWhere(
          (t) => t.value == streamInfoData['streamType'],
        ),
        channelCount: streamInfoData['channelCount'] as int,
        sampleRate: streamInfoData['sampleRate'] as double,
        channelFormat:
            LSLChannelFormat.values[streamInfoData['channelFormat'] as int],
        sourceId: streamInfoData['sourceId'] as String,
      );
      _streamInfo!.create();
    }

    // Set up the push function
    _pushFn = LSLMapper().streamPush(_streamInfo!);

    // Create the outlet
    final transportFlags = data['transportFlags'] as int? ?? 0;
    _outlet = transportFlags == 0
        ? lsl_create_outlet(
            _streamInfo!.streamInfo,
            data['chunkSize'] as int,
            data['maxBuffer'] as int,
          )
        : lslCreateOutletFlags(
            _streamInfo!.streamInfo,
            data['chunkSize'] as int,
            data['maxBuffer'] as int,
            transportFlags,
          );

    if (_outlet == null || _outlet!.isNullPointer) {
      throw LSLException('Error creating outlet');
    }

    return true;
  }

  Future<bool> _waitForConsumer(Map<String, dynamic> data) async {
    if (_outlet == null) {
      throw LSLException('Outlet not created');
    }

    final timeout = data['timeout'] as double;
    final int result = lsl_wait_for_consumers(_outlet!, timeout);

    if (result == 0) {
      throw LSLTimeout('No consumer found within $timeout seconds');
    }

    return true;
  }

  Future<int> _pushSample(Map<String, dynamic> data) async {
    if (_outlet == null || _streamInfo == null) {
      throw LSLException('Outlet not created');
    }
    // Allocate memory for the sample
    final samplePtr = Pointer.fromAddress(data['pointerAddr'] as int);

    // Push the sample
    final int result = _pushFn(_outlet!, samplePtr);
    if (LSLObj.error(result)) {
      throw LSLException('Error pushing sample: $result');
    }
    return result;
  }

  /// Pushes a chunk from the main isolate's shared native buffer.
  ///
  /// The main isolate owns the buffer and awaits this response before
  /// touching it again, so reading it here is race-free.
  Future<int> _pushChunk(Map<String, dynamic> data) async {
    if (_outlet == null || _streamInfo == null) {
      throw LSLException('Outlet not created');
    }
    final pushChunkFn = _pushChunkFn ??= LSLMapper().streamPushChunk(
      _streamInfo!,
    );
    final dataPtr = Pointer<NativeType>.fromAddress(data['pointerAddr'] as int);
    final elements = data['dataElements'] as int;
    final tsAddr = data['tsPointerAddr'] as int?;

    final int result;
    if (tsAddr != null) {
      result = pushChunkFn.pushWithTimestamps(
        _outlet!,
        dataPtr,
        elements,
        Pointer<Double>.fromAddress(tsAddr),
      );
    } else {
      result = pushChunkFn.pushWithTimestamp(
        _outlet!,
        dataPtr,
        elements,
        data['timestamp'] as double,
      );
    }
    if (LSLObj.error(result)) {
      throw LSLException('Error pushing chunk: $result');
    }
    return result;
  }

  void _destroy() {
    if (_outlet != null) {
      lsl_destroy_outlet(_outlet!);
      _outlet = null;
    }

    if (_streamInfo != null) {
      if (_isStreamInfoOwner) {
        _streamInfo!.destroy();
      }
      _streamInfo = null;
    }

    cleanup();
  }
}
