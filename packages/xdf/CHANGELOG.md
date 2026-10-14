## 0.2.0

- Values are no longer reduced to 32-bit floats: `XdfFile` keeps them as
  recorded (`XdfFileOptions.precision`, `SamplePrecision.exact` by
  default), and `XdfEvents.channels` is `List<List<double>>`.
- `XdfFile.exactSamples` (also on `XdfRecordingSource`): a stream's
  samples over a time range in their own format (an `Int64List` for int64)
  with every channel of a string stream, for replaying and exporting.
- `XdfStreamView.roundedValues`: whether some int64 values are beyond what
  a double holds (±2^53), so views of them are rounded.
- int64 values are read and written exactly where ints are 64-bit;
  `XdfWriter.writeSamples` takes any numbers (`List<num>`).
- `XdfFormat` and `XdfChannel` are now `lsl_core`'s `LSLChannelFormat` and
  `LSLChannel` (deprecated aliases remain; `XdfChannel`'s label is now
  positional). Stream headers are read and built with `lsl_core`.
- Requires `signal_core` ^0.2.0.

## 0.1.1

- Bump `xml` to `^7.1.0`

## 0.1.0

- Initial version: `loadXdf` (pyxdf-compatible), `XdfFile` (indexed large
  files on `signal_core`), `XdfWriter`, and the chunk readers.
