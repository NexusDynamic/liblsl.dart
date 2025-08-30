import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:logging/logging.dart';
export 'package:logging/logging.dart' show LogRecord;

Logger get logger => Log._logger;

class Log {
  static const String loggerName = 'LSLCoordinator';
  static const String isolateLoggerName = 'LSLCoordinator (Isolate)';
  static Logger _logger = Logger(loggerName);
  static SendPort? _sendPort;
  static StreamSubscription<LogRecord>? _subscription;
  static bool _useColors = true;

  static bool get useColors => _useColors && stdout.supportsAnsiEscapes;
  static set useColors(bool value) {
    _useColors = value;
  }

  static void defaultPrinter(LogRecord record) {
    print(
      wrapMessageColor(
        '[${record.level.name}] ${record.time}: ${record.loggerName}: ${record.message}',
        record.level,
      ),
    );
  }

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

  static String wrapMessageColor(String message, Level level) {
    if (!useColors) return message;
    // ANSI color codes
    const reset = '\x1B[0m';
    const red = '\x1B[31m';
    const green = '\x1B[32m';
    const yellow = '\x1B[33m';
    const blue = '\x1B[34m';
    const magenta = '\x1B[35m';
    const cyan = '\x1B[36m';

    String color;
    if (level >= Level.SEVERE) {
      color = red;
    } else if (level >= Level.WARNING) {
      color = yellow;
    } else if (level >= Level.INFO) {
      color = green;
    } else if (level >= Level.CONFIG) {
      color = cyan;
    } else if (level >= Level.FINE) {
      color = blue;
    } else if (level >= Level.FINER) {
      color = magenta;
    } else {
      color = reset; // Default terminal color
    }

    return '$color$message$reset';
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
