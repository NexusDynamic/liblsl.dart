# webrtc_coordinator_flutter

The [`flutter_webrtc`](https://pub.dev/packages/flutter_webrtc) binding for
[`webrtc_coordinator`](https://pub.dev/packages/webrtc_coordinator): an
`RtcPeerAdapter` backed by real peer connections, so
[`peer_coordinator`](https://pub.dev/packages/peer_coordinator) sessions can
run peer-to-peer over WebRTC data channels in a Flutter app.

All transport logic (the dial state machine, routing, framing, streams) lives
in the pure-Dart `webrtc_coordinator` package, which is tested headlessly
against a fake adapter. This package only adds what needs a device: real SDP,
ICE and SCTP. It exists separately because `flutter_webrtc` is a plugin with
native code, which a pure-Dart package cannot depend on.

## Usage

```dart
import 'package:peer_coordinator/websocket.dart' show HubCredentials;
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';

final session = PeerSession.create(
  CoordinationConfig(
    name: 'my_experiment',
    sessionConfig: CoordinationSessionConfig(name: 'lab', maxNodes: 4),
    transportConfig: RtcTransportConfig(
      hubUri: Uri.parse('ws://hub.local:8080'),
      credentials: HubCredentials(session: 'lab', secret: hubSecret),
      adapterFactory: flutterWebrtcAdapterFactory,
      // For peers on different networks, add STUN/TURN servers:
      // iceServers: [{'urls': 'stun:stun.l.google.com:19302'}],
    ),
  ),
);
await session.initialize();
await session.join();
```

The hub only handles discovery, election and signalling; run one with
`dart run peer_coordinator:hub` (see the
[`peer_coordinator` README](https://pub.dev/packages/peer_coordinator)).
Everything else goes directly between peers.

## Platform setup

Only data channels are used (no camera or microphone), so the app needs
network access and nothing more:

- **Android**: `<uses-permission android:name="android.permission.INTERNET"/>`
  in `AndroidManifest.xml`.
- **macOS**: the `com.apple.security.network.client` and
  `com.apple.security.network.server` entitlements.
- iOS, Windows, Linux and web need no extra configuration.

See the [`flutter_webrtc` documentation](https://pub.dev/packages/flutter_webrtc)
for anything platform-specific.
