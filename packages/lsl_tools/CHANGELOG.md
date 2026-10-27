## 0.3.0

- Bridge protocol 3 lets values travel in the stream's own channel format
  (float32, double64, int8/16/32/64, string) instead of always as float32,
  and every channel of a string stream reaches the outlets at the far end.
  `int64` is exact to 2^53 where ints are JavaScript numbers (web).
- Bridged, relayed and published streams become LSL outlets in their
  original format and channel count.
- `lsl replay` plays a recording with the original format and channel count.
- Recordings (`LslRecorder`) write values in the stream's own format.
- The facade (`LslBackend`, `LslInlet`, `LslOutlet`, `LslChunk`, the
  options), `receiveChunks` and the clock types moved to `lsl_core`, but
  are still exported from `lsl_tools`. `LslFormat`, `LslChannel`,
  `LslTimeCorrection` and `LslScope` are now `LSLChannelFormat`,
  `LSLChannel`, `LSLTimeCorrection` and `ResolveScope` (deprecated aliases
  remain).
- `LslOutlet.push` takes any numeric `TypedData` (converted to the outlet's
  format); `pushStrings` takes `channelCount` strings per sample.
- `LslChunk.typed`: the values in the stream's own format, if known.
- Outlets are created in `LslOutletSpec.format` (it was always float32 or
  string).
- Requires `liblsl` ^1.2.0, `peer_coordinator` ^0.4.3, `signal_core` ^0.2.0
  and `xdf` ^0.2.0.

## Unreleased

- `lsl cyton`: `--gain`, `--emg` (bipolar channels published as an EMG
  stream), `--markers` (the marker board mode, with markers typed on
  standard input and published as a markers stream) and `--sd`/`--sd-rate`
  (an SD card recording, up to 16 kHz).
- `lsl cyton-sd` converts an SD card recording of the Cyton to XDF.

## 0.2.1

- Requires `liblsl` ^1.1.2.

## 0.2.0

- Fixed: `LslRecorder` clock offset did not match standard `XDF`
- An event-driven inlet's latency is measured until the end of the chunk
- New `receiveChunks(inlet, options)`, stream version of inlet samples.
- The latency in an LSL inlet's `ClockChain` does not include the wait/polling
  delay when using event driven mode.
- `receiveChunks` uses `pullIntervalMs` for delivery, and slower streams will deliver immediately.
  pullInterval of `Duration.zero` will always deliver immediately.
- Bridge protocol 2; source timestamps are kept and a
  `ClockChain` gives offset, drift, error bound, latency
  and jitter per hop.
- The bridge's clock is measured as LSL measures an outlet's (bursts, the
  fastest round trip) with a drift fit
- Bridge inlets take `LslInletOptions`: corrected and dejittered time
  stamps by default, raw ones with `clockSync: false`.
- `lsl bridge` publishes a `BridgeTiming` stream and has `--stats`.
- New `LslDataStreamPump` and `DataStreamInlet` continue a chain through a
  `peer_coordinator` session (WebRTC).
- Monotinic clocks are now used instead of wall clocks where LSL is not available (e.g. web).

## 0.1.0

- Initial version, from signal_viewer_lsl: the lsl facade, LslRecorder,
  the LSL bridge, test outlets; and the `lsl` command line tool.
