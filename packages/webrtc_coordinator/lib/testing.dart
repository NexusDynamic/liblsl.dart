/// Test support for the WebRTC transport.
///
/// A regular library rather than something under `test/`, because
/// `webrtc_coordinator_flutter` needs the same fake to test its binding against
/// — the same reason `peer_coordinator` ships its conformance suite in `lib/`.
library;

export 'src/rtc/fake/fake_adapter.dart' show FakeRtcBus, FakeRtcPeerAdapter;
