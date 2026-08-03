## Unreleased

### Fixed

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

### Fixed (leaks)

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

### Performance

- Sends no longer block on a round-trip acknowledgement from the outlet
  isolate. A pool of eight native sample buffers gives bounded backpressure:
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

### Changed

- **`LSLDataStream.sendData` and `sendDataTyped` now return `Future<void>`.**
  Awaiting is optional (existing fire-and-forget calls keep working) and gives
  backpressure when the send buffer pool is saturated.
- **Message metadata now holds raw values instead of strings**: `received_at`
  is a `DateTime` (was an ISO-8601 `String`); `lsl_timestamp` and
  `lsl_time_correction` remain `double`. Consumers reading `received_at` as a
  `String` must call `.toIso8601String()` themselves.
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
