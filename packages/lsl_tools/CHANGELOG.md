## 0.2.0

- New `receiveChunks(inlet, options)`, stream version of inlet samples.
- The latency in an LSL inlet's `ClockChain` does not include the wait/polling
  delay when using event driven mode.
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
