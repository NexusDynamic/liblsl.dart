/// Lab Streaming Layer tools in pure Dart: a web-safe facade over
/// `package:liblsl` ([lsl]), recording to XDF ([LslRecorder]), sharing
/// streams over a WebSocket bridge ([LslBridgeServer], [LslBridgeClient]),
/// and test outlets. `bin/lsl.dart` runs them from the command line.
library;

export 'src/bridge/client.dart';
export 'src/bridge/protocol.dart' show BridgeStream;
export 'src/bridge/server.dart';
export 'src/lsl.dart';
export 'src/lsl_recorder.dart';
export 'src/lsl_test_outlets.dart';
