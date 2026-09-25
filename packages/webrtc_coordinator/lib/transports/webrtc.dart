/// The WebRTC transport for `peer_coordinator`.
///
/// Import this alongside `package:peer_coordinator/peer_coordinator.dart` to
/// coordinate over direct peer-to-peer data channels instead of a relay. The
/// hub is still needed — for discovery and for carrying signalling — but it is
/// off the data path.
///
/// This package is pure Dart and ships no WebRTC implementation. Supply an
/// [RtcPeerAdapter]: `webrtc_coordinator_flutter` provides one backed by
/// `flutter_webrtc`, and `package:webrtc_coordinator/testing.dart` provides a
/// fake for tests.
library;

export '../src/rtc/rtc_adapter.dart'
    show
        RtcPeerAdapter,
        RtcPeerLink,
        RtcChannel,
        RtcLinkState,
        rtcChannelIdFor,
        coordinationChannelName,
        coordinationChannelId,
        reservedChannelIds,
        maxChannelId;
export '../src/rtc/rtc_mesh.dart' show RtcChannelEvent, RtcMesh;
export '../src/rtc/rtc_signal.dart' show RtcSignal, RtcSignalKind;
export '../src/streams/rtc_stream.dart'
    show
        RtcCoordinationStream,
        RtcDataStream,
        RtcNetworkStreamFactory,
        RtcStreamMixin;
export '../src/transport/rtc_transport.dart'
    show RtcAdapterFactory, RtcTransport, RtcTransportConfig;
