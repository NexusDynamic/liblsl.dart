# lsl_tools

Lab Streaming Layer tools in pure Dart, and the `lsl` command line tool:
list, record to XDF, share across networks, bridge, relay, replay and
generate LSL streams.

- **`lsl`:** a facade over `package:liblsl` that is safe to import on the
  web, where `lsl.supported` is false. It covers discovery, inlets and
  outlets.
- **`LslRecorder`:** records streams to XDF as LabRecorder does (raw time
  stamps, clock offsets, footers).
- **`LslBridgeServer`, `LslBridgeClient`, `LslBridgeRepublisher`:** carry
  LSL streams over a WebSocket, across networks multicast doesn't reach and
  to and from browsers. The server can also relay streams between its
  clients. The client runs in browsers too.
- **`LslSignalGenerator`, `LslMarkerSender`:** test outlets.

**Setting up a bridge or relay:** see [doc/relay.md](doc/relay.md), also
published at <https://nexusdynamic.org/liblsl.dart/relay.html>.

## The `lsl` command line tool

Prebuilt bundles are attached to each
[`lsl_viewer` release](https://github.com/NexusDynamic/liblsl.dart/releases?q=lsl_viewer&expanded=true)
as `lsl-cli-<version>-<os>`. Run `bin/lsl` and keep `lib/`, which holds
liblsl, next to it. From a clone, use `dart run lsl_tools:lsl …`, or
`dart build cli` for the same bundle.

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

| Command | Does |
| --- | --- |
| `share` | Shares LSL streams from here over a WebSocket. With `--accept`, clients can publish streams, which go to the other clients and to LSL here. |
| `relay` | Passes streams between WebSocket clients only. It needs no LSL, e.g. on a server. |
| `bridge` | Publishes a bridge's streams as LSL streams here, and follows them as they come and go. |
| `publish` | Publishes LSL streams from here on a bridge or relay that accepts them, connecting out. |

`-s` takes names or types, and `*` is a wildcard. `--peer <address>`
(before the command) looks for streams on computers multicast doesn't reach.
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
