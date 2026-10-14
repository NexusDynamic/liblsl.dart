import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;
import 'package:lsl_core/lsl_core.dart' show LSLException, lslErrorWithDetail;

export 'package:lsl_core/lsl_core.dart'
    show
        LSLException,
        LSLTimeout,
        LSLSampleListenerException,
        lslErrorWithDetail;

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
