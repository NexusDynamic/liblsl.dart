# Transport Timing

`transport_timing` measures the timing of sample transfer between devices:
one-way latency, jitter, loss, and the difference and drift between the
clocks of the devices. It is run on every device of interest, each device
writes one log, and the logs are analysed together with
[`transport_timing_analysis`](../transport_timing_analysis)
([web app](https://nexusdynamic.org/liblsl.dart/transport_timing_analysis/)).
The guide [Validating timing in a lab](../../docs/validating-timing.md)
describes the procedure and the interpretation of the results.

Version [2.0.0](https://github.com/NexusDynamic/liblsl.dart/releases/tag/transport_timing-v2.0.0)
is available for Windows, macOS, Linux and Android
([all releases](https://github.com/NexusDynamic/liblsl.dart/releases?q=transport_timing&expanded=true)).

The application runs over each transport of
[`peer_coordinator`](../../packages/peer_coordinator), and over liblsl
directly:

| Transport | Path of the samples | Requirement |
| --- | --- | --- |
| LSL | LSL, through `liblsl_coordinator` | One local network with multicast |
| WebSocket hub | Through a relay | A hub (`dart run peer_coordinator:hub`) reachable by all devices |
| WebRTC | Peer to peer | The hub, for discovery and signalling |
| Raw LSL (a run option on any transport) | LSL outlets and inlets, without a coordinator | One local network with multicast |

## Running a test

1. Build the application in release mode and start it on each device
   (`flutter run --release`). Timings from debug builds are not meaningful.
2. Give each device a name, select the same session and transport on all
   devices, and connect. For WebSocket and WebRTC, start a hub first and
   enter its URL and secret.
3. The first device to connect becomes the coordinator. When every device
   appears in its list, configure the run on that device and start it.
   Every device takes part in the run and writes a log.
4. Share the logs from each device (the share button), or collect them from
   its downloads or documents folder: `tt_<run>_<device>.xdf`.
5. Open all logs of a run together in the analysis application, or run
   `dart run timing_core:analyse tt_*.xdf`.

Each device also shows a summary of its own log when a run ends. Every
received sample carries the timestamp of its sender, so the log of one
device contains the latency of everything that device received. The logs of
the other devices add their names and the exact number of samples they sent.

## What a run measures

Every device sends numbered samples at the chosen rate and logs when each
one it receives was sent (on the sender's clock) and received (on its own),
together with the transport's estimate of the difference between the two
clocks and how good that estimate is. Latency is
`received − (sent + offset)`.

No assumption is made about the clocks. The offset is supplied by the time
correction of LSL, or by the equivalent in `peer_coordinator` on the other
transports, and the report states its bound ("clock offset known to
±x ms"). A latency smaller than that bound is not resolved.

### Receive mode and polling

On a good network, the way a device receives samples determines most of the
measured latency. A receiver that polls sees a sample at its next poll, so
every latency includes a wait of between zero and one polling interval: half
the interval on average, with a spread of `interval / √12` that is unrelated
to the network. On loopback, raw LSL measures about 0.13 ms event-driven
and about 3.2 ms polled every 5 ms.

Each log records its receive mode and polling interval, and the report
states what polling adds, so that runs can be compared:

| Receive mode | Where it applies | Added delay |
| --- | --- | --- |
| event | WebSocket, WebRTC; LSL transport with "Event-driven receive"; raw LSL "Event-driven" | None: the sample is handled as it arrives |
| busy-wait | Raw LSL "Busy-wait" | None, at the cost of one CPU core per inlet |
| busy-wait | LSL transport with precise polling | Up to one sample period (0.1 to 10 ms) |
| polled | Raw LSL "Polled"; LSL transport without precise polling | Up to the polling interval |

Event-driven receive (`LSLInlet.sampleStream()` in liblsl,
`LSLTransportConfig.eventDrivenInlets` in `liblsl_coordinator`) gives each inlet an isolate that waits inside
`lsl_pull_sample`; liblsl wakes it when the sample is queued, and the
receive time is read as the call returns. This is the appropriate figure
for the latency of LSL on a given network.

For WebSocket and WebRTC the receive time is taken in the Dart handler, on
the main isolate, so it includes any time the handler waited behind other
work. The application should be otherwise idle during a run.

### Sending

Over the transport of the session, samples are sent from a timer, as an
application would send them, and the sender section of the report shows how
regular the sending was. Raw LSL sends from an isolate that busy-waits up to
each deadline, with three ways of pushing:

| Push mode | Mechanism |
| --- | --- |
| Sync push | `pushSampleSync`; liblsl queues the sample and its own thread writes it |
| Sync push, blocking socket writes | An outlet created with `LSLTransportOptions.syncBlocking`; the push writes to the socket of every consumer and returns when the operating system has the data |
| Async push | `pushSample` through the isolate of the outlet |

"Sweep raw LSL modes" runs every receive and send combination back to back
with the other settings unchanged.

### Interactive test

Touching the screen sends a sample, and every sample received, including
the device's own, flashes a square. The log contains the touch, the send,
the receive and the frame that showed the flash, so that the delays inside
the application can be separated from the transfer. With a force sensor on
the screen and a photodiode on the square, an external recorder times the
whole path.

## Platform notes

On Android the application requests the location and notification
permissions, on which the multicast discovery of LSL depends. On iOS, LSL
requires the multicast entitlement, which Apple grants per developer
account. The application keeps the screen awake, runs full screen on mobile
devices, and requests the highest refresh rate of the display.

## Tests

```bash
flutter test                 # three devices on an in-memory bus
flutter test --tags lsl      # two devices over real LSL on loopback; prints the reports
```
