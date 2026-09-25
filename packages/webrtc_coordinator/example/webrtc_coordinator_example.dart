// Two peers coordinating over the WebRTC transport, headless.
//
// A local hub handles discovery, election and signalling; the peers then talk
// over data channels. Here the channels come from the in-process fake adapter
// in `package:webrtc_coordinator/testing.dart`, so this runs with `dart run`.
// In a Flutter app, use `flutterWebrtcAdapterFactory` from
// `webrtc_coordinator_flutter` instead, and your own hub
// (`dart run peer_coordinator:hub`).
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/testing.dart' show startTestHub;
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

Future<void> main() async {
  final hub = await startTestHub(session: 'example');
  final bus = FakeRtcBus();

  CoordinationConfig configFor() => CoordinationConfig(
    name: 'webrtc_example',
    sessionConfig: CoordinationSessionConfig(
      name: 'example',
      maxNodes: 2,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 200),
      discoveryInterval: const Duration(milliseconds: 100),
      nodeTimeout: const Duration(seconds: 2),
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: 2,
    ),
    streamConfig: CoordinationStreamConfig(name: 'coordination'),
    transportConfig: RtcTransportConfig(
      hubUri: hub.uri,
      credentials: hub.credentials,
      adapterFactory: (selfNodeUId) =>
          FakeRtcPeerAdapter(selfKey: selfNodeUId, bus: bus),
    ),
  );

  // The lower roll wins the election, so 'alice' becomes the coordinator.
  final sessions = <PeerSession>[];
  for (final (name, roll) in [('alice', 0.1), ('bob', 0.9)]) {
    final session = PeerSession.create(
      configFor(),
      thisNodeConfig: NodeConfig(
        name: name,
        id: name,
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
        metadata: {PeerMetadataKeys.randomRoll: roll.toString()},
      ),
    );
    await session.initialize();
    await session.join(const Duration(seconds: 3));
    print(
      '$name joined as ${session.isCoordinator ? 'coordinator' : 'participant'}',
    );
    sessions.add(session);
  }

  final [alice, bob] = sessions;
  final received = bob.events.userCoordinationMessages.first;
  await alice.sendUserMessage('greeting', 'Hello over WebRTC', {});
  print('bob received: ${(await received).description}');

  for (final session in sessions.reversed) {
    await session.dispose();
  }
  await hub.close();
}
