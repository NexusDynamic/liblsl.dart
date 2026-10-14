## 0.2.0

- Recordings keep their values as recorded, unless the 32 bit pref is set.
- Replays send each stream exactly as recorded (`exactSamples`).
- Tabs of int64 streams warn when values cannot be shown exactly: beyond
  ±2^53, and in a browser.
- Requires `signal_viewer` ^0.2.0 and `xdf` ^0.2.0.

## 0.1.0

- Initial version: `XdfProvider` opens .xdf files, a tab per stream.
