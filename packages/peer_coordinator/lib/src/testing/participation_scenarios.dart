/// Shared scenarios for [StreamParticipationMode], run against every
/// transport in this package.
///
/// The mode decides who publishes a data stream and who receives it. Getting
/// it wrong is quiet — data simply goes to the wrong nodes, or nowhere — so
/// each mode is pinned by observing actual delivery rather than by inspecting
/// the producer/consumer sets.
library;

import 'dart:async';

import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:test/test.dart';

/// Supplies transport configs for a run, so one scenario set can be driven
/// over any transport.
abstract class ParticipationHarness {
  /// Human-readable transport name, used in test descriptions.
  String get name;

  /// Called once per test, before any node is built.
  Future<void> setUp();

  /// Called once per test, after all nodes are torn down.
  Future<void> tearDown();

  /// A transport config for one node. All nodes in a run must end up on the
  /// same medium.
  ITransportConfig transportConfigFor(int nodeIndex);

  /// Session name for the current run.
  ///
  /// Overridable because some transports discover peers machine-wide (LSL
  /// resolves over the network, not within a process), so each run needs a
  /// distinct name or concurrent runs — and leftovers from a previous test —
  /// are discovered as peers.
  String get sessionName => 'ParticipationSession';

  /// How long to allow for a join to settle.
  Duration get joinTimeout => const Duration(seconds: 3);

  /// How long to allow for samples to arrive.
  Duration get settleTimeout => const Duration(seconds: 3);

  /// How long to wait after `startStream` before publishing.
  ///
  /// Transports differ here in a way that is not a bug: an in-process bus is
  /// ready the instant a route is installed, whereas LSL has to establish a
  /// TCP connection per inlet/outlet pair, and an outlet with no connected
  /// consumer yet simply drops what it is given. Publishing too early would
  /// measure the handshake rather than the participation mode.
  Duration get warmup => const Duration(milliseconds: 200);

  /// Gap between successive samples from one node.
  Duration get sendInterval => Duration.zero;

  /// Modes to skip for this transport, mapped to why.
  ///
  /// The reason is printed in the test output, so a known gap stays visible
  /// instead of being deleted or left red. Empty means the transport is
  /// expected to satisfy the whole matrix.
  Map<StreamParticipationMode, String> get skippedModes => const {};

  /// Quiet period after a test's nodes are disposed, before the next starts.
  ///
  /// Needed by transports whose teardown is not synchronous with `dispose()`.
  /// LSL tears down isolates, outlets and inlets asynchronously and resolves
  /// peers machine-wide, so without a pause the next test starts while the
  /// previous run's nodes are still shutting down and competing for ports.
  Duration get teardownSettle => Duration.zero;
}

/// One node under test, with the samples it received.
class _Peer {
  _Peer(this.label, this.session);

  final String label;
  final PeerSession session;
  final List<List<double>> received = [];
  DataStream? stream;
  StreamSubscription<void>? _inbox;

  bool get isCoordinator => session.isCoordinator;

  void listen(DataStream s) {
    stream = s;
    _inbox = s.inbox.listen((message) {
      received.add(message.data.cast<double>().toList());
    });
  }

  Future<void> cancel() async => _inbox?.cancel();
}

/// Polls until [session] has [streamName], or [timeout] expires.
Future<DataStream> _awaitDataStream(
  PeerSession session,
  String streamName,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      return await session.getDataStream(streamName);
    } on ArgumentError {
      if (!DateTime.now().isBefore(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}

/// Registers the participation-mode scenarios for [harness].
void runParticipationScenarios(ParticipationHarness harness) {
  group('${harness.name} · participation modes', () {
    late List<_Peer> peers;
    late String runId;
    var runCounter = 0;

    setUp(() async {
      await harness.setUp();
      peers = [];
      // Every identity in a run is unique: session, node ids and stream names.
      //
      // Session alone is not enough. LSL resolves peers machine-wide and its
      // teardown is not synchronous with dispose(), so the previous test's
      // outlets are often still live and still resolvable when the next test
      // starts. Sharing a node id or stream name across tests then lets one
      // run discover another's leftovers.
      runId = '${DateTime.now().microsecondsSinceEpoch}-${runCounter++}';
    });

    tearDown(() async {
      for (final peer in peers.reversed) {
        await peer.cancel();
        try {
          await peer.session.leave();
        } catch (e) {
          // Must not mask the assertion that failed, but a teardown that
          // throws leaves resources behind and poisons every later test, so
          // it has to be visible.
          printOnFailure('teardown: leave() threw for ${peer.label}: $e');
        }
        try {
          await peer.session.dispose();
        } catch (e) {
          printOnFailure('teardown: dispose() threw for ${peer.label}: $e');
        }
      }
      peers = [];
      await harness.tearDown();
      if (harness.teardownSettle > Duration.zero) {
        await Future<void>.delayed(harness.teardownSettle);
      }
    });

    CoordinationConfig configFor(int index) => CoordinationConfig(
      name: 'participation_test',
      sessionConfig: CoordinationSessionConfig(
        name: harness.sessionName,
        maxNodes: 3,
        minNodes: 1,
        heartbeatInterval: const Duration(milliseconds: 100),
        discoveryInterval: const Duration(milliseconds: 50),
        nodeTimeout: const Duration(milliseconds: 800),
        consumeCoordinationStreamAsCoordinator: false,
      ),
      topologyConfig: HierarchicalTopologyConfig(
        promotionStrategy: PromotionStrategyRandom(),
        maxNodes: 3,
      ),
      streamConfig: CoordinationStreamConfig(name: 'coordination-$runId'),
      transportConfig: harness.transportConfigFor(index),
    );

    /// Builds a 3-node session: one coordinator (lowest roll) and two
    /// participants, all joined and mutually aware.
    Future<List<_Peer>> buildSession() async {
      const labels = ['coordinator', 'participant-a', 'participant-b'];
      const rolls = [0.1, 0.5, 0.9];

      for (var i = 0; i < labels.length; i++) {
        final session = PeerSession.create(
          configFor(i),
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
        peers.add(_Peer(labels[i], session));
        await session.initialize();
        await session.join(harness.joinTimeout);
      }

      await peers.first.session.waitForMinNodes(
        3,
        timeout: const Duration(seconds: 10),
      );
      expect(
        peers.where((p) => p.isCoordinator),
        hasLength(1),
        reason: 'exactly one coordinator expected',
      );
      expect(peers.first.isCoordinator, isTrue);
      return peers;
    }

    /// Creates the stream on every node, starts it, has every node that can
    /// publish send [samplesEach] samples, then waits for delivery to settle.
    Future<void> exchange(
      StreamParticipationMode mode, {
      int samplesEach = 5,
    }) async {
      final streamName = 'Modes-$runId';
      final config = DataStreamConfig(
        name: streamName,
        channels: 2,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
        participationMode: mode,
      );

      // Participants create their stream when told to; the coordinator's
      // createDataStream blocks until they report ready.
      final List<_Peer> participantStreams = peers
          .skip(1)
          .toList(growable: false);

      final coordinatorStream = await peers.first.session.createDataStream(
        config,
      );
      peers.first.listen(coordinatorStream);

      await peers.first.session.startStream(streamName);

      // Wait for each participant's stream to exist rather than assuming it.
      //
      // Participants build their streams automatically on the coordinator's
      // createStream command, and for most modes the coordinator's
      // createDataStream blocks until they report ready. coordinatorOnly is
      // the exception: it skips the readiness barrier entirely (participants
      // publish nothing, so there is nothing to wait for), which means their
      // streams may not exist yet when control returns here.
      for (final peer in participantStreams) {
        peer.listen(
          await _awaitDataStream(peer.session, streamName, harness.joinTimeout),
        );
      }
      // Let the start command reach every node and their links come up.
      await Future<void>.delayed(harness.warmup);

      for (var s = 0; s < samplesEach; s++) {
        for (var i = 0; i < peers.length; i++) {
          try {
            await peers[i].stream!.sendData([i.toDouble(), s.toDouble()]);
          } catch (_) {
            // A node with no publishing endpoint in this mode may refuse;
            // that is itself part of the mode's behaviour.
          }
        }
        if (harness.sendInterval > Duration.zero) {
          await Future<void>.delayed(harness.sendInterval);
        }
      }

      // Let delivery land BEFORE tearing the stream down.
      //
      // stopStream stops the coordinator's own stream synchronously and only
      // then broadcasts, and a stopped stream drops anything still in flight.
      // Stopping first therefore discarded exactly the samples under test —
      // which is why the coordinator saw nothing in every mode where it
      // consumes, while coordinatorOnly (participants consuming, stopped
      // later via the broadcast) still passed.
      await Future<void>.delayed(harness.settleTimeout);

      await peers.first.session.stopStream(streamName);
      await peers.first.session.destroyStream(streamName);
      for (final peer in participantStreams) {
        await peer.cancel();
      }
      peers.first.cancel();
    }

    /// Which node indices a peer received samples from. Channel 0 carries the
    /// sender index.
    Set<int> sendersSeenBy(_Peer peer) =>
        peer.received.map((sample) => sample[0].toInt()).toSet();

    String? skipFor(StreamParticipationMode mode) {
      final reason = harness.skippedModes[mode];
      return reason == null ? null : '${mode.name}: $reason';
    }

    test('coordinatorOnly: only the coordinator publishes', () async {
      await buildSession();
      await exchange(StreamParticipationMode.coordinatorOnly);

      final coordinator = peers[0];
      expect(
        coordinator.received,
        isEmpty,
        reason: 'the coordinator is the sole producer; it consumes nothing',
      );
      for (final participant in peers.skip(1)) {
        expect(sendersSeenBy(participant), {
          0,
        }, reason: '${participant.label} should receive only the coordinator');
      }
    }, skip: skipFor(StreamParticipationMode.coordinatorOnly));

    test(
      'sendParticipantsReceiveCoordinator: participants publish, only the '
      'coordinator consumes',
      () async {
        await buildSession();
        await exchange(
          StreamParticipationMode.sendParticipantsReceiveCoordinator,
        );

        expect(sendersSeenBy(peers[0]), {
          1,
          2,
        }, reason: 'the coordinator should receive from both participants');
        for (final participant in peers.skip(1)) {
          expect(
            participant.received,
            isEmpty,
            reason: '${participant.label} must not receive in this mode',
          );
        }
      },
      skip: skipFor(StreamParticipationMode.sendParticipantsReceiveCoordinator),
    );

    test('allNodes: everyone publishes and everyone consumes', () async {
      await buildSession();
      await exchange(StreamParticipationMode.allNodes);

      // Including itself: getProducersForStream and getConsumersForStream
      // both return every connected node for this mode, so a node is one of
      // its own producers. Whether that is wanted is a property of the mode,
      // not of the transport — a transport that quietly dropped self-delivery
      // would be overriding the mode.
      for (var i = 0; i < peers.length; i++) {
        expect(sendersSeenBy(peers[i]), {
          0,
          1,
          2,
        }, reason: '${peers[i].label} should receive from every node');
      }
    }, skip: skipFor(StreamParticipationMode.allNodes));

    test('sendAllReceiveCoordinator: everyone publishes', () async {
      await buildSession();
      await exchange(StreamParticipationMode.sendAllReceiveCoordinator);

      // Producers are all nodes, consumers are the coordinator alone, so the
      // coordinator sees everyone — itself included.
      expect(sendersSeenBy(peers[0]), {
        0,
        1,
        2,
      }, reason: 'the coordinator should receive from every producer');
    }, skip: skipFor(StreamParticipationMode.sendAllReceiveCoordinator));

    test('sendAllReceiveCoordinator ALSO delivers to participants '
        '(characterisation — see known issues)', () async {
      // The documented consumer set for this mode is the coordinator alone
      // (getConsumersForStream), but createDataStream has participants build
      // inlets for every producer whenever the mode is not
      // sendParticipantsReceiveCoordinator. So participants receive too, and
      // the mode behaves like allNodes on the receive side.
      //
      // Pinned rather than fixed: changing it alters delivery for anyone
      // relying on current behaviour, and the right fix (gate inlet creation
      // on getConsumersForStream) is a deliberate decision.
      await buildSession();
      await exchange(StreamParticipationMode.sendAllReceiveCoordinator);

      expect(
        sendersSeenBy(peers[1]),
        isNotEmpty,
        reason:
            'BUG: participants receive despite the consumer set naming only '
            'the coordinator',
      );
    }, skip: skipFor(StreamParticipationMode.sendAllReceiveCoordinator));
  });
}
