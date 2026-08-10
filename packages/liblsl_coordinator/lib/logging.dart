import 'dart:async';

import 'package:logging/logging.dart';

import 'src/logging/ansi_stub.dart'
    if (dart.library.io) 'src/logging/ansi_io.dart'
    if (dart.library.js_interop) 'src/logging/ansi_web.dart';

export 'package:logging/logging.dart' show LogRecord;

Logger get logger => Log._logger;

/// Logging for the coordination layer.
///
/// The core here is pure Dart so it works on the VM and on the web. Two things
/// that used to make it VM-only are now abstracted:
///
///  * **Colour detection.** `dart:io`'s `stdout.supportsAnsiEscapes` is behind
///    a conditional import, defaulting to "no colour" everywhere else —
///    browser consoles render ANSI codes as literal garbage.
///  * **Forwarding.** This used to take a `dart:isolate` `SendPort` directly.
///    It now takes a plain callback ([forwardTo]), so the isolate dependency
///    belongs to the caller that actually has isolates. The web has no
///    isolates, and a WebSocket transport needs no worker at all.
class Log {
  static const String loggerName = 'LSLCoordinator';

  /// Name used while records are being forwarded to another execution context.
  static const String forwardedLoggerName = 'LSLCoordinator (forwarded)';

  @Deprecated('Use forwardedLoggerName')
  static const String isolateLoggerName = forwardedLoggerName;

  static Logger _logger = Logger(loggerName);
  static void Function(LogRecord)? _forwarder;
  static StreamSubscription<LogRecord>? _subscription;
  static bool _useColors = true;

  /// Whether output should be colourised.
  ///
  /// True only if colour is both requested and supported by the platform.
  static bool get useColors => _useColors && ansiSupported;

  static set useColors(bool value) {
    _useColors = value;
  }

  /// A ready-made printer: `Logger.root.onRecord.listen(Log.defaultPrinter)`.
  static void defaultPrinter(LogRecord record) {
    print(
      wrapMessageColor(
        '[${record.level.name}] ${record.time}: '
        '${record.loggerName}: ${record.message}',
        record.level,
      ),
    );
  }

  /// Sends every record to [sink] instead of handling it locally.
  ///
  /// Used by workers that need their logs surfaced in the host context — an
  /// LSL isolate passes `(record) => sendPort.send(record)`. Pass null to stop
  /// forwarding and return to normal local logging.
  ///
  /// Takes a callback rather than a `SendPort` so this file stays free of
  /// `dart:isolate`, which does not exist on the web.
  static void forwardTo(void Function(LogRecord record)? sink) {
    _subscription?.cancel();
    _subscription = null;
    _forwarder = sink;
    if (sink != null) {
      // Forwarding must not be filtered out before it reaches the host, which
      // is where the real level is applied.
      Logger.root.level = Level.ALL;
      _logger = Logger(forwardedLoggerName);
      _subscription = Logger.root.onRecord.listen((record) {
        _forwarder?.call(record);
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

  /// Re-emits a record received from a forwarding context, preserving its
  /// original level, error and stack trace.
  static Future<void> replayRecord(LogRecord record) async {
    logger.log(
      record.level,
      record.message,
      record.error,
      record.stackTrace,
      record.zone,
    );
  }

  @Deprecated('Use replayRecord')
  static Future<void> logIsolateMessage(LogRecord record) =>
      replayRecord(record);
}
