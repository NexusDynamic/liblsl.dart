## Unreleased

- `RtcMesh.releaseChannel` ends only this node's reading of the stream and
  tells the peer with a new `unsubscribe` signal; the channel closes once
  neither side reads it. It used to drop the peer's subscription and close
  the shared channel too, so a participant tearing down its role could
  close the connection the coordinator had just reopened to re-admit it.
  Peers on older versions ignore the new signal; the channel then lives
  until the connection closes.
- `RtcStream.addInlet` attaches to a channel that survived an earlier
  `removeInlet`, so reading again from that peer receives its messages.

## 0.2.3

- A link that closes on this side only (ICE failure, timeout) now tells the
  peer with a best-effort `bye`, so the peer drops its stale half and the
  same node uId can connect again (as `CoordinatorLossPolicy.rejoin` does).
- Requires `peer_coordinator` ^0.4.4.

## 0.2.2

- Requires `peer_coordinator` ^0.4.3.

## 0.2.1

- `test` constraint relaxed to `^1.30.0`, which resolves alongside `flutter_test`
- Data streams report their peers' clock-offset estimates through
  `clockSyncs` (`PeerClockOffsets.estimates`), as LSL streams do.
- Data streams relay source clocks (`sendDataAt`, `upstream`): a sample
  passed on from elsewhere keeps its origin's timestamp, and receivers get
  the `ClockChain` to read it by in `MessageTiming.upstream`.

## 0.2.0

- Fix hashing on JS

## 0.1.0

- Initial release: a peer-to-peer transport for `peer_coordinator` over
  WebRTC data channels, with the hub used only for discovery, election and
  signalling. Coordination is reliable and ordered; data channels can be
  unreliable and unordered. Ships no WebRTC implementation: supply an
  `RtcPeerAdapter` (`webrtc_coordinator_flutter` provides one), or use the
  in-process fake from `package:webrtc_coordinator/testing.dart` for tests.
