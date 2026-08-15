## 0.4.0+0

The coordination layer is now transport-neutral and lives in a new pure-Dart
package, `peer_coordinator`. `liblsl_coordinator` is the Lab Streaming Layer
transport for it, and re-exports the core so existing imports keep working.

Two other transports ship in `peer_coordinator`: an in-memory one for testing
and a WebSocket one (with a relay hub) that also runs in the browser.

### Breaking changes

- **The core moved to `package:peer_coordinator`.** Every library previously
  under `package:liblsl_coordinator/` — `framework.dart`, `config.dart`,
  `coordination.dart`, `data.dart`, `discovery.dart`, `interfaces.dart`,
  `network.dart`, `logging.dart` — is now a one-line re-export of its
  `peer_coordinator` counterpart. Existing imports continue to resolve
  unchanged; prefer importing from `peer_coordinator` in new code.
  `liblsl_coordinator` now depends on it.
- **`LSLCoordinationSession` is a thin subclass of `PeerSession`.** The session
  flow, election, heartbeat, membership and stream lifecycle are all in
  `PeerSession` now. Return types are narrowed covariantly, so
  `createDataStream`/`getDataStream` still hand back `LSLDataStream` and
  `transport` still returns `LSLTransport`. No call-site change expected.
- **`ITransportConfig` requires `createTransport()`.** Transport selection is a
  method on the config rather than a registry, so an application never
  compiles in a transport it does not name. Only affects custom transports.
- **`ITransport` gained `streamFactory` and `createDiscovery`, and lost
  `createStream`.** `createStream` had no callers. `ITransport` now also
  implements `IResourceManager`, which it did in practice already.
- **`NetworkStream` gained the lifecycle members that previously existed only
  on `LSLStreamMixin`**: `started`, `start`, `stop`, `createOutlet`,
  `recreateOutlet`, `addInlet`, `createInletsForNodes`, `updateNode`, plus
  default `pauseStream`/`resumeStream`/`flushStreams`/`destroyStream`. Callers
  no longer need a concrete LSL type to drive a stream.
- **`resume()` was split.** `IPausable.resume()` takes no arguments; the
  parameterised form is now `resumeWith({flushBeforeResume})`. The old
  widened `resume({flushBeforeResume})` could never be called through the base
  type.
- **`createResolvedInletsForStream` renamed to `createInletsForNodes`** and
  **`addInlet` now takes a `PeerHandle`**, not an `LSLStreamInfo`.
- **Discovery is typed.** `LslDiscovery` implements `IDiscovery`;
  `startDiscovery(predicate:)`/`stopDiscovery()` are now `start(query:)`/
  `stop()`, taking a `DiscoveryQuery` instead of an XPath string. The LSL
  transport compiles queries to XPath via `LslPredicateCompiler`, which emits
  byte-identical predicates (golden-tested). `LSLStreamInfoHelper`'s string
  builders remain for now.
- **Discovery events renamed.** `StreamDiscoveredEvent` is now
  `PeersDiscoveredEvent`, carrying `List<PeerHandle>` rather than
  `List<StreamInfoResource>`.
- **`Log.sendPort` is now `Log.forwardTo(callback)`** and
  `Log.logIsolateMessage` is `Log.replayRecord` (old names deprecated). Logging
  no longer imports `dart:isolate` or `dart:io`, so the core compiles for web.
  The default logger name changed from `LSLCoordinator` to `PeerCoordinator`.
- **Removed as unused:** `TransportStreamConfig` /
  `TransportCoordinationStreamConfig` (never implemented, and unusable — the
  field was dropped by `DataStreamConfigFactory.fromMap`, so per-stream options
  could never reach other nodes; put transport options on `ITransportConfig`),
  `IStartable`, `NullNode`, the `NetworkTopology`/`HierarchicalTopology`
  runtime classes and `TopologyType` (the *configs* remain), the `src/events.dart`
  `Event` hierarchy, and `IntMessageTypeMapping.minValue`/`maxValue` (never
  read, and `0x7FFFFFFFFFFFFFFF` cannot be represented in JavaScript).
- `CoordinationConfig.name` now defaults to `'peer_coordinator'`. It surfaces
  only as the `appId` node metadata and is not used in discovery.

### Fixed

- **Duplicate `createDataStream` leaked a live outlet.** Participants build
  their streams automatically on the coordinator's `createStream` command, so
  application code that also called `createDataStream` ran the setup path
  twice. Two concurrent `createOutlet()` calls both passed its null check (it
  awaited before assigning), both built an outlet, and the second overwrote the
  first. The orphan stayed published on the network with nothing referencing
  it — unreachable from `dispose()`, and indistinguishable from a teardown
  leak — while the second listen on the single-subscription outgoing controller
  threw `Bad state: Stream has already been listened to`.
  `createDataStream` is now idempotent and `createOutlet()` serialises on an
  in-flight future.
- **`createInletsForNodes` resolved once and threw** if any producer had not
  published yet. Producers come up independently, so in `allNodes` mode one
  node routinely looked for another that was not ready — a race the caller
  could not win. It now polls a continuous resolver until the deadline.
- **`createInletsForNodes` leaked every `LSLStreamInfo` it resolved but did not
  use.** Unmatched infos are destroyed.
- **Election's self-exclusion never excluded anything.** It emitted
  `not(starts-with(source_id, '<nodeId>'))`, but `source_id` begins with the
  *stream* name, so the clause was always true. Now excludes by node uId.
- **`randomRoll` was written under one metadata key and read under another**
  (`'random_roll'` vs `'randomRoll'`), so the value silently never arrived on
  the skip-election path. Both sides now use `PeerMetadataKeys`.
- **XPath predicate values were never quoted**, so an apostrophe in a session
  name or node id produced a malformed predicate that silently matched nothing.
- **An unpromoted node lost its identity across the wire.** `Node` always
  starts with `role: 'none'`, and `NodeFactory` returned `NullNode()` for that
  role, discarding the supplied config and generating a fresh `uId`.
- **`RuntimeTypeUID` cached `uId` in a `static Map<Type, String>`**, so every
  session, data stream and coordination stream in a process shared one
  identity. Harmless across processes, fatal for in-process multi-node use.
- **Unguarded `topologyConfig as HierarchicalTopologyConfig`** crashed election
  for any other topology type.
- **`PeerHandle` ownership is explicit.** Continuous discovery frees the
  previous cycle's native `lsl_streaminfo` pointers, so a handle still in use
  became a dangling pointer. `addInlet` now calls `take()` before touching a
  handle, which is also what unified the two call sites that previously
  differed.

### Added

- `peer_coordinator` — the transport-neutral core. Pure Dart, no `dart:io`,
  `dart:isolate` or `dart:ffi`; compiles to JavaScript
  (`tool/web_safety_check.dart` enforces this in CI).
- In-memory transport (`package:peer_coordinator/in_memory.dart`) for testing
  whole multi-node sessions with no sockets and no timing luck.
- WebSocket transport and relay hub
  (`package:peer_coordinator/websocket.dart`, `.../hub.dart`, or
  `dart run peer_coordinator:hub`). Control traffic is JSON; data samples use a
  binary frame the hub relays without parsing. On loopback at 60 Hz it measured
  p50 ~0.7 ms against LSL's ~6.1 ms, because LSL's figure at that rate is
  bounded by its polling interval rather than the network.
- `DiscoveryQuery` — a typed peer filter that relay transports evaluate
  directly and LSL compiles to XPath.
- Cross-transport conformance scenarios (`package:peer_coordinator/testing.dart`)
  covering every `StreamParticipationMode`. All five modes pass over in-memory,
  WebSocket and LSL.
- `DataStreamConfig.validateSample`, shared by every transport.
- A test suite for this package, where there was none: unit tests for the
  message/JSON contract, handlers and state; XPath goldens; and tagged LSL
  integration tests (`melos run test:lsl`).

### Notes

- LSL tests must run serially (`--concurrency=1`): they bind real sockets and
  resolve peers machine-wide, so concurrent files interfere. `melos run test`
  excludes them; `melos run test:lsl` runs them serially.
- Two behaviours are documented in tests rather than fixed, because changing
  them is a deliberate decision: a rejected node cannot distinguish rejection
  from a timeout (the handler's `StateError` is swallowed by the controller's
  log-only catch), and a full session re-offers and re-rejects a waiting node
  on every discovery cycle.

## 0.3.0+0

- `removeInlet` never actually removed or destroyed the inlet (the lazy
  `whereIndexed` iterable was never consumed), so removed sources kept
  delivering samples and leaking native inlets.
- Received samples could be tagged with another inlet's LSL time correction,
  because the correction index only advanced when a sample was present.
- Time corrections were never refreshed on the timer-based polling path (only
  in busy-wait mode), so `lsl_time_correction` stayed at its initial value.
- `LSLStreamMixin.create()` was a permanent no-op (`_created` was initialised
  to `true`), leaving `created` wrong for the stream's whole lifetime.
- The direct-mode (non-isolate) inlet polling timer was never cancellable and
  kept firing after the stream was disposed.
- `createInletForNode` compared a node UID against full LSL source IDs, so its
  duplicate check never matched and duplicate inlets could be created.
- `leave()` disposed the transport before the controller, while the controller
  still needed transport-owned discovery to announce leaving.
- A stopped, crashed, or exited outlet/inlet isolate left in-flight requests
  awaiting a response that could never arrive; they now fail with a
  `StateError` instead of hanging forever.
- Pause/flush work in the busy-wait inlet loop was not awaited and could
  interleave with polling.
- `StreamController`s in the isolate manager, LSL streams, and discovery are
  now closed on teardown (previously disabled because awaiting `close()` hung).
- The outlet `StreamInfo` handed to the outlet isolate is now destroyed when
  the worker stops, not only on outlet recreation.
- Worker-side `ReceivePort`s are closed and isolate log forwarding is stopped
  on worker shutdown, so isolates can exit rather than relying on `kill`.
- Event waits with no timeout (`waitForMinNodes`, `waitForUserMessage`,
  `_waitForPhase`) no longer leak their subscription; all waits now share one
  `waitForEvent` helper that always cancels.
- The session's stream-lifecycle subscription is cancelled on `dispose()`.
- Sends no longer block on a round-trip acknowledgement from the outlet
  isolate. A pool of eight native sample buffers gives backpressure, and
  a send only waits when every buffer is still in flight.
- Inlets are now drained (up to 100 samples per inlet per tick) instead of
  yielding a single sample per tick, which previously caused an unbounded
  backlog whenever the producer outpaced the poll interval. At 500 Hz on
  loopback this changes 79% sample loss and multi-second latency into zero
  loss at ~1.1 ms p50.
- Timer-based polling derives its interval from `sampleRate` (clamped to
  1–10 ms) rather than being hard-coded to 10 ms.
- Removed per-sample UUID generation, per-sample lock acquisition, per-sample
  channel type re-scanning, and per-sample ISO-8601 string formatting from the
  receive path.
- **`LSLDataStream.sendData` and `sendDataTyped` now return `Future<void>`.**
  Awaiting is optional (existing fire-and-forget calls keep working) and gives
  backpressure when the send buffer pool is saturated.
- **Message timing moved from the metadata map to a typed `MessageTiming`.**
  The `lsl_timestamp`, `lsl_time_correction`, `received_at` and `source_id`
  metadata keys are gone; read `message.timing` instead, whose fields are
  `sourceClock`, `clockOffset`, `receivedClock` and `sourceId`, with
  `transitSeconds` / `transitMicros` doing the clock-domain arithmetic for you.
  Nothing in the wild could have depended on the old keys — nothing read them
  and the values never reached a coordination-message consumer (see below).
- `LSLCoordinationSession.waitForUserMessage` now matches on the message
  *type* (the first argument to `sendUserMessage`) rather than an
  auto-generated message ID, which no caller could know — the method was
  previously unusable. It also matches participant messages and returns
  `UserMessageEvent`.
- `sendUserMessage`'s first parameter is renamed `messageId` → `messageType`
  to match what it actually is (positional; no call-site change needed).
- New `NodeJoinRejectedEvent` on the coordinator's event stream; the
  coordinator now clears its pending-join tracking when a join is rejected, so
  a rejected node can be re-offered a join if capacity frees up.

## 0.1.1+0

- Initial version.
