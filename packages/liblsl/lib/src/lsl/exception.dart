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

/// Builds an [LSLException] for a nonzero liblsl error code, naming the code
/// and appending liblsl's own message for it when one is available.
///
/// Must be called on the thread that made the failing call: liblsl keeps the
/// message in a thread-local buffer, so calling this from a different isolate
/// than the one that failed yields the code alone.
LSLException lslError(String what, int code) {
  final name = switch (code) {
    -1 => 'timeout',
    -2 => 'lost',
    -3 => 'argument',
    -4 => 'internal',
    _ => 'unknown',
  };
  final detailPtr = lsl_last_error();
  final detail = detailPtr.isNullPointer
      ? ''
      : detailPtr.cast<Utf8>().toDartString();
  final suffix = detail.isEmpty ? '' : ': $detail';
  return code == -1
      ? LSLTimeout('$what: $name error ($code)$suffix')
      : LSLException('$what: $name error ($code)$suffix');
}
