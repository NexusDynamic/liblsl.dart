## 0.3.0

- Requires `lsl_tools` ^0.3.0 (bridge protocol 3: values keep their
  format; `LslOutlet.push` takes any numeric `TypedData`).

## 0.2.1

- Requires `lsl_tools` ^0.2.1.

## 0.2.0

- Streams now use event-driven mode by default
- Stream details show how long samples were held before being handed on

## 0.1.0

- Initial version, extracted from hyprview 0.5.1: `LslProvider` (stream
  discovery, inlets, settings) and the `lsl` facade over liblsl.
