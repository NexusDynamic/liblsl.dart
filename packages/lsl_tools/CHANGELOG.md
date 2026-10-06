## Unreleased

- Bridge protocol 2 (not compatible with 1; older clients are refused):
  time stamps cross a bridge or relay as their origin stamped them, with a
  `ClockChain` beside them (per hop: offset, drift, error bound, latency
  and jitter).
- The bridge's clock is measured as LSL measures an outlet's (bursts, the
  fastest round trip) with a drift fit, instead of one ping every 2 s.
- Bridge inlets take `LslInletOptions`: corrected and dejittered time
  stamps by default, raw ones with `clockSync: false`.
- New `LslInlet.timeCorrectionEx()` and `chain()`, `LslChunk.received`,
  `LslBridgeClient.link` (replaces `offset`), `BridgeOutlet.upstream`,
  `LslRecorder.fromInlets`.
- `lsl bridge` publishes a `BridgeTiming` stream and has `--stats`.
- New `LslDataStreamPump` and `DataStreamInlet` continue a chain through a
  `peer_coordinator` session (WebRTC).
- Without LSL (web, a relay) the clock is now steady instead of the wall
  clock.

## 0.1.0

- Initial version, from signal_viewer_lsl: the lsl facade, LslRecorder,
  the LSL bridge, test outlets; and the `lsl` command line tool.
