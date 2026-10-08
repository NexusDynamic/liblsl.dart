# webrtc_coordinator_flutter

[![Pub Version](https://img.shields.io/pub/v/webrtc_coordinator_flutter)](https://pub.dev/packages/webrtc_coordinator_flutter)

`webrtc_coordinator_flutter` connects
[`webrtc_coordinator`](https://pub.dev/packages/webrtc_coordinator) to
[`flutter_webrtc`](https://pub.dev/packages/flutter_webrtc). It provides an
`RtcPeerAdapter` based on real peer connections, so that
[`peer_coordinator`](https://pub.dev/packages/peer_coordinator) sessions run
peer-to-peer over WebRTC data channels in a Flutter application.

The transport logic (the dial state machine, routing, framing and streams)
is in the pure-Dart `webrtc_coordinator` package, where it is tested against
a fake adapter. This package adds the parts that require a device: SDP, ICE
and SCTP. It is a separate package because `flutter_webrtc` is a plugin with
native code.

[API documentation](https://pub.dev/documentation/webrtc_coordinator_flutter/latest/)

## Installation

```bash
flutter pub add webrtc_coordinator_flutter
```

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

The hub handles discovery, election and signalling, and is started with
`dart run peer_coordinator:hub` (see the
[`peer_coordinator` README](https://pub.dev/packages/peer_coordinator)). All
other traffic passes directly between peers.

## Platform setup

Only data channels are used, so an application only requires network access.

| Platform | Configuration |
| --- | --- |
| Android | `<uses-permission android:name="android.permission.INTERNET"/>` in `AndroidManifest.xml` |
| macOS | The entitlements `com.apple.security.network.client` and `com.apple.security.network.server` |
| iOS, Windows, Linux, web | None |

The [`flutter_webrtc` documentation](https://pub.dev/packages/flutter_webrtc)
covers further platform-specific details.
