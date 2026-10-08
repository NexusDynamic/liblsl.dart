# lsl_tools

[![Pub Version](https://img.shields.io/pub/v/lsl_tools)](https://pub.dev/packages/lsl_tools)

`lsl_tools` provides tools for Lab Streaming Layer (LSL) in pure Dart, and
the `lsl` command line tool built from them. The tools list streams, record
them to XDF, replay recordings, generate test streams, and carry streams
over a WebSocket to other networks and to web browsers.

| Component | Purpose |
| --- | --- |
| `lsl` | A facade over `package:liblsl` for discovery, inlets and outlets. It can be imported on the web, where `lsl.supported` is false |
| `LslRecorder` | Records streams to XDF in the same way as LabRecorder (raw time stamps, clock offsets, footers) |
| `LslBridgeServer`, `LslBridgeClient`, `LslBridgeRepublisher` | Carry LSL streams over a WebSocket, across networks that multicast does not reach and to and from browsers. The server can also relay streams between its clients, and the client runs in browsers |
| `LslSignalGenerator`, `LslMarkerSender` | Test outlets |

The [bridge and relay guide](doc/relay.md), also published at
<https://nexusdynamic.org/liblsl.dart/relay.html>, describes how to set up a
bridge or relay.

[API documentation](https://pub.dev/documentation/lsl_tools/latest/)

## Installation

```bash
dart pub add lsl_tools
```

## The `lsl` command line tool

Prebuilt bundles are attached to each
[`lsl_viewer` release](https://github.com/NexusDynamic/liblsl.dart/releases?q=lsl_viewer&expanded=true)
as `lsl-cli-<version>-<os>`. The tool is `bin/lsl`; the `lib/` directory,
which holds liblsl, must stay next to it. From a clone of the repository the
tool is run with `dart run lsl_tools:lsl …`, and `dart build cli` produces
the same bundle.

```sh
lsl list [--wait 2]                              # streams on the network
lsl info EEG                                     # full XML and clock offset
lsl record session.xdf -s EEG -s Markers [-d 60] # Ctrl-C stops
lsl replay session.xdf [--loop]                  # an XDF file as LSL streams
lsl generate -c 8 -r 500 [-f 10] [--name --type] # a test stream
lsl cyton [/dev/ttyUSB0]                         # OpenBCI Cyton (+ Daisy)

# Across networks and to browsers (see doc/relay.md)
lsl share [-s EEG] [--token t] [-p 8765] [--host 0.0.0.0]
          [--accept [--no-local-outlets]] [--rescan 5] [--allow-origin https://…]
lsl relay [--token t] [-p 8765] [--host 127.0.0.1] [--allow-origin …]
lsl bridge ws://host:8765 [-s EEG] [--token t] [--suffix " (remote)"]
lsl publish wss://relay.example.org [-s EEG] [--token t] [--rescan 5]
```

| Command | Purpose |
| --- | --- |
| `share` | Shares LSL streams from here over a WebSocket. With `--accept`, clients can publish streams, which go to the other clients and to LSL here. |
| `relay` | Passes streams between WebSocket clients only. It requires no LSL and can run on a server. |
| `bridge` | Publishes a bridge's streams as LSL streams here, and follows them as they come and go. |
| `publish` | Publishes LSL streams from here on a bridge or relay that accepts them, connecting out. |

`-s` takes names or types, and `*` is a wildcard. `--peer <address>`
(before the command) looks for streams on computers that multicast does not
reach.
`lsl help <command>` lists every option.

## From Dart

```dart
import 'package:lsl_tools/lsl_tools.dart';

// A relay on port 8765 that needs no LSL.
final relay = await LslBridgeServer.start(
  const [],
  acceptPublish: true,
  localOutlets: false,
  token: 'secret',
);
relay.onChange.listen((_) => print('${relay.clientCount} connected'));

// A client (also in a browser): view a stream, publish one.
final client = await LslBridgeClient.connect(
  Uri.parse('ws://localhost:8765'),
  token: 'secret',
);
final outlet = await client.publish(
  const LslOutletSpec(name: 'Mine', type: 'EEG', channelCount: 2, rate: 250,
      sourceId: 'mine'),
);
```

The wire protocol is documented in `lib/src/bridge/protocol.dart`.
