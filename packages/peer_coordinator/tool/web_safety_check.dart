// Web-safety check for the transport-neutral core.
//
// Compile this to JavaScript to prove that nothing in the core's import
// closure — or the in-memory transport's — reaches `dart:io`, `dart:isolate`,
// `dart:ffi`, or a literal the web cannot represent:
//
//   dart compile js -o /tmp/web_check.js tool/web_safety_check.dart
//
// Includes the WebSocket *client*, which is the whole point of the web
// target: a browser node coordinates through a hub.
//
// Deliberately does NOT import `package:peer_coordinator/hub.dart` (dart:io —
// browsers connect to a hub, they do not host one) or
// `package:liblsl_coordinator/transports/lsl.dart` (native by nature).
// dart2js only compiles what the entrypoint reaches, which is also why an app
// using only LSL never pays for the WebSocket transport.
//
// This caught two real blockers when it was first run: `dart:io` in the logger
// and an int64 bound in `message.dart` that has no JavaScript representation.
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator/websocket.dart';

void main() {
  final bus = InMemoryBus();
  final config = CoordinationConfig(
    name: 'web_check',
    sessionConfig: CoordinationSessionConfig(name: 'WebSession'),
    transportConfig: InMemoryTransportConfig(bus: bus),
  );
  final session = PeerSession.create(config);

  // Reference the WebSocket transport so it is genuinely in the closure.
  final wsConfig = WebSocketTransportConfig(
    hubUri: Uri.parse('ws://example.invalid:8080'),
  );

  print(
    '${session.name} ${session.isCoordinator} ${bus.registry.length} '
    '${wsConfig.hubUri} $wsProtocolVersion',
  );
}
