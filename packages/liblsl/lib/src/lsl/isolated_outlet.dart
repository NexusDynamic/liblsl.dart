import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart' show Utf8, StringUtf8Pointer;
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/push_sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';

/// An isolate-ready implementation of LSL outlet
class LSLIsolatedOutlet extends LSLObj {
  final LSLStreamInfo streamInfo;
  final int chunkSize;
  final int maxBuffer;
  final LSLOutletIsolateManager _isolateManager = LSLOutletIsolateManager();
  bool _initialized = false;

  /// Creates a new LSLIsolatedOutlet object
  ///
  /// The [streamInfo] parameter is used to determine the type of data for the
  /// given outlet and other LSL parameters.
  /// The [chunkSize] parameter (in samples) determines how to hand off samples
  /// to the buffer, 0 creates a chunk for each push.
  /// The [maxBuffer] parameter determines the size of the buffer that
  /// stores incoming samples. This is in seconds if the stream has
  /// a sample rate, otherwise it is in 100s of samples (maxBuffer * 10^2).
  LSLIsolatedOutlet({
    required this.streamInfo,
    this.chunkSize = 0,
    this.maxBuffer = 360,
  }) {
    if (streamInfo.streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
  }

  @override
  create() async {
    if (created) {
      throw LSLException('Outlet already created');
    }
    // Initialize the isolate manager
    await _isolateManager.init();

    // Send message to create outlet in the isolate
    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.createOutlet, {
        'streamInfo': LSLSerializer.serializeStreamInfo(streamInfo),
        'chunkSize': chunkSize,
        'maxBuffer': maxBuffer,
      }),
    );
    if (!response.success) {
      throw LSLException('Error creating outlet: ${response.error}');
    }

    _initialized = true;
    super.create();
    return this;
  }

  /// Waits for a consumer (e.g. LabRecorder, another inlet) to connect to the
  /// outlet.
  ///
  /// The [timeout] parameter determines the maximum time to wait for a
  /// consumer to connect.
  ///
  /// If [exception] is true, an exception will be thrown if no consumer is
  /// found within the timeout period.
  Future<void> waitForConsumer({
    double timeout = 60,
    bool exception = true,
  }) async {
    if (!_initialized) {
      throw LSLException('Outlet not created');
    }

    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.waitForConsumer, {'timeout': timeout}),
    );

    if (!response.success) {
      if (exception) {
        throw LSLTimeout('No consumer found within $timeout seconds');
      }
    }
  }

  /// Pushes a sample to the outlet.
  ///
  /// The [data] parameter is a list of values that will be used to
  /// initialize the sample. The type should match the channel format.
  Future<int> pushSample(List<dynamic> data) async {
    if (!_initialized) {
      throw LSLException('Outlet not created');
    }

    if (data.length != streamInfo.channelCount) {
      throw LSLException(
        'Data length (${data.length}) does not match channel count (${streamInfo.channelCount})',
      );
    }

    final response = await _isolateManager.sendMessage(
      LSLMessage(LSLMessageType.pushSample, {'data': data}),
    );

    if (!response.success) {
      throw LSLException('Error pushing sample: ${response.error}');
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
    return 'LSLIsolatedOutlet{streamInfo: $streamInfo, chunkSize: $chunkSize, maxBuffer: $maxBuffer}';
  }
}

/// Implementation of outlet functionality for the isolate
class LSLOutletIsolate {
  final ReceivePort _receivePort = ReceivePort();
  final SendPort _sendPort;
  lsl_outlet? _outlet;
  LSLStreamInfo? _streamInfo;
  late final LslPushSample _pushFn;
  late final bool _isStreamInfoOwner;

  LSLOutletIsolate(this._sendPort) {
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
        case LSLMessageType.createOutlet:
          final result = await _createOutlet(data);
          replyPort.send(LSLResponse.success(result).toMap());
          break;
        case LSLMessageType.waitForConsumer:
          final result = await _waitForConsumer(data);
          replyPort.send(LSLResponse.success(result).toMap());
          break;
        case LSLMessageType.pushSample:
          final result = await _pushSample(data);
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
    _outlet = lsl_create_outlet(
      _streamInfo!.streamInfo!,
      data['chunkSize'] as int,
      data['maxBuffer'] as int,
    );

    if (_outlet == null) {
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

    final sampleData = data['data'] as List<dynamic>;

    if (sampleData.length != _streamInfo!.channelCount) {
      throw LSLException(
        'Data length (${sampleData.length}) does not match channel count (${_streamInfo!.channelCount})',
      );
    }

    // Allocate memory for the sample
    final samplePtr = _allocSample(sampleData);

    try {
      // Push the sample
      final int result = _pushFn(_outlet!, samplePtr);
      if (LSLObj.error(result)) {
        throw LSLException('Error pushing sample: $result');
      }
      return result;
    } finally {
      samplePtr.free();
    }
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

    _receivePort.close();
  }

  /// Allocates a sample of the appropriate type for the given data.
  Pointer _allocSample(List<dynamic> data) {
    if (_streamInfo == null) {
      throw LSLException('Stream info not available');
    }

    switch (_streamInfo!.channelFormat.ffiType) {
      case const (Float):
        final ptr = allocate<Float>(_streamInfo!.channelCount);
        for (var i = 0; i < _streamInfo!.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Double):
        final ptr = allocate<Double>(_streamInfo!.channelCount);
        for (var i = 0; i < _streamInfo!.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int8):
        final ptr = allocate<Int8>(_streamInfo!.channelCount);
        for (var i = 0; i < _streamInfo!.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int16):
        final ptr = allocate<Int16>(_streamInfo!.channelCount);
        for (var i = 0; i < _streamInfo!.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int32):
        final ptr = allocate<Int32>(_streamInfo!.channelCount);
        for (var i = 0; i < _streamInfo!.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Int64):
        final ptr = allocate<Int64>(_streamInfo!.channelCount);
        for (var i = 0; i < _streamInfo!.channelCount; i++) {
          ptr[i] = data[i];
        }
        return ptr;
      case const (Pointer<Char>):
        if (data.every((item) => item is String)) {
          // For string data
          final stringArray = allocate<Pointer<Char>>(
            _streamInfo!.channelCount,
          );
          for (var i = 0; i < _streamInfo!.channelCount; i++) {
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
}
