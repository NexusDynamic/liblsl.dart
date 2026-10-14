## 1.0.0

- First version: the Lab Streaming Layer types and utilities that need no
  FFI, shared by `liblsl`, `lsl_tools`, `xdf` and the coordinators, and
  usable on the web.
  - `LSLChannelFormat` (with `byteWidth`, `isInteger`, `outletFormat` and
    `parse`), `LSLContentType`, `LSLStreamProperty`, `LSLChunk`,
    `LSLChunkTyped`, `LSLSample`, `LSLTimedSample`, `LSLTimedChunk`,
    `LSLBacklog`, `LSLTimeCorrection` (with `zero`), the `LSLException`
    family and `LSLApiConfig` (moved from `liblsl`, which re-exports them).
  - A value codec for every channel format (`readValues`, `writeValues`,
    `asFormat`, `typedListFor`, `sliceTyped`...): little-endian, exact for
    int64 where ints are 64-bit and to ±2^53 on the web (`exactInt64`).
  - `ClockHop`, `ClockChain`, `ClockModel`, `TimestampSmoother`,
    `LatencyWindow` and `ClockOffsetEstimate` (moved from
    `peer_coordinator`, which re-exports them).
  - The `LslBackend`/`LslInlet`/`LslOutlet` facade, `LslChunk` and the
    inlet and outlet options, and `receiveChunks` (moved from `lsl_tools`).
  - Polling: `ListenerRestartSchedule` and `TimeCorrectionSchedule` (moved
    from `liblsl_coordinator`), `drainInlet`, `pullCapacity`,
    `pollIntervalFor` and `runPreciseInterval`/`runPreciseIntervalAsync`.
  - Stream info XML: `buildInfoXml`, `infoField`, `channelsOf`.
