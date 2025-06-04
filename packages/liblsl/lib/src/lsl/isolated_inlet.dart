import 'dart:async';
import 'dart:ffi';

import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
import 'package:liblsl/src/meta/todo.dart';
import 'package:liblsl/src/util/reusable_buffer.dart';
import 'package:meta/meta.dart';

/// An isolate-ready implementation of LSL inlet
class LSLIsolatedInlet<T> extends LSLObj {
  final LSLStreamInfo streamInfo;
  final int maxBufferSize;
  final int maxChunkLength;
  final bool recover;
  final LSLInletIsolateManager _isolateManager = LSLInletIsolateManager();
  final double createTimeout;
  bool _initialized = false;
  late final LslPullSample _pullFn;
  late final LSLReusableBuffer _buffer;

  /// Creates a new LSLIsolatedInlet object
  ///
  /// The [streamInfo] parameter is used to determine the type of data for the
  /// given inlet.
  ///
  /// The [maxBufferSize] parameter determines the size of the buffer to use
  /// in seconds if the stream has a sample rate, otherwise it is in 100s of
  /// samples. If 0, the default buffer size from the stream is used.
  /// The [maxChunkLength] parameter determines the maximum number of samples
  /// in a chunk, if 0, the default chunk length from the stream is used.
  /// The [recover] parameter determines whether the inlet should
  /// recover from lost samples.
  LSLIsolatedInlet(
    this.streamInfo, {
    this.maxBufferSize = 360,
    this.maxChunkLength = 0,
    this.recover = true,
    this.createTimeout = LSL_FOREVER,
  }) {
    _pullFn = LSLMapper().streamPull(streamInfo);

    // Validate type parameter matches channel format
    final expectedType = _getExpectedType();
    if (T != expectedType && T != dynamic) {
      throw LSLException(
        'Type parameter T ($T) does not match expected type for channel format ($expectedType)',
      );
    }
  }

  bool get initialized => _initialized;
  LSLInletIsolateManager get isolateManager => _isolateManager;

  Type _getExpectedType() {
    switch (streamInfo.channelFormat.dartType) {
      case const (double):
        return double;
      case const (int):
        return int;
      case const (String):
        return String;
      default:
        return dynamic;
    }
  }

  @override
  Future<LSLIsolatedInlet<T>> create() async {
    if (created) {
      throw LSLException('Inlet already created');
    }

    // Initialize the isolate manager
    await _isolateManager.init();
    _buffer = _pullFn.createReusableBuffer(streamInfo.channelCount);

    // Send message to create inlet in the isolate
    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.createInlet, {
        'streamInfo': LSLSerializer.serializeStreamInfo(streamInfo),
        'maxBufferSize': maxBufferSize,
        'maxChunkLength': maxChunkLength,
        'recover': recover,
        'timeout': createTimeout,
      }),
    );

    if (!response.success) {
      throw LSLException('Error creating inlet: ${response.error}');
    }

    _initialized = true;
    super.create();
    return this;
  }

  /// Pulls a sample from the inlet.
  ///
  /// The [timeout] parameter determines the maximum time to wait for a sample
  /// to arrive. To wait indefinitely, set [timeout] to [LSL_FOREVER].
  /// If [timeout] is 0, the function will return immediately with available
  /// samples, but there is no guarantee that it will return a sample.
  Future<LSLSample<T>> pullSample({double timeout = 0.0}) async {
    _ensureInitialized();

    // Send message to pull sample from the isolate
    // and wait for the response.
    // The buffer address is passed to the isolate for sample retrieval.
    // The buffer has to be freed on this thread after the sample is pulled.
    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.pullSample, {
        'timeout': timeout,
        'pointerAddr': _buffer.buffer.address,
        'ecPointerAddr': _buffer.ec.address,
      }),
    );

    if (!response.success) {
      throw LSLException('Error pulling sample: ${response.error}');
    }

    // Deserialize the sample pointer object.
    final samplePointer = LSLSerializer.deserializeSamplePointer(
      response.result as Map<String, dynamic>,
    );
    // a timestamp of zero means no sample was retrieved.
    if (samplePointer.timestamp == 0) {
      return LSLSample<T>([], 0, samplePointer.errorCode);
    }

    // Convert the buffer to a list of the appropriate type.
    final sampleData =
        _pullFn.bufferToList(_buffer.buffer, streamInfo.channelCount)
            as List<T>;

    // Return the sample!
    return LSLSample<T>(
      sampleData,
      samplePointer.timestamp,
      samplePointer.errorCode,
    );
  }

  /// Get time correction for the inlet.
  Future<double> getTimeCorrection(double timeout) async {
    _ensureInitialized();

    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.timeCorrection, {
        'timeout': timeout,
        'ecPointerAddr': _buffer.ec.address,
      }),
    );

    if (!response.success) {
      throw LSLException('Error getting time correction: ${response.error}');
    }

    return response.result as double;
  }

  /// Clears all samples from the inlet.
  Future<int> flush() async {
    _ensureInitialized();

    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.flush, {}),
    );

    if (!response.success) {
      throw LSLException('Error flushing inlet: ${response.error}');
    }

    return response.result as int;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw LSLException('Inlet not created');
    }
  }

  /// Gets the number of samples available in the inlet.
  /// This will either be the number of available samples (if supported by the
  /// platform) or it will be 1 if there are samples available, or 0 if there
  /// are no samples available.
  Future<int> samplesAvailable() async {
    _ensureInitialized();

    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.samplesAvailable, {}),
    );

    if (!response.success) {
      throw LSLException('Error checking samples available: ${response.error}');
    }

    return response.result as int;
  }

  @override
  void destroy() async {
    if (destroyed) {
      return;
    }

    if (_initialized) {
      try {
        await _isolateManager.sendMessage(
          LSLMessage(LSLMessageType.destroy, {}),
        );
      } catch (e) {
        // Ignore errors during cleanup
      }

      _isolateManager.dispose();
    }

    super.destroy();
  }

  @override
  String toString() {
    return 'LSLIsolatedInlet<$T>{streamInfo: $streamInfo, maxBufferSize: $maxBufferSize, maxChunkLength: $maxChunkLength, recover: $recover}';
  }
}

/// Implementation of inlet functionality for the isolate
class LSLInletIsolate extends LSLIsolateWorkerBase {
  lsl_inlet? _inlet;
  LSLStreamInfo? _streamInfo;
  late final LslPullSample _pullFn;
  late final bool _isStreamInfoOwner;

  final Map<LSLMessageType, FutureOr Function(Map<String, dynamic>)> _handlers =
      {};

  LSLInletIsolate(super.sendPort) : super() {
    _registerHandlers();
  }

  void _registerHandlers() {
    _handlers[LSLMessageType.createInlet] = _createInlet;
    _handlers[LSLMessageType.pullSample] = _pullSample;
    _handlers[LSLMessageType.flush] = _flush;
    _handlers[LSLMessageType.timeCorrection] = _timeCorrection;
    _handlers[LSLMessageType.samplesAvailable] = _samplesAvailable;
    _handlers[LSLMessageType.destroy] = _destroy;
    _handlers[LSLMessageType.pullChunk] = pullChunk;
  }

  @override
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
  external Future<dynamic> pullChunk(Map<String, dynamic> data);

  Future<bool> _createInlet(Map<String, dynamic> data) async {
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

    return true;
  }

  Future<Map<String, dynamic>> _pullSample(Map<String, dynamic> data) async {
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
    return LSLSerializer.serializeSamplePointer(sample);
  }

  Future<int> _flush(Map<String, dynamic>? data) async {
    if (_inlet == null) {
      throw LSLException('Inlet not created');
    }

    return lsl_inlet_flush(_inlet!);
  }

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
