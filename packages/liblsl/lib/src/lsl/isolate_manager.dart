import 'dart:async';
import 'dart:isolate';

import 'package:liblsl/src/lsl/isolated_inlet.dart';
import 'package:liblsl/src/lsl/isolated_outlet.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';

/// Message types for communication between isolates
enum LSLMessageType {
  createOutlet,
  createInlet,
  pushSample,
  pullSample,
  waitForConsumer,
  destroy,
  resolveStreams,
  samplesAvailable,
  flush,
}

/// A message payload for communication between isolates
class LSLMessage {
  final LSLMessageType type;
  final Map<String, dynamic> data;
  final SendPort? replyPort;

  LSLMessage(this.type, this.data, {this.replyPort});
}

/// A response message from an isolate
class LSLResponse {
  final bool success;
  final dynamic result;
  final String? error;

  LSLResponse({required this.success, this.result, this.error});

  factory LSLResponse.success(dynamic result) {
    return LSLResponse(success: true, result: result);
  }

  factory LSLResponse.error(String message) {
    return LSLResponse(success: false, error: message);
  }

  Map<String, dynamic> toMap() {
    return {'success': success, 'result': result, 'error': error};
  }

  factory LSLResponse.fromMap(Map<String, dynamic> map) {
    return LSLResponse(
      success: map['success'] as bool,
      result: map['result'],
      error: map['error'] as String?,
    );
  }
}

/// Handles serialization of complex types between isolates
class LSLSerializer {
  /// Serialize stream info to pass between isolates
  static Map<String, dynamic> serializeStreamInfo(LSLStreamInfo info) {
    return {
      'streamName': info.streamName,
      'streamType': info.streamType.value,
      'channelCount': info.channelCount,
      'sampleRate': info.sampleRate,
      'channelFormat': info.channelFormat.index,
      'sourceId': info.sourceId,
      'address': info.streamInfo?.address,
    };
  }

  /// Serialize a sample for passing between isolates
  static Map<String, dynamic> serializeSample<T>(LSLSample<T> sample) {
    return {
      'data': sample.data,
      'timestamp': sample.timestamp,
      'errorCode': sample.errorCode,
    };
  }

  /// Deserialize a sample
  static LSLSample<T> deserializeSample<T>(Map<String, dynamic> map) {
    return LSLSample<T>(
      List<T>.from(map['data'] as List),
      map['timestamp'] as double,
      map['errorCode'] as int,
    );
  }
}

/// Manages communication with outlet isolates
class LSLOutletIsolateManager {
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _sendPort;
  final Completer<void> _initialization = Completer<void>();
  Isolate? _isolate;

  LSLOutletIsolateManager() {
    _listen();
  }

  void _listen() {
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!_initialization.isCompleted) {
          _initialization.complete();
        }
      } else if (message is Map<String, dynamic>) {
        // Handle response from isolate if needed in the future
      }
    });
  }

  /// Initialize the isolate
  Future<void> init() async {
    // Create the isolate that will run LSLOutletIsolate
    _isolate = await Isolate.spawn(
      _outletIsolateEntryPoint,
      _receivePort.sendPort,
    );

    return _initialization.future;
  }

  /// Entry point for the outlet isolate
  static void _outletIsolateEntryPoint(SendPort mainSendPort) {
    // Create the LSLOutletIsolate instance to handle LSL operations
    // This is where we create the actual LSLOutletIsolate class
    LSLOutletIsolate(mainSendPort);
  }

  /// Send a message to the isolate
  Future<LSLResponse> sendMessage(LSLMessage message) async {
    if (!_initialization.isCompleted) {
      await init();
    }

    if (_sendPort == null) {
      throw StateError('Isolate communication not established');
    }

    final completer = Completer<LSLResponse>();
    final replyPort = ReceivePort();
    replyPort.listen((response) {
      replyPort.close();
      if (response is Map<String, dynamic>) {
        completer.complete(LSLResponse.fromMap(response));
      } else {
        completer.completeError('Invalid response format');
      }
    });
    _sendPort!.send({
      'type': message.type.index,
      'data': message.data,
      'replyPort': replyPort.sendPort,
    });
    return completer.future;
  }

  /// Clean up resources
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
  }
}

/// Manages communication with inlet isolates
class LSLInletIsolateManager {
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _sendPort;
  final Completer<void> _initialization = Completer<void>();
  Isolate? _isolate;

  LSLInletIsolateManager() {
    _listen();
  }

  void _listen() {
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!_initialization.isCompleted) {
          _initialization.complete();
        }
      } else if (message is Map<String, dynamic>) {
        // Handle response from isolate if needed in the future
      }
    });
  }

  /// Initialize the isolate
  Future<void> init() async {
    // Create the isolate that will run LSLInletIsolate
    _isolate = await Isolate.spawn(
      _inletIsolateEntryPoint,
      _receivePort.sendPort,
    );

    return _initialization.future;
  }

  /// Entry point for the inlet isolate
  static void _inletIsolateEntryPoint(SendPort mainSendPort) {
    // Create the LSLInletIsolate instance to handle LSL operations
    // This is where we create the actual LSLInletIsolate class
    LSLInletIsolate(mainSendPort);
  }

  /// Send a message to the isolate
  Future<LSLResponse> sendMessage(LSLMessage message) async {
    if (!_initialization.isCompleted) {
      await init();
    }

    if (_sendPort == null) {
      throw StateError('Isolate communication not established');
    }

    final completer = Completer<LSLResponse>();
    final replyPort = ReceivePort();

    replyPort.listen((response) {
      replyPort.close();
      if (response is Map<String, dynamic>) {
        completer.complete(LSLResponse.fromMap(response));
      } else {
        completer.completeError('Invalid response format');
      }
    });

    _sendPort!.send({
      'type': message.type.index,
      'data': message.data,
      'replyPort': replyPort.sendPort,
    });

    return completer.future;
  }

  /// Clean up resources
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
  }
}
