## 2.0.3

- Values are kept as recorded instead of as 32-bit floats.
- Requires `signal_viewer` ^0.2.0 and `timing_core` ^0.2.1.

## 2.0.2

- Add run summary statistics.
- The report can show the fitted clock offset or the latest estimate.
- A percentile is left out where there are too few samples for it.
- Logs are read and analysed off the main isolate.
- Updated to `timing_core` ^0.2.0 and `signal_viewer` ^0.1.2.

## 2.0.1

- Updated all dependencies

## 2.0.0

- Rebuilt as a signal_viewer provider
- Reads XDF run logs
- Updated Android Gradle Plugin
- Signed Android builds
