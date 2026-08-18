# webrtc_coordinator

A genuinely peer-to-peer transport for
[`peer_coordinator`](../peer_coordinator): coordination and data over WebRTC
data channels, with the hub demoted to discovery and connection setup.

Pure Dart. It ships no WebRTC implementation — you supply an `RtcPeerAdapter`.
[`webrtc_coordinator_flutter`](../webrtc_coordinator_flutter) provides one
backed by `flutter_webrtc`; `package:webrtc_coordinator/testing.dart` provides a
fake for headless tests.

## Why

The WebSocket transport relays every byte. The hub is on the data path by
design, so every message and every sample costs two network hops. Here it costs
one: peers exchange an offer and an answer through the hub, and everything
after that goes directly between them.

The hop count is the obvious win. The less obvious one is that a data channel
can be **unreliable and unordered**, which a relay cannot offer at all — so a
latency-critical sampling stream can stop paying for retransmissions it does
not want.

No core changes were needed for any of this. The abstraction was built for it:
LSL is already peer-to-peer behind the same interfaces.

## Using it

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

Run the same hub as the WebSocket transport:

```sh
dart run peer_coordinator:hub --host 0.0.0.0 --port 8080
```

## What still goes through the hub

Discovery and signalling, and nothing else.

| | Hub | Direct |
|---|---|---|
| Endpoint registration, peer queries, election | ✅ | |
| WebRTC offers, answers, ICE candidates | ✅ | |
| Coordination messages | | ✅ |
| Data samples | | ✅ |

`test/transports/rtc_transport_test.dart` pins this: after a full data exchange
the hub's routing table is empty for every stream, so it could not have relayed
a byte even if one had arrived.

## How it is put together

* **One `RTCPeerConnection` per peer pair**, keyed on node uId — the only
  identifier stable across an election role change — and shared by every stream
  between those two peers.
* **One data channel per stream**, opened `negotiated: true` with an id derived
  from the stream name (`rtcChannelIdFor`), so neither end has to exchange
  channel metadata. Derivation collisions are asserted on at open time rather
  than trusted.
* **Glare** is resolved by rule, not negotiation: the lexicographically lower
  node uId makes the offer.
* **Routing is local.** The hub's `RelayRouting` becomes
  `RtcMesh.subscribersFor`, filled by the `open` signal a subscriber sends. A
  producer sends on exactly the channels whose far end asked for them.
* **Samples reuse `WsSampleFrame` verbatim**, so the encoders and
  `decodeChannels` stay shared and covered by the WebSocket transport's tests.
  Its slot fields are written as zero and never read — a data channel identifies
  its sender by being that channel.

### The adapter seam

`flutter_webrtc` cannot run in a headless `dart test` VM, so every call into it
goes through `lib/src/rtc/rtc_adapter.dart`, with `FakeRtcPeerAdapter` on the
other side for tests. **No `flutter_webrtc` type may appear in a signature
there**: session descriptions and ICE candidates cross as plain JSON maps, and
`RTCPeerConnectionState`'s six values cross as `RtcLinkState`'s three.

That is what makes the dial state machine, glare resolution, routing fan-out and
framing testable without a device — which is nearly all of the transport. Only
the binding needs one.

## ICE, NAT, and what "peer-to-peer" means here

`iceServers` defaults to empty: host candidates only, pure LAN peer-to-peer with
no third party involved, which is the open-network case this exists for. STUN is
opt-in for crossing a NAT.

**TURN reintroduces a relay.** A TURN-relayed connection is peer-to-peer in name
only — the bytes go through someone else's server, exactly as they do through
the hub — so the halved hop count does not survive it. The claim in this README
holds for host and srflx connectivity.

## Contracts that are easy to get wrong

Three, two of which have already been got wrong once elsewhere:

1. **`discoverOnce` must wait out its full timeout when nothing matches.**
   Election concludes "no better candidate exists" precisely by finding nothing
   after the full timeout. Returning early on an empty result makes every node
   elect itself and splits the session.
2. **`PeerHandle.take()` transfers ownership exactly once**, and `addInlet` must
   call it before touching the handle, so a discovery cycle cannot free a
   resource a stream is still using.
3. **`inbox` must be a broadcast stream.** Several subscribers read it.

And one specific to keeping this package testable:

4. **The fake's delivery must stay asynchronous**, as `InMemoryBus` is careful
   to be. A synchronous fake makes ordering bugs invisible and lets the suite
   validate behaviour no real transport has.

## Testing

```sh
dart analyze
dart test              # 35 tests, including the participation-mode gate
dart run benchmark/rtc_latency_bench.dart 60 5
```

`test/transports/participation_modes_test.dart` runs `peer_coordinator`'s shared
`runParticipationScenarios` suite — the same one the in-memory and WebSocket
transports run. A participation mode is a property of the coordination layer,
not of how bytes move, so anything that passes there and fails here is a
transport bug. **That is the acceptance gate.**

The benchmark's WebRTC arm runs against the fake, so it measures the library's
own overhead with the network removed — a useful regression check, not an
estimate of real peer-to-peer latency. For that, run two devices on one LAN with
the Flutter binding.

## Known gaps

* **Headless testing stops at the adapter boundary.** Anything the fake does not
  model — ICE restarts, packet loss, the actual difference between reliable and
  unreliable delivery — is only exercised on a device.
* **`maxRetransmits: 0` cannot be expressed through `flutter_webrtc`.** Its
  `RTCDataChannelInit.toMap` writes the field only when it is positive, so zero
  silently produces a reliable channel. The binding logs a warning; use `1` for
  near-unreliable delivery.
* **`WsControl.peerGone` is still consumed by nobody.** The hub broadcasts it on
  socket close, which would be a faster departure signal than waiting for ICE to
  fail. `RtcMesh.peerLost` currently fires on link state alone.
* **Mobile and NAT.** Multiple NICs, Wi-Fi client isolation and carrier NAT all
  make host candidates fail in ways a LAN test will not show.
