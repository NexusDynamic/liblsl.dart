# Transport Timing

Measures what it costs to move a sample between devices: one-way latency,
jitter, loss, and how the devices' clocks differ and drift. Run it on every
device you care about, collect one log from each, and analyse them together
with [`transport_timing_analysis`](../transport_timing_analysis).

It runs over each backend of
[`peer_coordinator`](../../packages/peer_coordinator), and over liblsl
directly:

| Backend | Samples travel | Needs |
|---|---|---|
| LSL | LSL, through `liblsl_coordinator` | one LAN, multicast |
| WebSocket hub | through a relay | `dart run peer_coordinator:hub` reachable by all |
| WebRTC | peer to peer | the hub, for discovery and signalling |
| Raw LSL (a run option on any backend) | LSL outlets and inlets, no coordinator | one LAN, multicast |

## Running a test

1. Build in **release** mode and start the app on each device
   (`flutter run --release`). Debug builds work but their timings mean
   nothing.
2. Give each device a name, pick the same session and backend on all of
   them, and connect. For WebSocket and WebRTC, start a hub first and enter
   its URL and secret.
3. The first device in becomes the coordinator. When every device shows in
   its roster, set up the run there and start it. Every device runs it and
   writes a log.
4. Share the logs from each device (the share button), or collect them from
   its downloads or documents folder: `tt_<run>_<device>.ttlog`.
5. Open all of a run's logs together in the analysis app, or
   `dart run transport_timing_analysis:analyse *.ttlog`.

Each device also shows what its own log says as soon as a run ends. That is
already most of the picture: every received sample carries its sender's
timestamp, so a device's log has the latency of everything it received. The
other devices' logs add their names and the exact number they sent.

## What a run measures

Every device sends numbered samples at the chosen rate and logs when each
one it receives was sent (on the sender's clock) and received (on its own),
together with the transport's estimate of the difference between the two
clocks and how good that estimate is. Latency is
`received − (sent + offset)`.

Nothing is assumed about the clocks: LSL's time correction, or
`peer_coordinator`'s equivalent on the other transports, supplies the
offset, and the report says how far to trust it ("clock offset known to
±x ms"). A latency smaller than that bound is not resolved.

### Polling, and how to take it out

**How a device receives decides most of what you will see on a good
network.** A receiver that polls sees a sample at its next poll, so every
latency includes a wait of between zero and one poll interval: half the
interval on average, and a spread of `interval / √12` that has nothing to do
with the network. On loopback, raw LSL measures about 0.13 ms event-driven
and about 3.2 ms polled every 5 ms.

Each log records its receive mode and poll interval, and the report prints
what the polling adds, so runs can be compared:

| Receive mode | Where | What it adds |
|---|---|---|
| event | WebSocket, WebRTC; raw LSL "Event-driven" | nothing: handled as the sample arrives |
| busy-wait | raw LSL "Busy-wait" | nothing, at the cost of a core per inlet |
| busy-wait | LSL backend with precise polling | up to one sample period (0.1 to 10 ms) |
| polled | raw LSL "Polled", LSL backend without precise polling | up to the poll interval |

Raw LSL's event-driven mode gives each inlet an isolate that waits inside
`lsl_pull_sample`; liblsl wakes it when the sample is queued, and the
receive time is read as the call returns. That is the number to quote for
"what does LSL cost on this network".

For WebSocket and WebRTC the receive time is taken in the Dart handler, on
the main isolate, so it includes any time the handler waited behind other
work. Keep the app idle during a run.

### Sending

Over the session's backend, samples are sent from a timer, as an app would,
and the report's sender section shows how regular that was. Raw LSL sends
from an isolate that spins up to each deadline, and offers three ways to
push:

- **Sync push**: `pushSampleSync`; liblsl queues the sample and its own
  thread writes it.
- **Sync push, blocking socket writes**: an outlet created with
  `LSLTransportOptions.syncBlocking`; the push writes to every consumer's
  socket itself and returns when the OS has the data.
- **Async push**: `pushSample` through the outlet's isolate.

"Sweep raw LSL modes" runs every receive and send combination back to back
with the other settings unchanged.

### Interactive test

Touching the screen sends a sample; every sample received, the device's own
included, flashes a square. The log has the touch, the send, the receive and
the frame that showed the flash, so the delays inside the app can be
separated from the transfer. With a force sensor on the screen and a
photodiode on the square, an external recorder times the whole path.

## Platform notes

- **Android**: asks for location and notification permission, which LSL's
  multicast discovery depends on.
- **iOS**: LSL needs the multicast entitlement, which Apple grants per
  developer account.
- The app keeps the screen awake, goes full screen on mobile, and asks for
  the display's highest refresh rate.

## Tests

```bash
flutter test                 # three devices on an in-memory bus
flutter test --tags lsl      # two devices over real LSL on loopback; prints the reports
```
