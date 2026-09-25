/// Lab Streaming Layer: receive any stream on the network and publish the
/// device or a recording.
///
/// Native only. On the web [lsl] is a stub whose [LslBackend.supported] is
/// false, and `package:liblsl` is never imported, so the web build does not
/// depend on it.
library;

import 'lsl_stub.dart' if (dart.library.ffi) 'lsl_native.dart' as platform;
import 'lsl_types.dart';

export 'lsl_types.dart';

/// This platform's LSL.
final LslBackend lsl = platform.createBackend();
