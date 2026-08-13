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
