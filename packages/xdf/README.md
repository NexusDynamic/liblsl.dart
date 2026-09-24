# xdf

Read and write [XDF](https://github.com/sccn/xdf/wiki/Specifications)
(Extensible Data Format) recordings, the file format of LabRecorder and the
Lab Streaming Layer. Pure Dart; works on all platforms, including the web.

- `loadXdf(bytes)`: a whole file in memory, like pyxdf's `load_xdf`: clock
  synchronisation (robust fit, clock reset detection), jitter removal and
  effective rates, with pyxdf's algorithms and defaults. Tested against
  pyxdf 1.17.5 on the xdf-modules example files (see `test/fixtures`).
- `XdfFile.open(ByteSource)`: large files without loading them: one
  indexing pass builds summary pyramids per regular stream (from
  `signal_core`), so overviews, zooming and filtered windows are fast;
  markers and irregular streams are kept in memory. A stream without
  breaks gets exactly pyxdf's time stamps.
- `XdfWriter`: write files as data comes in (headers, samples, clock
  offsets, boundaries, footers), e.g. to record LSL streams.
- `readChunks`, `readSamples`: the raw chunks.

```dart
final rec = loadXdf(File('session.xdf').readAsBytesSync());
for (final s in rec.streams) {
  print('${s.info.name}: ${s.length} samples at ${s.effectiveRate} Hz');
}
```
