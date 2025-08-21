import 'dart:async';
import 'dart:isolate';
import '../config/lsl_stream_config.dart';
import '../../../utils/logging.dart';
import '../../../utils/stream_controller_extensions.dart';

/// Isolate layer type - ensures coordination/data separation
enum IsolateLayerType {
  coordination,
  data,
  testing,
}

/// Controller for managing LSL operations in isolates
/// Extracts the proven patterns from high-frequency transport
class LSLIsolateController {
  final String controllerId;
  final LSLPollingConfig pollingConfig;
  final IsolateLayerType layerType;
  
  // Static registry to enforce coordination/data isolation
  static final Map<String, IsolateLayerType> _activeIsolates = {};
  static final Map<IsolateLayerType, Set<String>> _isolatesByLayer = {
    IsolateLayerType.coordination: <String>{},
    IsolateLayerType.data: <String>{},
    IsolateLayerType.testing: <String>{},
  };

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  final StreamController<IsolateMessage> _messageController =
      StreamController<IsolateMessage>.broadcast();
  final StreamController<IsolateError> _errorController =
      StreamController<IsolateError>.broadcast();

  bool _isActive = false;
  bool _hasErrors = false;
  int _restartCount = 0;
  final Completer<void> _readyCompleter = Completer<void>();
  final List<IsolateError> _recentErrors = [];
  static const int _maxErrorHistory = 10;
  static const int _maxRestartAttempts = 3;

  LSLIsolateController({
    required this.controllerId,
    required this.pollingConfig,
    IsolateLayerType? layerType,
  }) : layerType = layerType ?? _inferLayerType(pollingConfig);
  
  /// Infer layer type from polling config if not explicitly specified
  static IsolateLayerType _inferLayerType(LSLPollingConfig config) {
    // Check if it's a testing config (no isolate)
    if (!config.usePollingIsolate) {
      return IsolateLayerType.testing;
    }
    
    // Check coordination frequency range (typically 10-50 Hz)
    if (config.targetIntervalMicroseconds >= 20000) { // <= 50 Hz
      return IsolateLayerType.coordination;
    }
    
    // Everything else is data
    return IsolateLayerType.data;
  }

  /// Whether the isolate is currently active
  bool get isActive => _isActive;

  /// Wait for isolate to be ready for operations
  Future<void> get ready => _readyCompleter.future;

  /// Stream of messages from the isolate
  Stream<IsolateMessage> get messages => _messageController.stream;

  /// Stream of isolate errors
  Stream<IsolateError> get errors => _errorController.stream;

  /// Whether the isolate has encountered errors
  bool get hasErrors => _hasErrors;

  /// Number of restart attempts
  int get restartCount => _restartCount;

  /// Recent error history
  List<IsolateError> get recentErrors => List.unmodifiable(_recentErrors);

  /// Get the send port for responses (used for command responses)
  SendPort? get responseSendPort => _receivePort?.sendPort;

  /// Get all active isolates by layer type
  static Map<IsolateLayerType, Set<String>> get activeIsolatesByLayer => 
      Map.unmodifiable(_isolatesByLayer);
  
  /// Check if coordination and data isolates are properly separated
  static bool get isProperlyIsolated {
    final coordIsolates = _isolatesByLayer[IsolateLayerType.coordination]!;
    final dataIsolates = _isolatesByLayer[IsolateLayerType.data]!;
    
    // They should never overlap
    return coordIsolates.intersection(dataIsolates).isEmpty;
  }

  /// Start the isolate with the given entry point
  Future<void> start<T>(void Function(T) entryPoint, T params) async {
    if (_isActive) {
      throw LSLIsolateException(
        'Isolate controller $controllerId is already active',
      );
    }
    
    // Register this isolate in the separation registry
    _activeIsolates[controllerId] = layerType;
    _isolatesByLayer[layerType]!.add(controllerId);
    
    // Validate separation is maintained
    if (!isProperlyIsolated) {
      _activeIsolates.remove(controllerId);
      _isolatesByLayer[layerType]!.remove(controllerId);
      throw LSLIsolateException(
        'Isolate separation violation: coordination and data isolates cannot be shared. '
        'Controller $controllerId (${layerType.name}) would break isolation.',
      );
    }

    try {
      _receivePort = ReceivePort();

      // Listen for messages from isolate
      _receivePort!.listen((message) {
        logger.finest('Received message from isolate: ${message.runtimeType}');
        if (message is SendPort) {
          logger.fine('Received SendPort from isolate, setting ready');
          _sendPort = message;
          if (!_readyCompleter.isCompleted) {
            _readyCompleter.complete();
            logger.fine('Ready completer completed');
          } else {
            logger.fine('Ready completer already completed');
          }
        } else if (message is IsolateMessage) {
          logger.fine('Received isolate message: ${message.type}');

          // Handle error messages specifically
          if (message.type == IsolateMessageType.error) {
            _handleIsolateError(message);
          }

          _messageController.addEvent(message);
        } else if (message is LogRecord) {
          logger.finest('Forwarded log record from isolate');
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
                  config: params.config,
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

    // Remove from isolation registry
    _activeIsolates.remove(controllerId);
    _isolatesByLayer[layerType]!.remove(controllerId);

    // Kill isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    // Close ports
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;

    await _messageController.close();
    await _errorController.close();
  }

  /// Handle an error message from the isolate
  void _handleIsolateError(IsolateMessage errorMessage) {
    final error = IsolateError(
      controllerId: controllerId,
      errorMessage: errorMessage.data['error']?.toString() ?? 'Unknown error',
      cause: errorMessage.data['cause']?.toString(),
      timestamp: DateTime.fromMicrosecondsSinceEpoch(errorMessage.timestamp),
      isolateState: _isActive ? IsolateState.running : IsolateState.stopped,
    );

    _hasErrors = true;
    _addToErrorHistory(error);
    _errorController.addEvent(error);

    logger.warning('Isolate $controllerId error: ${error.errorMessage}');

    // Check if we should attempt automatic recovery
    if (_shouldAttemptRecovery(error)) {
      _scheduleRecovery(error);
    }
  }

  /// Add error to history, maintaining max size
  void _addToErrorHistory(IsolateError error) {
    _recentErrors.add(error);
    if (_recentErrors.length > _maxErrorHistory) {
      _recentErrors.removeAt(0);
    }
  }

  /// Determine if automatic recovery should be attempted
  bool _shouldAttemptRecovery(IsolateError error) {
    // Don't attempt recovery if we've already restarted too many times
    if (_restartCount >= _maxRestartAttempts) {
      logger.warning('Isolate $controllerId: Maximum restart attempts reached');
      return false;
    }

    // Don't attempt recovery for certain fatal errors
    if (error.isFatal) {
      logger.warning(
        'Isolate $controllerId: Fatal error, no recovery attempted',
      );
      return false;
    }

    // Check for rapid error succession
    final recentErrorCount =
        _recentErrors.where((e) {
          return DateTime.now().difference(e.timestamp).inMinutes < 1;
        }).length;

    if (recentErrorCount > 5) {
      logger.warning(
        'Isolate $controllerId: Too many recent errors, no recovery attempted',
      );
      return false;
    }

    return true;
  }

  /// Schedule an automatic recovery attempt
  void _scheduleRecovery(IsolateError error) {
    final delay = Duration(
      seconds: (1 << _restartCount),
    ); // Exponential backoff
    logger.info(
      'Isolate $controllerId: Scheduling recovery in ${delay.inSeconds} seconds',
    );

    Timer(delay, () async {
      try {
        await _attemptRecovery(error);
      } catch (e) {
        logger.severe('Isolate $controllerId: Recovery attempt failed: $e');
        // Create a new error for the failed recovery
        final recoveryError = IsolateError(
          controllerId: controllerId,
          errorMessage: 'Recovery attempt failed: $e',
          timestamp: DateTime.now(),
          isolateState: IsolateState.failed,
          isFatal: true,
        );
        _addToErrorHistory(recoveryError);
        _errorController.addEvent(recoveryError);
      }
    });
  }

  /// Attempt to recover the isolate
  Future<void> _attemptRecovery(IsolateError originalError) async {
    logger.info(
      'Isolate $controllerId: Attempting recovery (attempt ${_restartCount + 1})',
    );

    _restartCount++;

    // Stop the current isolate
    await stop();

    // Wait a moment for cleanup
    await Future.delayed(const Duration(milliseconds: 500));

    // Note: Automatic restart would require preserving the original entry point and params
    // For now, we just log the recovery attempt. The parent component should listen to
    // error events and handle restart if needed.

    logger.info(
      'Isolate $controllerId: Recovery attempt completed. Parent should restart if needed.',
    );

    // Emit a recovery event
    final recoveryEvent = IsolateError(
      controllerId: controllerId,
      errorMessage: 'Recovery attempted for: ${originalError.errorMessage}',
      timestamp: DateTime.now(),
      isolateState: IsolateState.recovering,
    );
    _addToErrorHistory(recoveryEvent);
    _errorController.addEvent(recoveryEvent);
  }

  /// Get current error statistics
  IsolateErrorStats getErrorStats() {
    final now = DateTime.now();
    final last24Hours =
        _recentErrors.where((e) {
          return now.difference(e.timestamp).inHours < 24;
        }).toList();

    final lastHour =
        _recentErrors.where((e) {
          return now.difference(e.timestamp).inHours < 1;
        }).toList();

    return IsolateErrorStats(
      totalErrors: _recentErrors.length,
      errorsLast24Hours: last24Hours.length,
      errorsLastHour: lastHour.length,
      restartCount: _restartCount,
      hasErrors: _hasErrors,
      lastError: _recentErrors.isNotEmpty ? _recentErrors.last : null,
    );
  }

  /// Clear error state (useful after manual recovery)
  void clearErrors() {
    _hasErrors = false;
    _recentErrors.clear();
    _restartCount = 0;
    logger.info('Isolate $controllerId: Error state cleared');
  }
  
  /// Get current isolate separation statistics
  static IsolateSeparationStats getSeparationStats() {
    return IsolateSeparationStats(
      coordinationIsolates: Set.from(_isolatesByLayer[IsolateLayerType.coordination]!),
      dataIsolates: Set.from(_isolatesByLayer[IsolateLayerType.data]!),
      testingIsolates: Set.from(_isolatesByLayer[IsolateLayerType.testing]!),
      isProperlyIsolated: isProperlyIsolated,
    );
  }
  
  /// Validate that the architecture maintains proper isolation
  static void validateIsolation() {
    if (!isProperlyIsolated) {
      final coordCount = _isolatesByLayer[IsolateLayerType.coordination]!.length;
      final dataCount = _isolatesByLayer[IsolateLayerType.data]!.length;
      
      throw LSLIsolateException(
        'CRITICAL: Isolate separation violated! '
        'Found $coordCount coordination and $dataCount data isolates with overlap. '
        'This violates the 4-layer architecture requirement.',
      );
    }
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
  final LSLPollingConfig config;
  final String nodeId;
  final SendPort? sendPort;

  const LSLOutletIsolateParams({
    required this.config,
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

/// Represents the state of an isolate
enum IsolateState {
  created,
  starting,
  running,
  stopping,
  stopped,
  failed,
  recovering,
}

/// Represents an error that occurred in an isolate
class IsolateError {
  final String controllerId;
  final String errorMessage;
  final String? cause;
  final DateTime timestamp;
  final IsolateState isolateState;
  final bool isFatal;

  const IsolateError({
    required this.controllerId,
    required this.errorMessage,
    this.cause,
    required this.timestamp,
    required this.isolateState,
    this.isFatal = false,
  });

  @override
  String toString() {
    return 'IsolateError($controllerId): $errorMessage${cause != null ? ' (cause: $cause)' : ''} at $timestamp';
  }
}

/// Statistics about isolate errors
class IsolateErrorStats {
  final int totalErrors;
  final int errorsLast24Hours;
  final int errorsLastHour;
  final int restartCount;
  final bool hasErrors;
  final IsolateError? lastError;

  const IsolateErrorStats({
    required this.totalErrors,
    required this.errorsLast24Hours,
    required this.errorsLastHour,
    required this.restartCount,
    required this.hasErrors,
    this.lastError,
  });

  @override
  String toString() {
    return 'IsolateErrorStats(total: $totalErrors, 24h: $errorsLast24Hours, 1h: $errorsLastHour, restarts: $restartCount)';
  }
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

/// Statistics about isolate layer separation
class IsolateSeparationStats {
  final Set<String> coordinationIsolates;
  final Set<String> dataIsolates;
  final Set<String> testingIsolates;
  final bool isProperlyIsolated;

  const IsolateSeparationStats({
    required this.coordinationIsolates,
    required this.dataIsolates,
    required this.testingIsolates,
    required this.isProperlyIsolated,
  });

  /// Total number of active isolates
  int get totalIsolates => 
      coordinationIsolates.length + dataIsolates.length + testingIsolates.length;

  /// Whether coordination and data layers are properly separated
  bool get hasViolations => !isProperlyIsolated;

  @override
  String toString() {
    return 'IsolateSeparationStats('
        'coord: ${coordinationIsolates.length}, '
        'data: ${dataIsolates.length}, '
        'testing: ${testingIsolates.length}, '
        'isolated: $isProperlyIsolated'
        ')';
  }
}
