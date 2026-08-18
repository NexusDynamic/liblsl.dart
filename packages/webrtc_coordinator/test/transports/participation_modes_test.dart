/// The acceptance gate for the WebRTC transport.
///
/// `runParticipationScenarios` is the same suite `peer_coordinator` runs
/// against its in-memory and WebSocket transports. A participation mode is a
/// property of the coordination layer, not of how bytes move, so anything that
/// passes there and fails here is a transport bug — which is exactly what makes
/// it worth running against a transport whose routing table is local rather
/// than in the hub.
///
/// Everything below the adapter seam is the fake: real ICE, real SDP and real
/// SCTP are only exercised on a device, by `webrtc_coordinator_flutter`.
@Tags(['integration'])
library;

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/testing.dart';
import 'package:test/test.dart';
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

class _RtcHarness extends ParticipationHarness {
  CoordinationHub? _hub;
  FakeRtcBus? _bus;

  @override
  String get name => 'webrtc (fake adapter)';

  @override
  Duration get joinTimeout => const Duration(seconds: 2);

  @override
  Duration get settleTimeout => const Duration(seconds: 1);

  @override
  Future<void> setUp() async {
    // A real hub: discovery, election queries and signalling all still go
    // through it. Only the data does not.
    _hub = await CoordinationHub.serve();
    _bus = FakeRtcBus();
  }

  @override
  Future<void> tearDown() async {
    await _hub?.close();
    _hub = null;
    _bus = null;
  }

  @override
  ITransportConfig transportConfigFor(int nodeIndex) {
    final bus = _bus!;
    return RtcTransportConfig(
      hubUri: Uri.parse('ws://127.0.0.1:${_hub!.port}'),
      adapterFactory: (selfNodeUId) =>
          FakeRtcPeerAdapter(selfKey: selfNodeUId, bus: bus),
    );
  }
}

void main() {
  runParticipationScenarios(_RtcHarness());
}
