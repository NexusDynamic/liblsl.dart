# webrtc_coordinator

[![Pub Version](https://img.shields.io/pub/v/webrtc_coordinator)](https://pub.dev/packages/webrtc_coordinator)

`webrtc_coordinator` is a peer-to-peer transport for
[`peer_coordinator`](https://pub.dev/packages/peer_coordinator). Coordination
messages and data travel directly between devices over WebRTC data
channels, and a hub is used only for discovery and connection setup.

The package is pure Dart and contains no WebRTC implementation. An
application supplies an `RtcPeerAdapter`:
[`webrtc_coordinator_flutter`](https://pub.dev/packages/webrtc_coordinator_flutter)
provides one based on `flutter_webrtc`, and
`package:webrtc_coordinator/testing.dart` provides a fake adapter for tests
that run without a device.

[API documentation](https://pub.dev/documentation/webrtc_coordinator/latest/)

## Comparison with the WebSocket transport

The WebSocket transport of `peer_coordinator` relays every message through
the hub, so each message takes two network hops. With this transport, peers
exchange an offer and an answer through the hub and then communicate
directly, in one hop.

A data channel can also be unreliable and unordered, which a relay cannot
provide. A stream for which latency matters more than completeness can then
avoid the cost of retransmissions.

## Installation

```bash
dart pub add webrtc_coordinator
```

A Flutter application adds `webrtc_coordinator_flutter` as well.

## Usage

```dart
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';

final config = CoordinationConfig(
  name: 'my_session',
  transportConfig: RtcTransportConfig(
    hubUri: Uri.parse('ws://hub.local:8080'),
    adapterFactory: flutterWebrtcAdapterFactory,
    // Data streams only; the coordination stream is always reliable and
    // ordered, because a lost election message splits the session.
    dataOrdered: false,
    dataMaxRetransmits: 1,
  ),
);
```

The hub is the one used by the WebSocket transport:

```sh
dart run peer_coordinator:hub --host 0.0.0.0 --port 8080
```

## What passes through the hub

| Traffic | Path |
| --- | --- |
| Endpoint registration, peer queries, election | Hub |
| WebRTC offers, answers and ICE candidates | Hub |
| Coordination messages | Direct |
| Data samples | Direct |

`test/transports/rtc_transport_test.dart` verifies this: after a complete
data exchange, the routing table of the hub is empty for every stream.

## ICE and NAT

`iceServers` is empty by default, which gives host candidates only: peers on
one local network connect directly and no third party is involved. STUN
servers can be added for peers behind NAT.

A connection relayed by a TURN server passes through that server, in the
same way as traffic through the hub. The single-hop property described above
therefore holds for host and server-reflexive (STUN) connectivity, and does
not hold for TURN.

## Design

There is one `RTCPeerConnection` for each pair of peers, shared by all
streams between them. It is keyed on the node uId, which is the only
identifier that remains stable when the role of a node changes in an
election.

Each stream has one data channel, opened with `negotiated: true` and an id
derived from the stream name (`rtcChannelIdFor`), so that the two ends do
not exchange channel metadata. Collisions of derived ids are checked when a
channel is opened.

When two peers dial each other at the same time, the node with the
lexicographically lower uId makes the offer.

Routing is local to each peer. `RtcMesh.subscribersFor` takes the place of
the hub's `RelayRouting` and is filled by the `open` signal that a
subscriber sends. A producer sends on exactly the channels whose far end has
asked for them.

Samples use the `WsSampleFrame` format of the WebSocket transport, so the
encoders and `decodeChannels` are shared and covered by the tests of that
transport. The slot fields of the frame are written as zero and are not
read, since a data channel identifies its sender.

### The adapter

`flutter_webrtc` cannot run in a `dart test` process, so every call to it
passes through `lib/src/rtc/rtc_adapter.dart`, and tests use
`FakeRtcPeerAdapter` in its place. No `flutter_webrtc` type appears in a
signature of that interface: session descriptions and ICE candidates cross
it as JSON maps, and the six values of `RTCPeerConnectionState` cross as the
three values of `RtcLinkState`. This makes the dial state machine, the
resolution of simultaneous dials, the routing and the framing testable
without a device.

### Contracts for implementers

| Contract | Reason |
| --- | --- |
| `discoverOnce` waits for its full timeout when nothing matches | The election concludes that no better candidate exists from an empty result after the timeout. An early return makes every node elect itself and splits the session |
| `PeerHandle.take()` transfers ownership exactly once, and `addInlet` calls it before using the handle | A discovery cycle must not free a resource that a stream is using |
| `inbox` is a broadcast stream | Several subscribers read it |
| Delivery by the fake adapter is asynchronous, as in `InMemoryBus` | A synchronous fake hides ordering errors and validates behaviour that no real transport has |

## Testing

```sh
dart analyze
dart test
dart run benchmark/rtc_latency_bench.dart 60 5
```

`test/transports/participation_modes_test.dart` runs the shared
`runParticipationScenarios` suite of `peer_coordinator`, which the in-memory
and WebSocket transports also run. A participation mode is a property of the
coordination layer, so a scenario that passes there and fails here indicates
a defect in this transport.

The WebRTC arm of the benchmark runs against the fake adapter. It measures
the overhead of the library with the network removed and serves as a
regression check. Real peer-to-peer latency is measured with two devices on
one local network and the Flutter binding, for example with
[`transport_timing`](https://github.com/NexusDynamic/liblsl.dart/tree/main/apps/transport_timing).

## Known limitations

| Limitation | Detail |
| --- | --- |
| Tests without a device stop at the adapter | ICE restarts, packet loss and the difference between reliable and unreliable delivery are exercised only on a device |
| `maxRetransmits: 0` cannot be expressed through `flutter_webrtc` | `RTCDataChannelInit.toMap` writes the field only when it is positive, so zero produces a reliable channel. The binding logs a warning; `1` gives nearly unreliable delivery |
| `WsControl.peerGone` is not used | The hub broadcasts it when a socket closes, which would signal a departure sooner than a failed ICE connection. `RtcMesh.peerLost` currently depends on the link state alone |
| Mobile networks and NAT | Multiple network interfaces, Wi-Fi client isolation and carrier NAT can make host candidates fail in ways that a test on a local network does not show |
