import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

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

/// An isolate-ready implementation of LSL inlet
class LSLIsolatedInlet<T> extends LSLObj {
  final LSLStreamInfo streamInfo;
  final int maxBufferSize;
  final int maxChunkLength;
  final bool recover;
  final LSLInletIsolateManager _isolateManager = LSLInletIsolateManager();
  final double createTimeout;
  bool _initialized = false;

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
    if (streamInfo.streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }

    // Validate type parameter matches channel format
    final expectedType = _getExpectedType();
    if (T != expectedType && T != dynamic) {
      throw LSLException(
        'Type parameter T ($T) does not match expected type for channel format ($expectedType)',
      );
    }
  }

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
  create() async {
    if (created) {
      throw LSLException('Inlet already created');
    }

    // Initialize the isolate manager
    await _isolateManager.init();

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
    if (!_initialized) {
      throw LSLException('Inlet not created');
    }

    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.pullSample, {'timeout': timeout}),
    );

    if (!response.success) {
      throw LSLException('Error pulling sample: ${response.error}');
    }

    // Deserialize the sample
    final sampleData = response.result as Map<String, dynamic>;
    return LSLSerializer.deserializeSample<T>(sampleData);
  }

  /// Clears all samples from the inlet.
  Future<int> flush() async {
    if (!_initialized) {
      throw LSLException('Inlet not created');
    }

    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.flush, {}),
    );

    if (!response.success) {
      throw LSLException('Error flushing inlet: ${response.error}');
    }

    return response.result as int;
  }

  /// Gets the number of samples available in the inlet.
  /// This will either be the number of available samples (if supported by the
  /// platform) or it will be 1 if there are samples available, or 0 if there
  /// are no samples available.
  Future<int> samplesAvailable() async {
    if (!_initialized) {
      throw LSLException('Inlet not created');
    }

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
class LSLInletIsolate {
  final ReceivePort _receivePort = ReceivePort();
  final SendPort _sendPort;
  lsl_inlet? _inlet;
  LSLStreamInfo? _streamInfo;
  late final LslPullSample _pullFn;
  late final bool _isStreamInfoOwner;

  LSLInletIsolate(this._sendPort) {
    _listen();
    _sendPort.send(_receivePort.sendPort);
  }

  void _listen() {
    _receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        _handleMessage(message);
      }
    });
  }

  void _handleMessage(Map<String, dynamic> message) async {
    final type = LSLMessageType.values[message['type'] as int];
    final data = message['data'] as Map<String, dynamic>;
    final SendPort replyPort = message['replyPort'] as SendPort;

    try {
      switch (type) {
        case LSLMessageType.createInlet:
          final result = await _createInlet(data);
          replyPort.send(LSLResponse.success(result).toMap());
          break;
        case LSLMessageType.pullSample:
          final result = await _pullSample(data);
          replyPort.send(LSLResponse.success(result).toMap());
          break;
        case LSLMessageType.flush:
          final result = await _flush();
          replyPort.send(LSLResponse.success(result).toMap());
          break;
        case LSLMessageType.samplesAvailable:
          final result = await _samplesAvailable();
          replyPort.send(LSLResponse.success(result).toMap());
          break;
        case LSLMessageType.destroy:
          _destroy();
          replyPort.send(LSLResponse.success(null).toMap());
          break;
        default:
          replyPort.send(
            LSLResponse.error('Unsupported message type: $type').toMap(),
          );
      }
    } catch (e) {
      replyPort.send(LSLResponse.error(e.toString()).toMap());
    }
  }

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
      _streamInfo!.streamInfo!,
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

    // Pull the sample
    final sample = _pullFn(_inlet!, _streamInfo!.channelCount, timeout);

    // Return the serialized sample
    return LSLSerializer.serializeSample(sample);
  }

  Future<int> _flush() async {
    if (_inlet == null) {
      throw LSLException('Inlet not created');
    }

    return lsl_inlet_flush(_inlet!);
  }

  Future<int> _samplesAvailable() async {
    if (_inlet == null) {
      throw LSLException('Inlet not created');
    }

    return lsl_samples_available(_inlet!);
  }

  void _destroy() {
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

    _receivePort.close();
  }
}
