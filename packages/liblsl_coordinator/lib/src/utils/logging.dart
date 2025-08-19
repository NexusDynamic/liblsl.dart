import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
export 'package:logging/logging.dart' show LogRecord;

Logger get logger => Log._logger;

class Log {
  static const String loggerName = 'LSLCoordinator';
  static const String isolateLoggerName = 'LSLCoordinator (Isolate)';
  static Logger _logger = Logger(loggerName);
  static SendPort? _sendPort;
  static StreamSubscription<LogRecord>? _subscription;

  static set sendPort(SendPort? port) {
    _subscription?.cancel();
    _subscription = null;
    _sendPort = port;
    if (port != null) {
      // Isolate logging does not alter the root logger's level,
      Logger.root.level = Level.ALL;
      _logger = Logger(isolateLoggerName);
      _subscription = Logger.root.onRecord.listen((LogRecord record) {
        _sendPort?.send(record);
      });
    } else {
      _logger = Logger(loggerName);
    }
  }

  static void logIsolateMessage(LogRecord record) {
    logger.log(
      record.level,
      record.message,
      record.error,
      record.stackTrace,
      record.zone,
    );
  }
}

// void _isolateEntryPointExample(SendPort sendPort) {
//   Log.sendPort = sendPort;
//   logger.warning('warning, your isolate does nothing');
// }

// void startLoggingIsolateExample() {
//   final receivePort = ReceivePort();
//   Isolate.spawn(_isolateEntryPointExample, receivePort.sendPort).then((_) {
//     receivePort.listen((message) {
//       if (message is LogRecord) {
//         Log.logIsolateMessage(message);
//       }
//     });
//   });
// }
