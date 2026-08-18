/// End-to-end characterisation of the LSL coordination flow.
///
/// This is the green baseline the transport extraction has to preserve. It
/// drives real [LSLCoordinationSession]s over loopback and asserts on election,
/// join, the data path, stream lifecycle and clean teardown — everything the
/// existing `example/multi_node_test.dart` exercises but never checks.
///
/// See `test/support/lsl_harness.dart` for why every node has to live in one
/// process under one process-global LSL config.
@Tags(['lsl', 'integration'])
library;

import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:test/test.dart';

import '../support/lsl_harness.dart';

/// Everything needed to drive one node, plus its teardown.
class TestNode {
  TestNode(this.name, this.session);

  final String name;
  final LSLCoordinationSession session;
  bool _joined = false;

  bool get isCoordinator => session.isCoordinator;

  Future<void> initialize() => session.initialize();

  /// Joins the session.
  ///
  /// [timeout] is deliberately short. Election calls `discoverOnce` with
  /// `minStreams: 1`, which returns as soon as a peer is found but otherwise
  /// waits out the *entire* timeout before concluding there is no better
  /// candidate — so the eventual coordinator always pays it in full. On
  /// loopback, peers resolve in well under a second.
  Future<void> join([Duration timeout = const Duration(seconds: 3)]) async {
    await session.join(timeout);
    _joined = true;
  }

  Future<void> shutdown() async {
    try {
      if (_joined) await session.leave();
    } catch (_) {
      // Teardown must not mask the assertion that actually failed.
    }
    try {
      await session.dispose();
    } catch (_) {}
  }
}

void main() {
  useLoopbackLsl();

  /// Nodes created by the current test, torn down in reverse order.
  late List<TestNode> nodes;
  late String sessionName;

  setUp(() {
    nodes = [];
    sessionName = uniqueSessionName();
  });

  tearDown(() async {
    for (final node in nodes.reversed) {
      await node.shutdown();
    }
    nodes = [];
  });

  /// Builds a node. Lower [randomRoll] wins the election, because a node
  /// becomes a participant as soon as it discovers a peer rolling lower than
  /// itself, so the lowest roll finds nobody to defer to.
  TestNode makeNode(
    String name, {
    required double randomRoll,
    int maxNodes = 3,
  }) {
    final node = TestNode(
      name,
      LSLCoordinationSession(
        testCoordinationConfig(sessionName: sessionName, maxNodes: maxNodes),
        thisNodeConfig: testNodeConfig(name: name, randomRoll: randomRoll),
      ),
    );
    nodes.add(node);
    return node;
  }

  DataStreamConfig dataStreamConfig({
    StreamParticipationMode mode =
        StreamParticipationMode.sendParticipantsReceiveCoordinator,
  }) => DataStreamConfig(
    name: 'TestData',
    channels: 2,
    sampleRate: 20.0,
    dataType: StreamDataType.double64,
    participationMode: mode,
  );

  group('election', () {
    test('a lone node elects itself coordinator', () async {
      final only = makeNode('solo', randomRoll: 0.5);
      await only.initialize();
      await only.join();

      expect(only.isCoordinator, isTrue);
      expect(
        only.session.connectedNodes.map((n) => n.uId),
        contains(only.session.thisNode.uId),
        reason: 'the coordinator should include itself in the topology',
      );
    });

    test('two nodes agree on exactly one coordinator', () async {
      // Start the low roller first and let it establish, so the outcome does
      // not depend on discovery timing.
      final first = makeNode('first', randomRoll: 0.1);
      await first.initialize();
      await first.join();
      expect(first.isCoordinator, isTrue);

      final second = makeNode('second', randomRoll: 0.9);
      await second.initialize();
      await second.join();

      expect(second.isCoordinator, isFalse);
      expect(
        second.session.connectedNodes.map((n) => n.uId),
        contains(first.session.thisNode.uId),
        reason: 'the participant should know the coordinator',
      );

      await first.session.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 15),
      );
      expect(first.session.connectedNodes, hasLength(2));
      expect(first.session.connectedParticipantNodes, hasLength(1));
    });
  });

  group('membership', () {
    test('a third node past maxNodes is rejected', () async {
      // maxNodes 2 = coordinator + one participant.
      final coordinator = makeNode('coord', randomRoll: 0.1, maxNodes: 2);
      await coordinator.initialize();
      await coordinator.join();

      final accepted = makeNode('accepted', randomRoll: 0.5, maxNodes: 2);
      await accepted.initialize();
      await accepted.join();
      await coordinator.session.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 15),
      );

      final rejections = <NodeJoinRejectedEvent>[];
      final sub = coordinator.session.events.nodeJoinRejected.listen(
        rejections.add,
      );

      final surplus = makeNode('surplus', randomRoll: 0.9, maxNodes: 2);
      await surplus.initialize();
      // The rejection never propagates out of join() — see the known-issues
      // group below — so the surplus node's own view is not the contract. What
      // matters, and what is stable, is that the coordinator refuses it.
      try {
        await surplus.join(const Duration(seconds: 5));
      } catch (_) {
        // Expected: it gives up waiting for a phase it will never reach.
      }

      expect(rejections, isNotEmpty, reason: 'the join should be refused');
      expect(rejections.first.reason, 'Maximum nodes reached');
      expect(rejections.first.rejectedNodeUId, surplus.session.thisNode.uId);
      expect(
        coordinator.session.connectedNodes.map((n) => n.uId),
        isNot(contains(surplus.session.thisNode.uId)),
        reason: 'the surplus node must not be admitted',
      );
      expect(
        coordinator.session.connectedNodes,
        hasLength(2),
        reason: 'the topology must never exceed maxNodes',
      );
      expect(
        coordinator.session.connectedNodes.map((n) => n.uId),
        containsAll([
          coordinator.session.thisNode.uId,
          accepted.session.thisNode.uId,
        ]),
      );
      await sub.cancel();
    });

    test('a graceful leave removes the node from the topology', () async {
      final coordinator = makeNode('coord', randomRoll: 0.1);
      await coordinator.initialize();
      await coordinator.join();

      final leaver = makeNode('leaver', randomRoll: 0.9);
      await leaver.initialize();
      await leaver.join();
      await coordinator.session.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 15),
      );

      final left = Completer<NodeLeftEvent>();
      final sub = coordinator.session.events.nodeLeft.listen((e) {
        if (!left.isCompleted) left.complete(e);
      });

      await leaver.session.leave();

      final event = await left.future.timeout(const Duration(seconds: 10));
      expect(event.node.uId, leaver.session.thisNode.uId);
      expect(coordinator.session.connectedNodes, hasLength(1));
      await sub.cancel();
    });
  });

  group('data streams', () {
    test('samples flow from participant to coordinator', () async {
      final coordinator = makeNode('coord', randomRoll: 0.1);
      await coordinator.initialize();
      await coordinator.join();

      final producer = makeNode('producer', randomRoll: 0.9);
      await producer.initialize();
      await producer.join();
      await coordinator.session.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 15),
      );

      // The participant creates its stream when told to; the coordinator's
      // createDataStream blocks until participants report ready.
      final producerStreamReady = Completer<LSLDataStream>();
      final producerSub = producer.session.events.streamStart.listen((
        event,
      ) async {
        if (producerStreamReady.isCompleted) return;
        producerStreamReady.complete(
          await producer.session.getDataStream(event.streamName),
        );
      });

      final received = <List<double>>[];
      final coordinatorStream = await coordinator.session.createDataStream(
        dataStreamConfig(),
      );
      final inboxSub = coordinatorStream.inbox.listen((message) {
        received.add(message.data.cast<double>().toList());
      });

      await coordinator.session.startStream('TestData');
      final producerStream = await producerStreamReady.future.timeout(
        const Duration(seconds: 15),
      );

      // Send a known, checkable sequence.
      const sampleCount = 20;
      for (var i = 0; i < sampleCount; i++) {
        await producerStream.sendData([i.toDouble(), i * 2.0]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // Allow the tail of the stream to drain.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (received.length < sampleCount &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(
        received,
        hasLength(sampleCount),
        reason: 'every sample sent should arrive — no loss on loopback',
      );
      // Order and payload must both be intact.
      for (var i = 0; i < sampleCount; i++) {
        expect(received[i], [i.toDouble(), i * 2.0], reason: 'sample $i');
      }

      await coordinator.session.stopStream('TestData');
      await inboxSub.cancel();
      await producerSub.cancel();
    });

    test('a user message reaches the participant', () async {
      final coordinator = makeNode('coord', randomRoll: 0.1);
      await coordinator.initialize();
      await coordinator.join();

      final participant = makeNode('participant', randomRoll: 0.9);
      await participant.initialize();
      await participant.join();
      await coordinator.session.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 15),
      );

      final delivered = participant.session.waitForUserMessage(
        'phase',
        timeout: const Duration(seconds: 10),
      );
      await coordinator.session.sendUserMessage('phase', 'start phase 1', {
        'phase': 1,
      });

      final event = await delivered;
      expect(event.messageType, 'phase');
      expect(event.description, 'start phase 1');
      expect(event.payload['phase'], 1);
    });

    test('inbox can be listened to again after cancelling', () async {
      // The LSL transport used a single-subscription controller here while the
      // websocket and in-memory transports were broadcast, so this exact
      // sequence threw `Bad state: Stream has already been listened to` on LSL
      // alone. It is not a contrived sequence: getDataStream returns the same
      // cached object across a stream stop/start cycle, so any consumer that
      // tears its subscription down and rebuilds it hits this.
      final coordinator = makeNode('coord', randomRoll: 0.1);
      await coordinator.initialize();
      await coordinator.join();

      final stream = await coordinator.session.createDataStream(
        dataStreamConfig(),
      );

      final firstSub = stream.inbox.listen((_) {});
      await firstSub.cancel();

      late StreamSubscription<dynamic> secondSub;
      expect(() => secondSub = stream.inbox.listen((_) {}), returnsNormally);
      await secondSub.cancel();
    });
  });

  group('teardown', () {
    test('a full session lifecycle disposes without throwing', () async {
      final coordinator = makeNode('coord', randomRoll: 0.1);
      await coordinator.initialize();
      await coordinator.join();

      final participant = makeNode('participant', randomRoll: 0.9);
      await participant.initialize();
      await participant.join();
      await coordinator.session.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 15),
      );

      await expectLater(participant.session.leave(), completes);
      await expectLater(participant.session.dispose(), completes);
      await expectLater(coordinator.session.leave(), completes);
      await expectLater(coordinator.session.dispose(), completes);

      // Stop tearDown from disposing them a second time.
      nodes.clear();
    });
  });

  group('known issues (characterisation — these pin current behaviour)', () {
    test('a rejected node cannot tell rejection from an ordinary timeout', () {
      // ParticipantMessageHandler._handleJoinReject throws a StateError so the
      // session can surface the rejection (handlers.dart:535). But the
      // controller invokes handlers from inside a stream listener and wraps
      // every call in a try/catch that only logs
      // (lsl_coordination_controller.dart:404-411), so the StateError is
      // swallowed.
      //
      // The rejected node therefore just sits in CoordinationPhase.established
      // until join()'s _waitForPhase gives up, and reports:
      //
      //   StateError: Failed to establish coordination: TimeoutException ...
      //     Timeout waiting for phase {accepting, ready}
      //
      // — indistinguishable from "no coordinator could be reached". That is
      // why example/multi_node_test.dart:184 has to string-match 'rejected',
      // and why it never actually matches.
      //
      // The fix belongs with the coordinator-loss work: give the participant a
      // way to fail its join with the real reason. Until then, callers must
      // watch the coordinator's NodeJoinRejectedEvent, as the maxNodes test
      // above does.
      //
      // Marked as a documentation-only test: the behaviour is asserted in the
      // maxNodes test, which tolerates whatever join() does.
    }, skip: 'documented above; behaviour is covered by the maxNodes test');

    test('a full session rejects the same node on every discovery cycle', () {
      // When the coordinator rejects a node it emits NodeJoinRejectedEvent,
      // and the controller responds by clearing the node from
      // _pendingJoinNodeUIds so it can be re-offered "if capacity frees up"
      // (lsl_coordination_controller.dart:339-342).
      //
      // Nothing rate-limits that. A node parked outside a full session is
      // re-offered, re-requests and is re-rejected on every discovery tick —
      // observed at 11-16 rejections in a 5s window with a 500ms discovery
      // interval. Each cycle also runs the 20s-timeout connection-test
      // handshake, so the traffic is not trivial.
      //
      // Harmless for a short-lived session with a spare node; worth bounding
      // before the WebSocket transport, where every one of those rejects is a
      // relayed frame through the hub.
    }, skip: 'documented above; no stable assertion without a long run');
  });
}
