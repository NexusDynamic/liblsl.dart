## 0.3.0

- Replays keep each stream's format and channels.
- Forwarding keeps the stream's format when its values are passed on
  unprocessed.
- int64 streams warn in a browser that values beyond ±2^53 are rounded.
- Requires `lsl_tools` ^0.3.0 (bridge protocol 3) and `signal_viewer`
  ^0.2.0.

## 0.2.1

- Requires `lsl_tools` ^0.2.1.

## 0.2.0

- Streams now use event-driven mode by default
- Stream details show how long samples were held before being handed on

## 0.1.0

- Initial version, extracted from hyprview 0.5.1: `LslProvider` (stream
  discovery, inlets, settings) and the `lsl` facade over liblsl.
