# Guides

These guides describe how to carry out common tasks with the libraries and
applications in this repository. Each one states what is needed, gives the
procedure, and shows how to confirm the result. The code in each guide is
taken from an example in the repository that can be run as it is.

| Guide | Result |
| --- | --- |
| [Streaming data between two devices](./streaming-between-devices.md) | A stream of timestamped samples sent from one device and received on another with `liblsl` |
| [A coordinated experiment](./coordinated-experiment.md) | Several devices running one program, in which a coordinator starts a data stream on all of them and announces trials |
| [Validating timing in a lab](./validating-timing.md) | Measured latency, jitter, loss and clock drift between the devices of a lab, in a form that can be reported |
| [Sharing LSL streams over the network](../packages/lsl_tools/doc/relay.md) | LSL streams available in web browsers and across networks, through a WebSocket bridge or relay |

Reference documentation for each library is in its README, linked from the
[repository README](../README.md), and in its API documentation on pub.dev.
