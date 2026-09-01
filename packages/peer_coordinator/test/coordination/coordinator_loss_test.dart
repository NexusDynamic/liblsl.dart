/// Drives whole sessions through losing their coordinator.
///
/// The behaviour these pin did not exist before: the liveness sweep ran on the
/// coordinator only, so a participant whose coordinator went away kept
/// heartbeating and publishing into a stream with no consumer, indefinitely and
/// silently. There was also no way for a departing coordinator to say so — the
/// leave notice was participant-only — so even a clean shutdown looked like a
/// network stall.
///
/// Both halves are covered here: an announced departure ([SessionEndReason.coordinatorLeft])
/// and a node that simply vanishes ([SessionEndReason.coordinatorTimedOut]), for
/// each [CoordinatorLossPolicy].
library;

import 'dart:async';

import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/in_memory.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBus bus;
  late List<PeerSession> sessions;

  const sessionName = 'LossSession';
  const streamName = 'coordination';
  const nodeTimeout = Duration(milliseconds: 400);

  setUp(() {
    bus = InMemoryBus();
    sessions = [];
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      try {
        await session.leave();
      } catch (_) {
        // Teardown must not mask the assertion that actually failed.
      }
      try {
        await session.dispose();
      } catch (_) {}
    }
    sessions = [];
    bus.dispose();
  });

  CoordinationConfig configFor(
    CoordinatorLossPolicy policy,
  ) => CoordinationConfig(
    name: 'loss_test',
    sessionConfig: CoordinationSessionConfig(
      name: sessionName,
      maxNodes: 3,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 50),
      discoveryInterval: const Duration(milliseconds: 25),
      // Sub-second on purpose. `Duration(seconds: nodeTimeout.inSeconds ~/ 2)`
      // truncated to zero here, giving a periodic timer that fired every
      // event-loop turn; the sweep period is now computed in microseconds.
      nodeTimeout: nodeTimeout,
      consumeCoordinationStreamAsCoordinator: false,
      coordinatorLossPolicy: policy,
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: 3,
    ),
    streamConfig: CoordinationStreamConfig(name: streamName),
    transportConfig: InMemoryTransportConfig(bus: bus),
  );

  /// Lower roll wins the election, so the roll fixes who coordinates — before
  /// and after a re-election.
  Future<PeerSession> joined(
    String name, {
    required double randomRoll,
    CoordinatorLossPolicy policy = CoordinatorLossPolicy.endSession,
  }) async {
    final session = PeerSession.create(
      configFor(policy),
      thisNodeConfig: NodeConfig(
        name: name,
        id: name,
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
        metadata: {PeerMetadataKeys.randomRoll: randomRoll.toString()},
      ),
    );
    sessions.add(session);
    await session.initialize();
    await session.join(const Duration(milliseconds: 500));
    return session;
  }

  /// Collects session-end events from the moment of subscription. `events` is a
  /// broadcast stream that buffers nothing, so this has to be set up before the
  /// coordinator goes away.
  List<SessionEndedEvent> watchEnds(PeerSession session) {
    final seen = <SessionEndedEvent>[];
    session.events.sessionEnded.listen(seen.add);
    return seen;
  }

  Future<SessionEndedEvent> nextEnd(PeerSession session) =>
      session.events.sessionEnded.first.timeout(const Duration(seconds: 3));

  /// Kills a node the way a crashed process dies: no announcement, nothing
  /// flushed. The bus drops its inbox, its routes and its registry entry — which
  /// is exactly what a hub does on a closed socket.
  void killWithoutNotice(PeerSession session) {
    bus.disconnect('$sessionName/${session.thisNode.uId}/$streamName');
  }

  group('endSession policy', () {
    test('an announced departure ends the participant\'s session', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('p1', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final ended = nextEnd(participant);
      await coordinator.leave();

      final event = await ended;
      expect(event.reason, SessionEndReason.coordinatorLeft);
      expect(event.policy, CoordinatorLossPolicy.endSession);
      expect(event.coordinatorUId, coordinator.thisNode.uId);
      expect(participant.currentPhase, CoordinationPhase.ended);
    });

    test('a send after the session ends throws instead of vanishing', () async {
      // The whole point of the policy. A participant used to be able to keep
      // publishing into a dead stream forever with nothing to tell it otherwise —
      // in the chat example, the message box stayed usable and the lines went
      // nowhere.
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('p1', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final ended = nextEnd(participant);
      await coordinator.leave();
      await ended;

      await expectLater(
        participant.sendUserMessage('chat', 'hello?', {'text': 'hello?'}),
        throwsStateError,
      );
    });

    test('a coordinator that vanishes is noticed by timeout', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('p1', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final ended = nextEnd(participant);
      killWithoutNotice(coordinator);

      final event = await ended;
      expect(event.reason, SessionEndReason.coordinatorTimedOut);
      expect(participant.currentPhase, CoordinationPhase.ended);
    });

    test('every participant is told, not just one', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final first = await joined('p1', randomRoll: 0.5);
      final second = await joined('p2', randomRoll: 0.9);
      await coordinator.waitForMinNodes(3, timeout: const Duration(seconds: 3));

      final firstEnded = nextEnd(first);
      final secondEnded = nextEnd(second);
      await coordinator.leave();

      expect((await firstEnded).reason, SessionEndReason.coordinatorLeft);
      expect((await secondEnded).reason, SessionEndReason.coordinatorLeft);
    });

    test('a live coordinator never looks lost', () async {
      // The other half of the timeout: the sweep must not fire while heartbeats
      // are arriving. Runs for several nodeTimeouts.
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('p1', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final ends = watchEnds(participant);
      await Future<void>.delayed(nodeTimeout * 4);

      expect(ends, isEmpty);
      expect(participant.currentPhase, isNot(CoordinationPhase.ended));
    });
  });

  group('reelect policy', () {
    test('a survivor takes the role and the rest re-join it', () async {
      final coordinator = await joined(
        'coord',
        randomRoll: 0.1,
        policy: CoordinatorLossPolicy.reelect,
      );
      final middle = await joined(
        'p1',
        randomRoll: 0.5,
        policy: CoordinatorLossPolicy.reelect,
      );
      final last = await joined(
        'p2',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.reelect,
      );
      await coordinator.waitForMinNodes(3, timeout: const Duration(seconds: 3));

      final middleEnded = nextEnd(middle);
      final lastEnded = nextEnd(last);
      await coordinator.leave();
      await middleEnded;
      await lastEnded;

      // Lowest surviving roll wins, so this is deterministic rather than a race.
      await middle.waitForMinNodes(2, timeout: const Duration(seconds: 5));
      expect(middle.isCoordinator, isTrue);
      expect(last.isCoordinator, isFalse);
      expect(last.coordinatorUId, middle.thisNode.uId);
      // Survivors only: a session that has left keeps whatever role it held, so
      // the departed coordinator would count here.
      expect(
        [middle, last].where((s) => s.isCoordinator),
        hasLength(1),
        reason: 'a re-election must not leave two coordinators',
      );
    });

    test('a user message crosses the rebuilt session', () async {
      final coordinator = await joined(
        'coord',
        randomRoll: 0.1,
        policy: CoordinatorLossPolicy.reelect,
      );
      final middle = await joined(
        'p1',
        randomRoll: 0.5,
        policy: CoordinatorLossPolicy.reelect,
      );
      final last = await joined(
        'p2',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.reelect,
      );
      await coordinator.waitForMinNodes(3, timeout: const Duration(seconds: 3));

      final lastEnded = nextEnd(last);
      await coordinator.leave();
      await lastEnded;
      await middle.waitForMinNodes(2, timeout: const Duration(seconds: 5));

      final delivered = Completer<UserMessageEvent>();
      last.events.userMessages.listen((event) {
        if (!delivered.isCompleted) delivered.complete(event);
      });
      await middle.sendUserMessage('chat', 'still here', {
        'text': 'still here',
      });

      final event = await delivered.future.timeout(const Duration(seconds: 3));
      expect(event.payload['text'], 'still here');
    });
  });

  group('remainOpen policy', () {
    test('the session stays live and sends still work', () async {
      // Characterisation of the pre-existing behaviour, kept as an escape hatch
      // for applications that drive their own recovery off the event.
      final coordinator = await joined(
        'coord',
        randomRoll: 0.1,
        policy: CoordinatorLossPolicy.remainOpen,
      );
      final participant = await joined(
        'p1',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.remainOpen,
      );
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final ended = nextEnd(participant);
      await coordinator.leave();

      final event = await ended;
      expect(event.policy, CoordinatorLossPolicy.remainOpen);
      expect(
        participant.currentPhase,
        isNot(CoordinationPhase.ended),
        reason: 'remainOpen changes nothing beyond emitting the event',
      );
      // Goes nowhere, but does not throw — that is the behaviour being pinned.
      await participant.sendUserMessage('chat', 'anyone?', {'text': 'anyone?'});
    });
  });

  group('eviction', () {
    /// Stops the coordinator hearing [participant] while leaving the reverse
    /// direction intact — the one-directional stall that eviction exists for,
    /// and the shape of the field failure these tests were written from: a node
    /// whose coordination stream went silent outbound while everything else
    /// about it kept working.
    void muteTowardsCoordinator(
      PeerSession participant,
      PeerSession coordinator,
    ) {
      bus.routing.unsubscribe(
        streamName: streamName,
        producerEndpointId:
            '$sessionName/${participant.thisNode.uId}/$streamName',
        subscriberEndpointId:
            '$sessionName/${coordinator.thisNode.uId}/$streamName',
      );
    }

    test('an evicted node is told, rather than left to time out', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('p1', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      // The participant stops being heard from but can still receive — a
      // one-directional stall, which is what makes the eviction notice useful.
      muteTowardsCoordinator(participant, coordinator);

      final event = await nextEnd(participant);
      expect(event.reason, SessionEndReason.evicted);
      expect(participant.currentPhase, CoordinationPhase.ended);
    });

    test('activity on another stream keeps a node from being evicted', () async {
      // The reason the field failure was so wasteful: the evicted node's *data*
      // stream was delivering samples to the coordinator 1:1 in the same second
      // it was declared dead. Only its heartbeats were missing.
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('p1', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final ends = watchEnds(participant);
      muteTowardsCoordinator(participant, coordinator);

      // Stand in for the application seeing data from that node.
      final ticker = Timer.periodic(
        const Duration(milliseconds: 40),
        (_) => coordinator.noteNodeActivity(participant.thisNode.uId),
      );
      addTearDown(ticker.cancel);

      await Future<void>.delayed(nodeTimeout * 4);

      expect(
        ends,
        isEmpty,
        reason: 'a node heard from on any stream is not a silent node',
      );
      expect(coordinator.connectedNodes.map((n) => n.uId), contains(
        participant.thisNode.uId,
      ));
    });

    test('activity stopping still lets the sweep evict', () async {
      // The counterpart: noteNodeActivity must postpone eviction, not disable
      // it, or a crashed node would linger in the roster forever.
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('p1', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      muteTowardsCoordinator(participant, coordinator);
      coordinator.noteNodeActivity(participant.thisNode.uId);

      final event = await nextEnd(participant);
      expect(event.reason, SessionEndReason.evicted);
    });
  });

  group('rejoin policy', () {
    test('an evicted node re-attaches once it can be heard again', () async {
      // The behaviour the whole policy exists for. Under endSession this same
      // sequence leaves the node permanently dead while its app carries on
      // rendering — a frozen screen with a running clock.
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined(
        'p1',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.rejoin,
      );
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final rejoined = participant.events.sessionRejoined.first.timeout(
        const Duration(seconds: 5),
      );
      final ended = nextEnd(participant);

      bus.routing.unsubscribe(
        streamName: streamName,
        producerEndpointId:
            '$sessionName/${participant.thisNode.uId}/$streamName',
        subscriberEndpointId:
            '$sessionName/${coordinator.thisNode.uId}/$streamName',
      );

      final endEvent = await ended;
      expect(endEvent.reason, SessionEndReason.evicted);
      expect(endEvent.policy, CoordinatorLossPolicy.rejoin);
      expect(
        participant.currentPhase,
        isNot(CoordinationPhase.ended),
        reason: 'rejoin must not enter the terminal phase',
      );

      // The link comes back, as it did in the field 10s before the eviction
      // was even declared.
      bus.routing.subscribe(
        streamName: streamName,
        producerEndpointId:
            '$sessionName/${participant.thisNode.uId}/$streamName',
        subscriberEndpointId:
            '$sessionName/${coordinator.thisNode.uId}/$streamName',
      );

      final event = await rejoined;
      expect(event.coordinatorUId, coordinator.thisNode.uId);
      expect(event.attempts, greaterThanOrEqualTo(1));
      expect(participant.isCoordinator, isFalse,
          reason: 'rejoin re-attaches as a participant, it never promotes');
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));
    });

    test('a rejoined node can send again', () async {
      // endSession leaves _ensureLive throwing forever; rejoin must clear that.
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined(
        'p1',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.rejoin,
      );
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final rejoined = participant.events.sessionRejoined.first.timeout(
        const Duration(seconds: 5),
      );
      bus.routing.unsubscribe(
        streamName: streamName,
        producerEndpointId:
            '$sessionName/${participant.thisNode.uId}/$streamName',
        subscriberEndpointId:
            '$sessionName/${coordinator.thisNode.uId}/$streamName',
      );
      await nextEnd(participant);
      bus.routing.subscribe(
        streamName: streamName,
        producerEndpointId:
            '$sessionName/${participant.thisNode.uId}/$streamName',
        subscriberEndpointId:
            '$sessionName/${coordinator.thisNode.uId}/$streamName',
      );
      await rejoined;

      await participant.sendUserMessage('chat', 'back', {'text': 'back'});
    });

    test('a coordinator that announces departure is also rejoined', () async {
      // Not only eviction: the same policy has to survive a coordinator
      // restarting under a new UId, which is what a headless server does.
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined(
        'p1',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.rejoin,
      );
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final ended = nextEnd(participant);
      await coordinator.leave();
      final endEvent = await ended;
      expect(endEvent.reason, SessionEndReason.coordinatorLeft);
      expect(
        participant.currentPhase,
        isNot(CoordinationPhase.ended),
        reason: 'rejoin keeps looking rather than giving up',
      );
    });
  });
}
