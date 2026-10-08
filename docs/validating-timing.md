# Validating timing in a lab

This guide measures how long samples take to travel between the devices of
a lab, how regular that time is, how many samples are lost, and how the
clocks of the devices differ and drift. It uses the
[`transport_timing`](../apps/transport_timing) application to run the test
and [`transport_timing_analysis`](../apps/transport_timing_analysis) to
read the results. At the end there is one report covering every pair of
devices, which can be quoted in a methods section.

The procedure follows the documentation of the two applications. It has not
been run end to end for this guide, which requires several devices.

## Requirements

`transport_timing` is installed on every device that will take part in the
experiment, from its
[release page](https://github.com/NexusDynamic/liblsl.dart/releases?q=transport_timing&expanded=true)
(Windows, macOS, Linux and Android) or built from source in release mode
with `flutter run --release`. Timings from debug builds are not meaningful.

The network requirement depends on the transport under test:

| Transport | Requirement |
| --- | --- |
| LSL | One local network that permits multicast |
| WebSocket hub | A hub reachable by all devices, started with `dart run peer_coordinator:hub` |
| WebRTC | The same hub, used for discovery and signalling |

The test should be run on the network, devices and transport that the
experiment will use, since the results apply to that configuration.

## Procedure

1. Start the application on each device and give each device a name.
2. Select the same session and the same transport on all devices and
   connect. For WebSocket and WebRTC, enter the address and secret of the
   hub.
3. The first device to connect becomes the coordinator. When all devices
   appear in its list, configure the run on that device and start it. Every
   device takes part in the run and writes a log.
4. Collect the log from each device with the share button, or from the
   downloads or documents folder of the device. The files are named
   `tt_<run>_<device>.xdf`.
5. Open all logs of the run together in the
   [analysis web app](https://nexusdynamic.org/liblsl.dart/transport_timing_analysis/)
   or the desktop application, and open the report from the toolbar.

The devices should be otherwise idle during a run.

The report is also available without the application:

```bash
dart run timing_core:analyse tt_*.xdf
dart run timing_core:analyse --json tt_*.xdf
```

## What is measured

During a run every device sends numbered samples at the selected rate. For
each sample it receives, a device logs when the sample was sent, on the
sender's clock, and when it was received, on its own clock, together with
the estimated offset between the two clocks and the quality of that
estimate. The latency of a sample is

```text
latency = received − (sent + offset)
```

The report has one row for each sender and receiver:

| Quantity | Meaning |
| --- | --- |
| Latency | Percentiles of the latency, computed with the offset current at arrival and with an offset fitted over the whole run |
| Clock bound | Half the round-trip time of the measurements behind the offset. The offset, and therefore the latency, is known to within this value |
| Loss, duplicates, reordering | Derived from the sequence numbers of the samples |
| Send and receive intervals | The regularity of sending and receiving |
| Clock | The offset at the start and end of the run, and the drift in parts per million |
| Polling | The interval at which the receiver polls, where it does |

## Interpreting the results

The clock bound limits the resolution of the measurement. A latency smaller
than the bound cannot be distinguished from zero, and slightly negative
latencies occur for the same reason. They are part of the measurement and
are kept in the report.

The receive mode determines much of the latency on a good network. A
receiver that polls sees a sample at its next poll, so each latency
includes a wait of between zero and one polling interval, which adds half
the interval to the mean. The report states the receive mode and the
polling interval of each log. Runs are comparable when their receive modes
match.

The timestamp of a sample is taken when the application sends it. The
latency therefore covers the sending path, the network and the receiving
path. It excludes delays before sending, such as those of an input device,
and delays after receiving, such as rendering on a display. The interactive
test in `transport_timing`, together with external sensors, measures that
complete path; see the
[`transport_timing` README](../apps/transport_timing/README.md#interactive-test).

Drift is the rate at which two clocks move apart, typically tens of parts
per million, which is tens of microseconds per second. It matters for long
recordings in which timestamps from different devices are compared.

## Reporting

A description of the timing of a multi-device experiment can state the
transport and receive mode, the devices and network, the sampling rate and
duration of the test, the median and upper percentiles of latency for each
pair of devices, the clock bound, the proportion of lost samples, and the
drift. The report can be copied from the analysis application as text or
JSON, and the logs are ordinary XDF files that can be archived with the
data of the experiment.

## Further reading

The [`timing_core` README](../packages/timing_core/README.md) specifies the
log format and the analysis. The
[`transport_timing` README](../apps/transport_timing/README.md) describes
the run options, including the raw LSL modes.
