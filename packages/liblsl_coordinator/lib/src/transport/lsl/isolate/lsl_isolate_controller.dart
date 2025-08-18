import 'dart:async';
import 'dart:isolate';
import '../config/lsl_stream_config.dart';
import '../../../utils/logging.dart';

/// Controller for managing LSL operations in isolates
/// Extracts the proven patterns from high-frequency transport
class LSLIsolateController {
  final String controllerId;
  final LSLPollingConfig pollingConfig;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  final StreamController<IsolateMessage> _messageController =
      StreamController<IsolateMessage>.broadcast();

  bool _isActive = false;
  final Completer<void> _readyCompleter = Completer<void>();

  LSLIsolateController({
    required this.controllerId,
    required this.pollingConfig,
  });

  /// Whether the isolate is currently active
  bool get isActive => _isActive;

  /// Wait for isolate to be ready for operations
  Future<void> get ready => _readyCompleter.future;

  /// Stream of messages from the isolate
  Stream<IsolateMessage> get messages => _messageController.stream;

  /// Get the send port for responses (used for command responses)
  SendPort? get responseSendPort => _receivePort?.sendPort;

  /// Start the isolate with the given entry point
  Future<void> start<T>(void Function(T) entryPoint, T params) async {
    if (_isActive) {
      throw LSLIsolateException(
        'Isolate controller $controllerId is already active',
      );
    }

    try {
      _receivePort = ReceivePort();

      // Listen for messages from isolate
      _receivePort!.listen((message) {
        print(
          'DEBUG CONTROLLER: Received message from isolate: ${message.runtimeType}',
        );
        if (message is SendPort) {
          print('DEBUG CONTROLLER: Received SendPort, setting ready');
          _sendPort = message;
          if (!_readyCompleter.isCompleted) {
            _readyCompleter.complete();
            print('DEBUG CONTROLLER: Ready completer completed');
          } else {
            print('DEBUG CONTROLLER: Ready completer already completed');
          }
        } else if (message is IsolateMessage) {
          print('DEBUG CONTROLLER: Received IsolateMessage: ${message.type}');
          _messageController.add(message);
        } else if (message is LogRecord) {
          print('DEBUG CONTROLLER: Received LogRecord');
          // Forward directly to the existing logging system
          Log.logIsolateMessage(message);
        } else {
          print(
            'DEBUG CONTROLLER: Received unknown message type: ${message.runtimeType}',
          );
        }
      });

      // Update params with correct SendPort for both inlet and outlet isolates
      if (params is LSLOutletIsolateParams) {
        params =
            LSLOutletIsolateParams(
                  streamConfig: params.streamConfig,
                  nodeId: params.nodeId,
                  sendPort: _receivePort!.sendPort,
                )
                as T;
      } else if (params is LSLInletIsolateParams) {
        params =
            LSLInletIsolateParams(
                  nodeId: params.nodeId,
                  config: params.config,
                  sendPort: _receivePort!.sendPort,
                  receiveOwnMessages: params.receiveOwnMessages,
                )
                as T;
      }

      // Spawn the isolate
      _isolate = await Isolate.spawn(entryPoint, params);
      _isActive = true;
    } catch (e) {
      await _cleanup();
      throw LSLIsolateException('Failed to start isolate $controllerId: $e');
    }
  }

  /// Send a message to the isolate
  Future<void> sendMessage(IsolateMessage message) async {
    if (!_isActive || _sendPort == null) {
      throw LSLIsolateException(
        'Isolate controller $controllerId is not active',
      );
    }

    _sendPort!.send(message);
  }

  /// Send a command to the isolate
  Future<void> sendCommand(
    IsolateCommand command, [
    Map<String, dynamic>? data,
  ]) async {
    await sendMessage(
      IsolateMessage(
        type: IsolateMessageType.command,
        data: {'command': command.name, ...?data},
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  /// Stop the isolate and cleanup resources
  Future<void> stop() async {
    if (!_isActive) return;

    try {
      // Send stop command if possible
      if (_sendPort != null) {
        await sendCommand(IsolateCommand.stop);
        // Give isolate time to clean up
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      // Ignore errors during graceful shutdown
    }

    await _cleanup();
  }

  Future<void> _cleanup() async {
    _isActive = false;

    // Kill isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    // Close ports
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;

    await _messageController.close();
  }
}

/// Parameters for LSL inlet isolate operations
class LSLInletIsolateParams {
  final String nodeId;
  final LSLPollingConfig config;
  final SendPort? sendPort;
  final bool receiveOwnMessages;

  const LSLInletIsolateParams({
    required this.nodeId,
    required this.config,
    this.sendPort,
    required this.receiveOwnMessages,
  });
}

/// Parameters for LSL outlet isolate operations
class LSLOutletIsolateParams {
  final LSLStreamConfig streamConfig;
  final String nodeId;
  final SendPort? sendPort;

  const LSLOutletIsolateParams({
    required this.streamConfig,
    required this.nodeId,
    this.sendPort,
  });
}

/// Types of messages that can be sent between isolates
enum IsolateMessageType { command, data, error, metrics, config, response }

/// Commands that can be sent to isolates
enum IsolateCommand {
  start,
  stop,
  pause,
  resume,
  updateConfig,
  sendData,
  addInlets,
  removeInlet,
  addOutlet,
  removeOutlet,
  waitForConsumer,
  hasConsumers,
}

/// Message structure for isolate communication
class IsolateMessage {
  final IsolateMessageType type;
  final Map<String, dynamic> data;
  final int timestamp;

  const IsolateMessage({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  factory IsolateMessage.command(
    IsolateCommand command, [
    Map<String, dynamic>? data,
  ]) {
    return IsolateMessage(
      type: IsolateMessageType.command,
      data: {'command': command.name, ...?data},
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
  }

  factory IsolateMessage.data(Map<String, dynamic> data) {
    return IsolateMessage(
      type: IsolateMessageType.data,
      data: data,
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
  }

  factory IsolateMessage.error(String error, [Object? cause]) {
    return IsolateMessage(
      type: IsolateMessageType.error,
      data: {'error': error, 'cause': cause?.toString()},
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
  }

  factory IsolateMessage.metrics(Map<String, dynamic> metrics) {
    return IsolateMessage(
      type: IsolateMessageType.metrics,
      data: metrics,
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
  }

  factory IsolateMessage.response(Map<String, dynamic> data) {
    return IsolateMessage(
      type: IsolateMessageType.response,
      data: data,
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
  }
}

/// Exception for isolate operations
class LSLIsolateException implements Exception {
  final String message;

  const LSLIsolateException(this.message);

  @override
  String toString() => 'LSLIsolateException: $message';
}

/// Metrics for isolate performance monitoring
class IsolateMetrics {
  final int samplesProcessed;
  final int droppedSamples;
  final double actualFrequency;
  final double targetFrequency;
  final int messagesReceived;
  final DateTime lastUpdate;

  const IsolateMetrics({
    required this.samplesProcessed,
    required this.droppedSamples,
    required this.actualFrequency,
    required this.targetFrequency,
    required this.messagesReceived,
    required this.lastUpdate,
  });

  double get dropRate =>
      samplesProcessed > 0 ? droppedSamples / samplesProcessed : 0.0;
  double get frequencyAccuracy =>
      targetFrequency > 0 ? actualFrequency / targetFrequency : 0.0;

  factory IsolateMetrics.fromMap(Map<String, dynamic> map) {
    return IsolateMetrics(
      samplesProcessed: map['samplesProcessed'] ?? 0,
      droppedSamples: map['droppedSamples'] ?? 0,
      actualFrequency: (map['actualFrequency'] ?? 0.0).toDouble(),
      targetFrequency: (map['targetFrequency'] ?? 0.0).toDouble(),
      messagesReceived: map['messagesReceived'] ?? 0,
      lastUpdate: DateTime.fromMicrosecondsSinceEpoch(
        map['timestamp'] ?? DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'samplesProcessed': samplesProcessed,
      'droppedSamples': droppedSamples,
      'actualFrequency': actualFrequency,
      'targetFrequency': targetFrequency,
      'messagesReceived': messagesReceived,
      'timestamp': lastUpdate.microsecondsSinceEpoch,
    };
  }
}
