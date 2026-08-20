## 0.3.1

- New `ClockSyncSample`: one clock-offset estimate for one peer — `offset`,
  `uncertainty` (full probe RTT, so the ± bound is `bound`), `remoteTime` (the
  peer's own clock when the estimate was taken), `receivedClock`, and
  `clockReset`. Exposed on `NetworkStream.clockSyncs`, which defaults to an
  empty broadcast stream so transports that estimate no offsets need no change.

  Complements `MessageTiming` rather than duplicating it: `MessageTiming`
  answers "when did *this* message arrive", `ClockSyncSample` answers "how well
  do the two clocks agree right now, and how is that changing". The
  `(remoteTime, offset)` pairs are what make drift fittable; an offset alone is
  not. And because the estimates arrive on their own cadence, a stream that
  carries no traffic for a while no longer leaves a hole in the record.

## 0.3.0

Defines what happens when the coordinator goes away. Previously nothing did: the
liveness sweep ran on the coordinator only, so a participant whose coordinator
had gone kept heartbeating and publishing into a stream with no consumer,
indefinitely and silently, and there was no way for a departing coordinator to
say it was leaving.

### Behaviour changes

- **A session now ends when its coordinator does.** New
  `CoordinationSessionConfig.coordinatorLossPolicy`, defaulting to
  `CoordinatorLossPolicy.endSession`: the node stops its timers, drops the
  topology, and refuses further sends. `CoordinatorLossPolicy.reelect` instead
  has the survivors re-elect between themselves; `CoordinatorLossPolicy.remainOpen`
  is the previous behaviour, for applications that drive their own recovery.

  This is the breaking change in this release. Anything relying on a session
  outliving its coordinator must now say `remainOpen`.

- **Sends after a session ends throw `StateError`.** `sendUserMessage`,
  `createStream` and `startStream` fail loudly rather than publishing into a
  stream nobody is reading.

- **A departing coordinator announces it.** New
  `CoordinationMessageType.sessionEnd` / `SessionEndMessage`, the counterpart to
  the participant-only `nodeLeaving`. Survivors learn within a round trip instead
  of waiting out `nodeTimeout`. It is accepted in any phase — a node still
  handshaking is the one that most needs to hear it — and only from the node that
  actually holds the coordinator role.

- **An evicted node is told it was evicted.** The timeout sweep sends
  `SessionEndMessage(evicted)` to the node it is dropping, best effort.

- **New `SessionEndedEvent` and `events.sessionEnded`**, carrying a
  `SessionEndReason` (`coordinatorLeft`, `coordinatorTimedOut`,
  `coordinatorTransportLost`, `evicted`) and the policy applied. Emitted under
  every policy, so there is one place to listen.

### WebSocket protocol

- **`wsProtocolVersion` is now 2**, adding `WsControl.signal`: an opaque payload
  the hub forwards verbatim to one named endpoint, checking only that the sender
  owns the `from` endpoint. It is the hub's only unicast and the only frame whose
  contents it never inspects.

  This exists so a peer-to-peer transport can use this hub for discovery and
  connection setup — WebRTC offer/answer/candidate exchange — while its data
  never touches the hub. That exchange cannot ride the coordination stream,
  because the coordination stream is what is being established.

  `WsFrame.decode` rejects unknown versions rather than guessing, so **a hub and
  its clients must be deployed together.** Client side: `WsConnection.sendSignal`
  and `WsConnection.signals`, plus the exported `WsSignal`.

### Fixes

- **The node-timeout sweep no longer spins.** Its period was
  `Duration(seconds: nodeTimeout.inSeconds ~/ 2)`, which truncates to zero for
  any timeout under two seconds — a periodic timer firing every event-loop turn.
  Computed in microseconds now.

- **A failed *join* no longer promotes the node to coordinator.** Election
  wrapped both discovery and role setup in one `catch`, so a participant that
  could not reach its coordinator became one instead. In a re-election that is
  how two survivors both take the role and split the session. Only the discovery
  call is caught now.

- **Departure notices reach the wire.** `announceLeaving` enqueued onto the
  handler's outgoing stream, which is drained by a listener on a microtask, and
  the stream was disposed on the next line — `WsStreamMixin.sendMessage` drops
  silently once disposed. Departures are now sent directly and awaited before
  teardown.

- **Heartbeat entries are cleared for nodes that never joined.** The clear sat
  inside the "was it in the topology?" branch, so an entry with no matching node
  survived every removal and was re-reported stale on every tick, re-broadcasting
  the topology each time.

- **`CoordinationSessionConfig.hashCode` and `==` no longer recurse.** `id` is
  derived from `hashCode`, and `hashCode` hashed `id`; either would have
  overflowed the stack. Nothing called them, which is why it went unnoticed.

- **`copyWith` and `fromMap` stopped dropping fields.** `copyWith` reset
  `clockSyncConfig` to the default; `fromMap` dropped `discoveryInterval` and
  `consumeCoordinationStreamAsCoordinator`.

## 0.2.0

Fixes a stream lifecycle race in which a `startStream` command could overtake
the `createStream` it belonged to, leaving a participant holding a stream it
never started while the coordinator believed it was running.

### Behaviour changes

- **A `coordinatorOnly` `createDataStream` now waits for its consumers.**
  Creation previously waited only for *producers*, and a `coordinatorOnly`
  stream has none — so the coordinator returned immediately and callers that
  issue `startStream` next (the normal pattern) broadcast a start command
  milliseconds later, while participants still needed the best part of a second
  to resolve the outlet and build an inlet. Creation now completes only once
  every consumer has acked, which makes create-then-start ordering a guarantee
  rather than a hope.

  This adds roughly one participant's inlet-build time to each `coordinatorOnly`
  stream creation. Unlike the producers wait, a consumer that does not ack
  within the timeout is logged at `severe` and creation continues: the outlet is
  valid regardless, and late consumers can still attach off their own
  `streamReady`.

- **`getDataStream` waits for an in-flight create instead of throwing.** The
  stream lock only covers registration, not the outlet and inlet wiring that
  follows, so a lookup landing in that window was told the stream did not exist.
  It now queues behind the create. It still throws `ArgumentError` for a stream
  nobody is creating.

- **Concurrent `createDataStream` calls for one name share a single setup.**
  The second call used to find nothing registered, fall through, and re-run the
  wiring on the stream the first had just registered — calling `createOutlet()`
  on a stream that already had one.

- **A `startStream` for a stream that does not exist logs `severe`, not
  `warning`.** Nothing retries it, so the failure surfaces here or not at all.

### Internal

- `_waitForParticipantStreamsReady` is replaced by `_StreamReadyAcks`, which
  begins collecting acks when it is constructed rather than when it is awaited.
  The previous wait was built on the forward-only `waitForEvent` and was reached
  only after the outlet existed, so an ack from a fast participant could land in
  the gap and be missed — costing the full timeout for a message already sent.
