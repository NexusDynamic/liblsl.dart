// Web-safety check for the transport-neutral core.
//
// Compile this to JavaScript to prove that nothing in the core's import
// closure — or the in-memory transport's — reaches `dart:io`, `dart:isolate`,
// `dart:ffi`, or a literal the web cannot represent:
//
//   dart compile js -o /tmp/web_check.js tool/web_safety_check.dart
//
// Deliberately does NOT import `transports/lsl.dart`: that one is native-only
// by nature. dart2js only compiles what the entrypoint reaches, which is also
// why an app that uses only LSL never pays for the WebSocket transport.
//
// This caught two real blockers when it was first run: `dart:io` in the logger
// and an int64 bound in `message.dart` that has no JavaScript representation.
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/memory.dart';

void main() {
  final bus = InMemoryBus();
  final config = CoordinationConfig(
    name: 'web_check',
    sessionConfig: CoordinationSessionConfig(name: 'WebSession'),
    transportConfig: InMemoryTransportConfig(bus: bus),
  );
  final session = PeerSession.create(config);
  print('${session.name} ${session.isCoordinator} ${bus.registry.length}');
}
