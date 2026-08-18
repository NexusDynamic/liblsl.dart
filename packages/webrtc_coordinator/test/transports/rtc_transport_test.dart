/// The claims this transport exists to make, pinned as tests.
///
/// `participation_modes_test.dart` proves the transport is contract-correct —
/// that it behaves like the other two. This file proves it is *different* from
/// them in the ways that were the point: the hub carries no data, a released
/// inlet releases a real connection, and a data stream can ask for delivery no
/// relay can offer.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:test/test.dart';
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

void main() {
  late CoordinationHub hub;
  late FakeRtcBus bus;
  late String runId;
  late String sessionName;
  late String coordinationStreamName;
  late List<PeerSession> sessions;
  var runCounter = 0;

  setUp(() async {
    hub = await CoordinationHub.serve();
    bus = FakeRtcBus();
    runId = '${DateTime.now().microsecondsSinceEpoch}-${runCounter++}';
    sessionName = 'RtcSession-$runId';
    coordinationStreamName = 'coordination-$runId';
    sessions = [];
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      try {
        await session.leave();
      } catch (e) {
        printOnFailure('teardown: leave() threw: $e');
      }
      try {
        await session.dispose();
      } catch (e) {
        printOnFailure('teardown: dispose() threw: $e');
      }
    }
    sessions = [];
    await hub.close();
  });

  CoordinationConfig configFor({
    bool dataOrdered = true,
    int? dataMaxRetransmits,
  }) => CoordinationConfig(
    name: 'rtc_transport_test',
    sessionConfig: CoordinationSessionConfig(
      name: sessionName,
      maxNodes: 2,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 100),
      discoveryInterval: const Duration(milliseconds: 50),
      nodeTimeout: const Duration(milliseconds: 800),
      consumeCoordinationStreamAsCoordinator: false,
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: 2,
    ),
    streamConfig: CoordinationStreamConfig(name: coordinationStreamName),
    transportConfig: RtcTransportConfig(
      hubUri: Uri.parse('ws://127.0.0.1:${hub.port}'),
      adapterFactory: (selfNodeUId) =>
          FakeRtcPeerAdapter(selfKey: selfNodeUId, bus: bus),
      dataOrdered: dataOrdered,
      dataMaxRetransmits: dataMaxRetransmits,
    ),
  );

  /// Builds a coordinator and one participant, both joined.
  Future<List<PeerSession>> buildPair({
    bool dataOrdered = true,
    int? dataMaxRetransmits,
  }) async {
    const labels = ['coordinator', 'participant'];
    const rolls = [0.1, 0.9];
    for (var i = 0; i < labels.length; i++) {
      final session = PeerSession.create(
        configFor(
          dataOrdered: dataOrdered,
          dataMaxRetransmits: dataMaxRetransmits,
        ),
        thisNodeConfig: NodeConfig(
          name: labels[i],
          id: '${labels[i]}-$runId',
          capabilities: {
            NodeCapability.coordinator,
            NodeCapability.participant,
          },
          metadata: {PeerMetadataKeys.randomRoll: rolls[i].toString()},
        ),
      );
      sessions.add(session);
      await session.initialize();
      await session.join(const Duration(seconds: 2));
    }
    await sessions.first.waitForMinNodes(
      2,
      timeout: const Duration(seconds: 10),
    );
    expect(sessions.first.isCoordinator, isTrue);
    return sessions;
  }

  /// Runs one data stream to completion, returning what each node received.
  Future<List<List<List<double>>>> exchange(
    List<PeerSession> peers,
    String streamName, {
    int samplesEach = 5,
  }) async {
    final config = DataStreamConfig(
      name: streamName,
      channels: 2,
      sampleRate: 50.0,
      dataType: StreamDataType.double64,
      participationMode: StreamParticipationMode.allNodes,
    );

    final received = [for (var i = 0; i < peers.length; i++) <List<double>>[]];
    final streams = <DataStream>[];
    final subscriptions = <StreamSubscription<void>>[];

    streams.add(await peers.first.createDataStream(config));
    await peers.first.startStream(streamName);
    for (var i = 1; i < peers.length; i++) {
      streams.add(await peers[i].getDataStream(streamName));
    }
    for (var i = 0; i < peers.length; i++) {
      final index = i;
      subscriptions.add(
        streams[i].inbox.listen(
          (m) => received[index].add(m.data.cast<double>().toList()),
        ),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (var s = 0; s < samplesEach; s++) {
      for (var i = 0; i < peers.length; i++) {
        await streams[i].sendData([i.toDouble(), s.toDouble()]);
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));

    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    return received;
  }

  test('the hub carries signalling and discovery, and no data', () async {
    final peers = await buildPair();
    final streamName = 'Direct-$runId';
    final received = await exchange(peers, streamName);

    // Data really did cross.
    expect(
      received[0].map((s) => s[0].toInt()).toSet(),
      containsAll(<int>[0, 1]),
      reason: 'the coordinator should have seen both senders',
    );
    expect(
      received[1].map((s) => s[0].toInt()).toSet(),
      containsAll(<int>[0, 1]),
      reason: 'the participant should have seen both senders',
    );

    // And the hub could not have relayed a byte of it. `subscribersFor` is the
    // hub's whole routing table: with no route installed it has nowhere to send
    // a `message` frame or a sample even if one arrived. That is a stronger
    // statement than counting frames, because it holds for frames not yet sent.
    for (final session in peers) {
      final nodeUId = session.thisNode.uId;
      for (final stream in [streamName, coordinationStreamName]) {
        expect(
          hub.subscribersFor(
            streamName: stream,
            producerEndpointId: '$sessionName/$nodeUId/$stream',
          ),
          isEmpty,
          reason: 'the hub installed a relay route for "$stream"',
        );
      }
    }

    // Discovery, though, is entirely the hub's: every endpoint is registered
    // there, which is how election and `createInletsForNodes` resolve peers.
    expect(hub.endpointCount, greaterThanOrEqualTo(4));
  });

  test(
    'a data stream gets the reliability mode its config asked for',
    () async {
      final peers = await buildPair(dataOrdered: false, dataMaxRetransmits: 0);
      final streamName = 'Unreliable-$runId';
      await exchange(peers, streamName, samplesEach: 2);

      final adapter = bus.adapterFor(peers.first.thisNode.uId);
      expect(
        adapter,
        isNotNull,
        reason: 'the coordinator should have an adapter',
      );

      final dataRequests = adapter!.openedChannels.where(
        (r) => r.id == rtcChannelIdFor(streamName),
      );
      expect(dataRequests, isNotEmpty);
      for (final request in dataRequests) {
        expect(request.ordered, isFalse);
        expect(request.maxRetransmits, 0);
      }

      // The coordination stream is never negotiable: it carries election and
      // topology decisions, and a lost one splits the session.
      final coordinationRequests = adapter.openedChannels.where(
        (r) => r.id == coordinationChannelId,
      );
      expect(coordinationRequests, isNotEmpty);
      for (final request in coordinationRequests) {
        expect(request.ordered, isTrue);
        expect(request.maxRetransmits, isNull);
      }
    },
  );

  test(
    'removeInlet releases the channel but not a connection still in use',
    () async {
      final peers = await buildPair();
      final streamName = 'Release-$runId';
      await exchange(peers, streamName, samplesEach: 2);

      final coordinator = peers.first;
      final participantUId = peers[1].thisNode.uId;
      final adapter = bus.adapterFor(coordinator.thisNode.uId)!;
      final dataChannelId = rtcChannelIdFor(streamName);

      expect(
        adapter.openChannelIdsTo(participantUId),
        containsAll(<int>[dataChannelId, coordinationChannelId]),
        reason: 'both streams should share one connection to the participant',
      );

      final stream = await coordinator.getDataStream(streamName);
      await stream.removeInlet(participantUId);

      expect(
        adapter.openChannelIdsTo(participantUId),
        isNot(contains(dataChannelId)),
        reason: 'the data channel should be gone',
      );
      // The connection survives, because the coordination stream is still on it.
      // Tearing it down here would take the session with it — which is why the
      // mesh drops a link only when its *last* channel goes.
      expect(adapter.peerKeys, contains(participantUId));
      expect(
        adapter.openChannelIdsTo(participantUId),
        contains(coordinationChannelId),
      );
    },
  );
}
