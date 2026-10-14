## 0.2.1

- Uses `LSLChannelFormat`/`LSLChannel` for its XDF streams.
- Requires `xdf` ^0.2.0.

## 0.2.0

- Add health checks (e.g. a device missing)
- Within-device offsets are ignored (while there is a RTT, the offset is 
  not meaningful).
- If edges are lost, it is reported seperately
- `Summary` has `mad` and `iqr`, and indication of if there were sufficient
  samples to be reliable.
- `InteractiveReport.reportedToHeard`, from a `touch_os` marker: the time
  between the OS reported timestamp and the application timestamp.
- The text report gives additional information about the analysis.
- `analyse` is about four times as quick on long runs.

## 0.1.0

- Initial version: run logs as XDF files (`RunHeader`, `RunLogWriter`, `RunLog`),
  `analyse`, the `Report` model and the `analyse` command.
