# A genuinely peer-to-peer transport, over WebRTC data channels

Originally a handoff plan written at the end of the session that built phase 1.
**Phases 1–6 are now implemented**; see Status below for what is verified and
what still needs a device. The design sections below are kept as the record of
why the transport is shaped the way it is — read `packages/webrtc_coordinator/README.md`
for how to use it.

## Why

The WebSocket transport relays every byte. The hub is on the data path by
design — `WsSampleFrame`'s header says so ("srcSlot REWRITTEN BY THE HUB on
relay"), and `addInlet` does not connect to anything, it installs a route in the
hub. Every message and every sample costs two network hops.

The question this answers: can the hub be demoted to discovery and connection
setup, with data going directly between peers? Yes. The abstraction was built
for it — LSL is already genuinely peer-to-peer behind the same interfaces — and
**no core changes are needed**.

WebRTC rather than a listening WebSocket per peer, because browsers cannot
listen. A direct-WS mesh would drop the web target that `peer_coordinator`
currently supports; WebRTC keeps it.

## Status

### Done — phase 1: the signalling frame

`WsControl.signal` is the hub's only unicast and the only frame whose contents it
never inspects. 188 package tests pass, analyzer is clean, and the web-safety
gate still compiles.

- `lib/src/websocket/ws_protocol.dart` — `WsControl.signal`; `wsProtocolVersion`
  bumped 1 → 2. (It is 3 now: `WsControl.unsubscribe` followed, for
  `removeInlet`.)
- `lib/hub.dart` — `CoordinationHub._forwardSignal`. Verifies the sender owns the
  `from` endpoint (exactly as `_relayMessage` does), then re-encodes rather than
  forwarding bytes, so `from` is the endpoint the hub verified and not whatever
  the sender wrote. Unknown or departed `to` is dropped silently.
- `lib/src/websocket/ws_connection.dart` — `sendSignal(...)`, `Stream<WsSignal>
  signals`, and the `WsSignal` class. `_signals` is closed in `close()`.
- `lib/websocket.dart` — exports `WsSignal`.
- `test/websocket/ws_signalling_test.dart` — 6 tests: delivery, opaque payloads,
  unicast isolation, impersonation refusal, unknown target, bidirectional
  offer/answer.
- `test/websocket/ws_protocol_test.dart` — signal round-trip, and the version
  coupling pinned out loud.

**The version bump is a hard cut.** `WsFrame.decode` rejects unknown versions
rather than guessing, so a hub and its clients must be deployed together.

### Done — phases 2–6

All in `packages/webrtc_coordinator` (pure Dart) and
`packages/webrtc_coordinator_flutter` (the plugin binding).

- **Phase 2 — seam, config, transport.** `lib/src/rtc/rtc_adapter.dart` is the
  boundary; `lib/src/rtc/fake/fake_adapter.dart` is the pure-Dart fake behind it.
  `RtcTransportConfig` / `RtcTransport` in `lib/src/transport/rtc_transport.dart`,
  with discovery delegated to `WsDiscovery` verbatim and a non-null
  `PeerClockOffsets`. The adapter is supplied by an `RtcAdapterFactory` on the
  config — the one seam that keeps `flutter_webrtc` out of the pure-Dart package.
- **Phase 3 — the data path.** `RtcMesh` (`lib/src/rtc/rtc_mesh.dart`) owns links
  and channels; `RtcStreamMixin` + `RtcCoordinationStream` / `RtcDataStream` /
  `RtcNetworkStreamFactory` in `lib/src/streams/rtc_stream.dart`.
- **Phase 4 — the binding.** `webrtc_coordinator_flutter/lib/src/flutter_rtc_adapter.dart`
  implements the seam over `flutter_webrtc`. Analyzer-clean against the real API;
  **not yet run on a device** — that is the one outstanding verification.
- **Phase 5 — conformance and measurement.** `runParticipationScenarios` passes
  against the fake adapter (`test/transports/participation_modes_test.dart`), and
  `test/transports/rtc_transport_test.dart` pins the hub off the data path, the
  reliability plumbing and `removeInlet`. `benchmark/rtc_latency_bench.dart` runs
  both arms in one process.
- **Phase 6 — example.** The example's `ConnectPage` has a Relay/Direct selector;
  `ChatSession` already took an `ITransportConfig`, so nothing else changed.

35 tests pass in `webrtc_coordinator`, 193 in `peer_coordinator`, 9 in the
example; all three packages are analyzer-clean and the web-safety gate compiles.

#### Two decisions taken during implementation, not in the plan below

1. **A fifth signal kind, `open`.** The plan did not account for `negotiated:
   true` needing *both* ends to open a channel while an asymmetric participation
   mode (`sendAllReceiveCoordinator`) has producers that never subscribe back —
   and for the higher-uId peer having no way to ask the offerer to dial. One
   signal solves both: a subscriber sends `open{stream, id, ordered,
   maxRetransmits}`, the far end opens its half and registers the sender as a
   subscriber. It is therefore also the transport's *only* subscribe.
2. **Routing is `RtcMesh.subscribersFor`, not `RelayRouting`.** With the hub off
   the data path the routing table has to live locally, and the `open` signal
   already fills exactly the map `RelayRouting` would have held. Using the core
   class would have added an indirection over the same data.

## Constraints that decide the shape

1. **`peer_coordinator` must stay pure Dart and web-safe.** `tool/web_safety_check.dart`
   enforces it in CI (`dart compile js -o /tmp/web_check.js tool/web_safety_check.dart`).
   `flutter_webrtc` is a Flutter plugin with native code, so the transport
   **cannot live in this package**. It goes in a sibling — `packages/webrtc_coordinator` —
   added to the workspace list in the root `pubspec.yaml`. `liblsl_coordinator` is
   the precedent: same reason (native-only), same shape.

2. **Signalling cannot ride the coordination stream.** That stream is what is
   being established. It goes out-of-band on the hub socket — which is what
   phase 1 built.

3. **The hub client is already public.** `lib/websocket.dart` exports
   `WsConnection`, `WsInbound`, `WsSignal`, `WsDiscovery`, `WsPeerHandle`,
   `WsControl`, `WsFrame`, `WsSampleFrame`, `wsProtocolVersion`, `WsStreamMixin`,
   `WsCoordinationStream`, `WsDataStream`, `WsNetworkStreamFactory`,
   `WebSocketTransport`, `WebSocketTransportConfig`. The new package reuses
   `WsConnection` + `WsDiscovery` verbatim and writes only a new data path.

## What the abstraction already gives you

Verified, not assumed:

- **Discovery and the data path are independent.** `ITransport`
  (`lib/src/interfaces/transport.dart`, 61 lines) asks for a `streamFactory` and
  a `createDiscovery`, with nothing linking them. The WS transport couples them
  only because both happen to share one `WsConnection` object.
- **`PeerHandle.rawUnsafe`** is documented as "the transport's private payload…
  an `LSLStreamInfo` for LSL, a connection id for a hub transport"
  (`lib/src/discovery/discovery.dart`). That is the dial target. LSL already does
  exactly this: its `addInlet` casts `rawUnsafe` to `LSLStreamInfo`.
- **`PeerDescriptor.extra`** is a wire-serialised `Map<String, String>` for
  "hostname, ports, connection id", never interpreted by the coordination layer,
  and currently **unused by anything in `lib/`**. It already crosses the hub. Free
  capacity for advertising anything static a peer needs to be dialled.
- **`RelayRouting`** is already `(streamName, producerEndpointId) -> {subscriberEndpointIds}`
  and **`PeerRegistry`** is already `endpointId -> PeerDescriptor`. Both are public
  via `lib/network.dart`. The only thing the hub owns that a P2P transport must
  own locally is `endpointId -> live connection`.
- **Clock sync is transport-agnostic.** Return a non-null `PeerClockOffsets` and
  leave `carriesSenderClock` / `sharesSenderClockDomain` false, and
  `ClockSyncService` does the rest. Its RTT then measures the real peer-to-peer
  path — the number `benchmark/ws_latency_bench.dart` exists to report.
- **`endpointId` is `'$sessionName/${node.uId}/$streamName'`**
  (`lib/src/discovery/peer_descriptor.dart`). Note that a restarted node gets a
  fresh `uId` and therefore a fresh endpoint id.

## What to build

### Phase 2 — package skeleton and the adapter seam

`packages/webrtc_coordinator/`, depending on `peer_coordinator` and
`flutter_webrtc`. Add to the root `pubspec.yaml` workspace list.

**Do the adapter seam first, before any transport code.** `flutter_webrtc`
cannot run in a headless `dart test` VM, so every call to it goes behind a thin
interface with a pure-Dart fake:

```dart
abstract interface class RtcPeerAdapter {
  Future<RtcPeerLink> connect(String peerEndpointId, {required bool asOfferer});
  Stream<RtcConnectionState> get states;
  Future<void> close();
}

abstract interface class RtcPeerLink {
  Future<RtcChannel> openChannel(int id, {required bool ordered, int? maxRetransmits});
  Future<void> acceptOffer(Object sdp);   // driven by WsSignal
  Future<void> addCandidate(Object candidate);
  Stream<Object> get outgoingSignals;     // -> WsConnection.sendSignal
}
```

(Shape it as the implementation demands — the point is the boundary, not this
sketch.) With a fake behind it, the dial state machine, glare resolution, routing
fan-out and framing are all unit-testable in the VM; only the plugin binding
needs a device. **This is the single highest-value decision in the whole plan** —
get it wrong and nothing is testable without a simulator.

Also in this phase: `RtcTransportConfig implements ITransportConfig`
(signalling hub URI, ICE servers, per-stream reliability defaults;
`createTransport()`, `validate()`, `copyWith()`, `toMap()`, `==`/`hashCode`), and
`RtcTransport extends ManagedResource implements ITransport<RtcTransportConfig>,
IResourceManager` — copy the resource plumbing from `ws_transport.dart`, and
return a **non-null** `PeerClockOffsets` from `clockOffsets`.

Discovery: delegate to `WsDiscovery` unchanged, over the same `WsConnection` used
for signalling.

### Phase 3 — the data path

`RtcStreamMixin`, modelled on `WsStreamMixin` (`lib/src/websocket/ws_stream.dart`)
and `InMemoryStreamMixin`. It replaces exactly four hub calls: `announce`,
`subscribe`, `publishMessage`, `publishSample`.

| `NetworkStream` member | WebRTC implementation |
|---|---|
| `create()` | wire `_incoming` (must be **broadcast**) / `_outgoing`; announce to the hub with `publish: false` |
| `createOutlet()` / `recreateOutlet()` | announce with `publish: true`; start answering inbound offers. `recreateOutlet` runs after the election role flip |
| `addInlet(handle)` | `handle.take()` **first**, dedupe, then dial the peer and record `endpointId -> channel` |
| `createInletsForNodes(nodes)` | resolve-and-retry until every wanted `nodeUId` is connected; `StateError` on timeout. Mirror `ws_stream.dart`, and note LSL's continuous-resolver comment in `lsl_stream.dart` — the same race applies |
| `sendMessage` / sample publish | write to the channels selected by `RelayRouting.subscribersFor(...)`; stamp `PeerClock.nowMicros()` |
| peer departure | `onConnectionState` failed/disconnected → local `PeerRegistry.detachNode` + `RelayRouting.removeEndpoint`. The hub's `peerGone` is a faster hint, currently consumed by nobody |

Then `RtcCoordinationStream extends CoordinationStream<CoordinationStreamConfig,
StringMessage>`, `RtcDataStream extends DataStream<DataStreamConfig, IMessage>`
(both `with InstanceUID, RtcStreamMixin<...>`), and `RtcNetworkStreamFactory
extends NetworkStreamFactory` supplying `createDataStream` and
`createCoordinationStream`.

Design decisions to carry in:

- **One `RTCPeerConnection` per peer pair**, shared by every stream between those
  two peers.
- **One data channel per `NetworkStream`**, opened `negotiated: true` with an `id`
  derived from the stream slot, so neither end has to exchange channel metadata.
- **Glare**: the lexicographically lower `endpointId` makes the offer.
  Deterministic, no negotiation needed.
- **Reliability**: coordination stream ordered + reliable. Data streams expose
  `ordered` / `maxRetransmits` in config, so a latency-critical sampling stream
  can run unreliable and unordered — something the relay cannot offer at all, and
  a real reason to prefer this transport beyond the halved hop count.
- **Reuse `WsSampleFrame` verbatim** for binary samples. Its only hub dependency
  is slot semantics; `srcSlot` becomes unused, since the data channel identifies
  the sender. That keeps the encoders and `decodeChannels` shared and already
  covered by `test/websocket/ws_protocol_test.dart`.
- **ICE**: `iceServers` defaults to empty — host candidates only, pure LAN P2P,
  which is the open-network case. STUN is opt-in for cross-NAT. **Document plainly
  that TURN reintroduces a relay**, so "genuinely peer-to-peer" holds for
  host/srflx connectivity only.

### Phase 4 — the `flutter_webrtc` binding

Implement `RtcPeerAdapter` against `flutter_webrtc`. Two-peer run under
`flutter test` on macOS, then one macOS peer and one Chrome peer, which is the
proof that browser parity survived.

### Phase 5 — conformance and measurement

- Implement `ParticipationHarness` (`lib/src/testing/participation_scenarios.dart`
  — `name`, `setUp`, `tearDown`, `transportConfigFor(int)`, plus tunables) and call
  `runParticipationScenarios(...)`, exactly as
  `test/transports/participation_modes_test.dart` does for in-memory and
  WebSocket. **This is the acceptance gate.**
- Extend `benchmark/ws_latency_bench.dart` with an RTC arm. Direct should roughly
  halve the round trip on the same LAN.
- Confirm the hub is off the data path: watch hub counters while a data stream
  runs — signalling and query traffic only, no `message` or sample frames.

### Phase 6 — example

Add the transport as an option on the example's `ConnectPage`, beside the
WebSocket one.

## Contracts that are easy to get wrong

Two are called out in the package README because they have already been got
wrong once:

1. **`discoverOnce` must wait out its full timeout when nothing matches.**
   Election concludes "no better candidate exists" precisely by finding nothing
   after the full timeout. Returning early on an empty result makes every node
   elect itself and splits the session.
2. **`PeerHandle.take()` transfers ownership exactly once**, and `addInlet` must
   call it before touching the handle, so a discovery cycle cannot free a
   resource a stream is still using.

Add a third, specific to this transport:

3. **`inbox` must be a broadcast stream.** Several subscribers read it.

## Known gaps and risks

- ~~**There is no `removeInlet` in the stream contract.**~~ Done: `removeInlet`
  is on `NetworkStream` with implementations for WebSocket (protocol v3
  `unsubscribe`), in-memory, LSL and WebRTC, and call sites in the controller and
  `PeerSession`.
- **The binding has not run on a device.** Everything below the adapter seam is
  exercised only by the fake. A two-peer `flutter test` on macOS, then macOS +
  Chrome, is the remaining phase-4 verification.
- **`maxRetransmits: 0` cannot be expressed through `flutter_webrtc`** —
  `RTCDataChannelInit.toMap` writes the field only when positive, so zero
  silently yields a reliable channel. The binding warns; use `1`.
- **`WsControl.peerGone` is still consumed by nobody.** The hub broadcasts it on
  socket close (`_onDisconnected`). Wiring it up would give this transport fast
  departure detection instead of waiting for ICE to fail. A neutral
  `Stream<String> get producerLost` on `NetworkStream` (default `Stream.empty()`)
  was scoped for this and not built.
- **Headless testing stops at the adapter boundary.** Anything the fake does not
  model is only exercised on a device. Keep the fake honest — in particular
  delivery must be asynchronous, as `InMemoryBus` is careful to be, or the suite
  validates behaviour no real transport has.
- **Mobile and NAT.** Multiple NICs, Wi-Fi client isolation and carrier NAT all
  make host candidates fail in ways a LAN test will not show.

## Verification, end to end

```sh
# in packages/peer_coordinator
dart analyze lib test
dart test
dart compile js -o /tmp/web_check.js tool/web_safety_check.dart   # web safety

# in packages/webrtc_coordinator
dart test              # unit tests against the fake adapter
flutter test           # two-peer, on a real platform

# in packages/peer_coordinator/example
flutter test
```

Manual, once the transport runs: `dart run peer_coordinator:hub --host 0.0.0.0
--port 8080`, then two app instances on the RTC transport — one native, one
Chrome — and confirm messages cross while the hub shows only signalling and query
traffic.


## An issue encountered in the test chat app

Everything seemed to work, but 2 things 

```text
flutter: [WARNING] PeerCoordinator: [CONTROLLER-a297e6d3-db37-4b4e-b920-9c8420842161] Coordinator lost (coordinatorLeft); policy: endSession
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.joinAccept
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.topologyUpdate
2026-08-18 10:45:41.430 peer_coordinator_example[91834:5600589] error messaging the mach port for IMKCFRunLoopWakeUpReliable
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.topologyUpdate
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.joinOffer
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.joinAccept
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.topologyUpdate
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.joinAccept
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.topologyUpdate
flutter: [WARNING] PeerCoordinator: [CONTROLLER-89e69c54-81d8-452f-bbbc-20d2a22ad0f1] No handler for message type: CoordinationMessageType.topologyUpdate
```

and the macos built release version of the app just hung on close (the app UI disappeared, but it was still running), probably a resource not closed properly.
