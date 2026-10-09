import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;

/// LSLException base exception class
class LSLException implements Exception {
  final String message;

  /// Creates a new LSLException with the given message.
  /// The [message] parameter is used to create the exception message.
  LSLException(this.message);

  @override
  String toString() {
    return 'LSLException: $message';
  }
}

/// LSLTimeout exception class
class LSLTimeout extends LSLException {
  LSLTimeout(super.message);

  @override
  String toString() {
    return 'LSLTimeout: $message';
  }
}

/// Why an [LSLInlet.sampleStream] ended without being cancelled.
///
/// The stream delivers one of these and then closes. A stream that closes
/// with no error was cancelled by its subscriber; nothing else ends it
/// quietly.
class LSLSampleListenerException extends LSLException {
  /// The liblsl error code of the failed pull (-2 lost, -3 argument,
  /// -4 internal), or null when the listener failed for another reason.
  final int? errorCode;

  /// A stack trace, when the listener failed for a reason other than a pull.
  final String? stackTrace;

  LSLSampleListenerException(super.message, {this.errorCode, this.stackTrace});

  /// Whether liblsl reported the stream as lost: the inlet will not deliver
  /// again and has to be reopened.
  bool get isLost => errorCode == -2;

  @override
  String toString() => 'LSLSampleListenerException: $message';
}

/// Builds an [LSLException] for a nonzero liblsl error code, naming the code
/// and appending liblsl's own message for it when one is available.
///
/// Must be called on the thread that made the failing call: liblsl keeps the
/// message in a thread-local buffer, so calling this from a different isolate
/// than the one that failed yields the code alone.
LSLException lslError(String what, int code) {
  final detailPtr = lsl_last_error();
  return lslErrorWithDetail(
    what,
    code,
    detailPtr.isNullPointer ? '' : detailPtr.cast<Utf8>().toDartString(),
  );
}

/// As [lslError], with liblsl's message already in hand: for a call that
/// failed on another thread, which read the message there.
LSLException lslErrorWithDetail(String what, int code, String detail) {
  final name = switch (code) {
    -1 => 'timeout',
    -2 => 'lost',
    -3 => 'argument',
    -4 => 'internal',
    _ => 'unknown',
  };
  final suffix = detail.isEmpty ? '' : ': $detail';
  return code == -1
      ? LSLTimeout('$what: $name error ($code)$suffix')
      : LSLException('$what: $name error ($code)$suffix');
}
