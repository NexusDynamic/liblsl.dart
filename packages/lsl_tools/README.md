# lsl_tools

Lab Streaming Layer tools in pure Dart, and the `lsl` command line tool.

- `lsl`: a facade over `package:liblsl` that is safe to import on the web
  (where `lsl.supported` is false): discovery, inlets, outlets.
- `LslRecorder`: record streams to XDF as LabRecorder does (raw time
  stamps, clock offsets, footers).
- `LslBridgeServer` / `LslBridgeClient`: share streams over a WebSocket,
  across networks multicast does not reach (the client also runs in
  browsers).
- `LslSignalGenerator`, `LslMarkerSender`: test outlets.

## lsl

```sh
dart run lsl_tools:lsl list
dart run lsl_tools:lsl info EEG
dart run lsl_tools:lsl record session.xdf -s EEG -s Markers   # Ctrl-C stops
dart run lsl_tools:lsl share --port 8765 --token secret      # on the lab network
dart run lsl_tools:lsl bridge ws://lab-pc:8765 --token secret # elsewhere
dart run lsl_tools:lsl replay session.xdf --loop
dart run lsl_tools:lsl generate -c 8 -r 500
```

`--peer <address>` (before the command) looks for streams on computers
multicast does not reach. `dart compile exe bin/lsl.dart` makes a
standalone program (liblsl is built by the liblsl package's build hook).
