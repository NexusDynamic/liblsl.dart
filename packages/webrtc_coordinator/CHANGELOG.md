## 0.1.0

- Initial release: a peer-to-peer transport for `peer_coordinator` over
  WebRTC data channels, with the hub used only for discovery, election and
  signalling. Coordination is reliable and ordered; data channels can be
  unreliable and unordered. Ships no WebRTC implementation: supply an
  `RtcPeerAdapter` (`webrtc_coordinator_flutter` provides one), or use the
  in-process fake from `package:webrtc_coordinator/testing.dart` for tests.
