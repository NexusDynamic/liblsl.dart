import 'dart:async';
import 'dart:ffi';

import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
import 'package:liblsl/src/meta/todo.dart';
import 'package:meta/meta.dart';

/// Implementation of inlet functionality for the isolate
class LSLInletIsolate extends LSLIsolateWorkerBase {
  lsl_inlet? _inlet;
  LSLStreamInfo? _streamInfo;
  late final LslPullSample _pullFn;
  late final bool _isStreamInfoOwner;

  final Map<LSLMessageType, FutureOr Function(Map<String, dynamic>)> _handlers =
      {};

  /// Creates a new instance of [LSLInletIsolate].
  /// The [sendPort] is used for communication with the main isolate.
  /// This constructor registers the handlers for the isolate messages.
  LSLInletIsolate(super.sendPort) : super() {
    _registerHandlers();
  }

  /// Sets the handlers for the isolate messages.
  void _registerHandlers() {
    _handlers[LSLMessageType.createInlet] = _createInlet;
    _handlers[LSLMessageType.pullSample] = _pullSample;
    _handlers[LSLMessageType.flush] = _flush;
    _handlers[LSLMessageType.timeCorrection] = _timeCorrection;
    _handlers[LSLMessageType.samplesAvailable] = _samplesAvailable;
    _handlers[LSLMessageType.destroy] = _destroy;
    _handlers[LSLMessageType.pullChunk] = pullChunk;
    _handlers[LSLMessageType.getFullInfo] = (data) async {
      if (_inlet == null) {
        throw LSLException('Inlet not created');
      }
      final timeout = data['timeout'] as double;
      final ec = allocate<Int32>();
      final fullInfoPtr = lsl_get_fullinfo(_inlet!, timeout, ec);
      final result = ec.value;
      ec.free();
      if (result != 0) {
        throw LSLException('Error getting full info: $result');
      }
      return fullInfoPtr.address;
    };
  }

  @override
  /// Handles incoming messages from the main isolate.
  /// This method processes the message based on its type and returns the result.
  /// If the message type is not supported, it throws an [LSLException].
  Future<dynamic> handleMessage(LSLMessage message) async {
    final type = message.type;
    final data = message.data;

    if (_handlers.containsKey(type)) {
      return await _handlers[type]!(data);
    } else {
      throw LSLException('Unsupported message type: $type');
    }
  }

  @protected
  /// Not yet implemented.
  external Future<dynamic> pullChunk(Map<String, dynamic> data);

  /// Creates an inlet for the specified stream info.
  /// The [data] parameter contains the necessary information to create the
  /// inlet, such as stream info, max buffer size, max chunk length, and whether
  /// to recover from lost samples.
  Future<Map<String, dynamic>> _createInlet(Map<String, dynamic> data) async {
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

    // Set up the pull function
    _pullFn = LSLMapper().streamPull(_streamInfo!);

    // Create the inlet
    _inlet = lsl_create_inlet(
      _streamInfo!.streamInfo,
      data['maxBufferSize'] as int,
      data['maxChunkLength'] as int,
      data['recover'] as bool ? 1 : 0,
    );

    if (_inlet == null) {
      throw LSLException('Error creating inlet');
    }

    // open the stream
    final Pointer<Int32> ec = allocate<Int32>();
    final timeout = data['timeout'] as double;
    lsl_open_stream(_inlet!, timeout, ec);
    final result = ec.value;
    ec.free();

    if (result != 0) {
      throw LSLException('Error opening stream: $result');
    }

    return {
      'inletAddress': _inlet!.address,
      'streamInfoAddress': _streamInfo!.streamInfo.address,
    };
  }

  /// Pulls a sample from the inlet.
  Future<LSLSamplePointer> _pullSample(Map<String, dynamic> data) async {
    if (_inlet == null || _streamInfo == null) {
      throw LSLException('Inlet not created');
    }

    final timeout = data['timeout'] as double;
    final samplePtr = Pointer.fromAddress(data['pointerAddr'] as int);
    final ecPtr = Pointer<Int32>.fromAddress(data['ecPointerAddr'] as int);
    // Pull the sample
    final sample = await _pullFn.pullSampleInto(
      samplePtr,
      _inlet!,
      _streamInfo!.channelCount,
      timeout,
      ecPtr,
    );

    // Return the serialized sample
    return sample;
  }

  /// Flushes the inlet, clearing any buffered samples.
  Future<int> _flush(Map<String, dynamic>? data) async {
    if (_inlet == null) {
      throw LSLException('Inlet not created');
    }

    return lsl_inlet_flush(_inlet!);
  }

  /// Returns the number of samples available in the inlet.
  Future<int> _samplesAvailable(Map<String, dynamic>? data) async {
    if (_inlet == null) {
      throw LSLException('Inlet not created');
    }

    return lsl_samples_available(_inlet!);
  }

  @Todo('zeyus', 'handle timeout code')
  /// Time correction
  Future<double> _timeCorrection(Map<String, dynamic> data) async {
    final timeout = data['timeout'] as double;
    final ecPtr = Pointer<Int32>.fromAddress(data['ecPointerAddr'] as int);
    final timeCorrection = lsl_time_correction(_inlet!, timeout, ecPtr);
    final result = ecPtr.value;
    if (result != 0) {
      throw LSLException('Error getting time correction: $result');
    }
    return timeCorrection;
  }

  /// Cleans up the inlet and stream info.
  Future<void> _destroy(Map<String, dynamic>? data) async {
    if (_inlet != null) {
      lsl_close_stream(_inlet!);
      lsl_destroy_inlet(_inlet!);
      _inlet = null;
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
