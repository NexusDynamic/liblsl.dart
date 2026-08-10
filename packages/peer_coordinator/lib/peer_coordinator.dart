/// Transport-neutral peer coordination.
///
/// Provides coordinator election, membership and heartbeat, and synchronised
/// data streams, over whichever backend you supply. Nothing here is tied to a
/// particular transport, and nothing here imports `dart:io`, `dart:isolate` or
/// `dart:ffi`, so it compiles for the web.
///
/// Pick a transport by choosing an [ITransportConfig]:
///
///  * `package:peer_coordinator/in_memory.dart` — everything in one process,
///    for tests.
///  * `package:liblsl_coordinator/transports/lsl.dart` — Lab Streaming Layer.
library;

export 'config.dart';
export 'framework.dart';
