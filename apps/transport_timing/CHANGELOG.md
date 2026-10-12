## 2.0.2

- Updated to `liblsl` ^1.1.3.
- Updated to `timing_core` ^0.2.0.
- Disable share icon on Linux (shareplus doesn't support linux), the path
  of the recorded file is visible in the UI for each session entry.
- The raw LSL sweep runs every condition three times, and randomises the order.
- A run that fails on a device is listed among its results.
- Interactive test: touches are recorded from
  `PlatformDispatcher.onPointerDataPacket`, and include the OS reported
  timestamp.
- Sized buffers are used to avoid growing lists.


## 2.0.1

- Requires `liblsl` ^1.1.2.
- Requires `liblsl_coordinator` ^0.5.3.

## 2.0.0

- Rebuilt on peer_coordinator
- Run logs saved as XDF
- Option to receive event-driven on the LSL backend
- WebSocket loopback test
- Updated Android Gradle Plugin
- Signed Android builds
