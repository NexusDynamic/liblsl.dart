/// Unit tests for the coordination protocol handlers.
///
/// [CoordinatorMessageHandler] and [ParticipantMessageHandler] hold the whole
/// join/leave/accept/reject protocol, topology diffing and stream-lifecycle
/// fan-out. They are already transport-neutral: `sendMessage` merely enqueues
/// onto [CoordinatorMessageHandler.outgoingMessages], and the transport is
/// whatever drains that stream.
///
/// That makes them directly unit-testable with no network at all, and it means
/// every transport inherits exactly the behaviour pinned here.
library;

import 'dart:async';

import 'package:peer_coordinator/framework.dart';
import 'package:test/test.dart';

Node participant(String uId) =>
    ParticipantNode(NodeConfig(name: uId, id: uId, uId: uId));

Node coordinatorNode(String uId) => CoordinatorNode(
  NodeConfig(
    name: uId,
    id: uId,
    uId: uId,
    capabilities: {NodeCapability.coordinator},
  ),
);

CoordinationSessionConfig sessionConfig({int maxNodes = 3}) =>
    CoordinationSessionConfig(
      name: 'TestSession',
      maxNodes: maxNodes,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 200),
      discoveryInterval: const Duration(milliseconds: 250),
      nodeTimeout: const Duration(milliseconds: 600),
    );

DataStreamConfig streamConfig({String name = 'TestData'}) => DataStreamConfig(
  name: name,
  channels: 2,
  sampleRate: 10.0,
  dataType: StreamDataType.double64,
);

/// Collects everything a handler emits, so tests can assert on it.
class HandlerSpy {
  final outgoing = <CoordinationMessage>[];
  final events = <ControllerEvent>[];
  final _subs = <StreamSubscription<void>>[];

  HandlerSpy.coordinator(CoordinatorMessageHandler handler) {
    _subs.add(handler.outgoingMessages.listen(outgoing.add));
    _subs.add(handler.events.listen(events.add));
  }

  HandlerSpy.participant(ParticipantMessageHandler handler) {
    _subs.add(handler.outgoingMessages.listen(outgoing.add));
    _subs.add(handler.events.listen(events.add));
  }

  /// Waits for queued async delivery, then returns.
  Future<void> settle() => pumpEventQueue();

  List<T> sent<T extends CoordinationMessage>() =>
      outgoing.whereType<T>().toList();
  List<T> emitted<T extends ControllerEvent>() =>
      events.whereType<T>().toList();

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
  }
}

void main() {
  group('CoordinatorMessageHandler', () {
    late CoordinationState state;
    late Node me;
    late CoordinatorMessageHandler handler;
    late HandlerSpy spy;

    setUp(() {
      state = CoordinationState();
      me = coordinatorNode('coord');
      state.becomeCoordinator(me.uId);
      state.addNode(me);
      state.transitionTo(CoordinationPhase.accepting);
      handler = CoordinatorMessageHandler(
        state: state,
        thisNode: me,
        sessionConfig: sessionConfig(),
      );
      spy = HandlerSpy.coordinator(handler);
    });

    tearDown(() async {
      await spy.dispose();
      handler.dispose();
      state.dispose();
    });

    group('canHandle', () {
      test('accepts exactly the coordinator-facing message types', () {
        const expected = {
          CoordinationMessageType.heartbeat,
          CoordinationMessageType.connectionTest,
          // The coordinator consumes replies too. Clock sync is per-inlet, and
          // the coordinator holds an inlet from every participant, so it is the
          // one probing them — which means it must handle their responses.
          CoordinationMessageType.connectionTestResponse,
          CoordinationMessageType.joinRequest,
          CoordinationMessageType.nodeLeaving,
          CoordinationMessageType.streamReady,
          CoordinationMessageType.userMessage,
          CoordinationMessageType.userParticipantMessage,
        };
        for (final type in CoordinationMessageType.values) {
          expect(
            handler.canHandle(type),
            expected.contains(type),
            reason: 'canHandle wrong for $type',
          );
        }
      });

      test('handles nothing at all once this node is not the coordinator', () {
        state.becomeParticipant('someone-else');
        for (final type in CoordinationMessageType.values) {
          expect(handler.canHandle(type), isFalse, reason: '$type');
        }
      });
    });

    group('join protocol', () {
      test(
        'accepts a join, adds the node and replies with the topology',
        () async {
          await handler.handleMessage(
            JoinRequestMessage(
              fromNodeUId: 'p1',
              requestingNode: participant('p1'),
              sessionId: 'TestSession',
            ),
          );
          await spy.settle();

          expect(state.connectedNodes.map((n) => n.uId), ['coord', 'p1']);

          final accept = spy.sent<JoinAcceptMessage>().single;
          expect(accept.acceptedNodeUId, 'p1');
          expect(accept.fromNodeUId, 'coord');
          expect(accept.currentTopology.map((n) => n.uId), ['coord', 'p1']);

          // and everyone is told about the new topology
          expect(
            spy.sent<TopologyUpdateMessage>().single.topology.map((n) => n.uId),
            ['coord', 'p1'],
          );
        },
      );

      test('rejects past maxNodes and emits NodeJoinRejectedEvent', () async {
        // maxNodes is 3 and the coordinator counts as one of them.
        await handler.handleMessage(_join('p1'));
        await handler.handleMessage(_join('p2'));
        await spy.settle();
        expect(state.connectedNodes, hasLength(3));
        expect(spy.sent<JoinRejectMessage>(), isEmpty);

        await handler.handleMessage(_join('p3'));
        await spy.settle();

        final reject = spy.sent<JoinRejectMessage>().single;
        expect(reject.rejectedNodeUId, 'p3');
        expect(reject.reason, 'Maximum nodes reached');
        expect(state.connectedNodes, hasLength(3));

        final event = spy.emitted<NodeJoinRejectedEvent>().single;
        expect(event.rejectedNodeUId, 'p3');
        expect(event.reason, 'Maximum nodes reached');
      });

      test('pauseAcceptingNodes rejects with a different reason', () async {
        expect(handler.isAcceptingNodes, isTrue);
        handler.pauseAcceptingNodes();
        expect(handler.isAcceptingNodes, isFalse);

        await handler.handleMessage(_join('p1'));
        await spy.settle();

        expect(
          spy.sent<JoinRejectMessage>().single.reason,
          'Not accepting new nodes',
        );
        expect(state.connectedNodes, hasLength(1));

        handler.resumeAcceptingNodes();
        await handler.handleMessage(_join('p1'));
        await spy.settle();

        expect(spy.sent<JoinAcceptMessage>(), hasLength(1));
        expect(state.connectedNodes.map((n) => n.uId), ['coord', 'p1']);
      });

      test(
        'an already-connected node is re-accepted even when paused',
        () async {
          // Both the maxNodes and the accepting checks are skipped for a node
          // that is already in the topology, so a rejoining node is never
          // locked out by a capacity limit it is already counted against.
          await handler.handleMessage(_join('p1'));
          await spy.settle();
          handler.pauseAcceptingNodes();

          await handler.handleMessage(_join('p1'));
          await spy.settle();

          expect(spy.sent<JoinRejectMessage>(), isEmpty);
          expect(spy.sent<JoinAcceptMessage>(), hasLength(2));
          expect(state.connectedNodes, hasLength(2));
        },
      );

      test(
        'nodeLeaving removes the node and re-broadcasts the topology',
        () async {
          await handler.handleMessage(_join('p1'));
          await spy.settle();
          spy.outgoing.clear();

          await handler.handleMessage(
            NodeLeavingMessage(fromNodeUId: 'p1', leavingNodeUId: 'p1'),
          );
          await spy.settle();

          expect(state.connectedNodes.map((n) => n.uId), ['coord']);
          expect(
            spy.sent<TopologyUpdateMessage>().single.topology.map((n) => n.uId),
            ['coord'],
          );
        },
      );
    });

    group('heartbeat and connection test', () {
      test('a heartbeat refreshes liveness without joining the node', () async {
        await handler.handleMessage(
          HeartbeatMessage(
            fromNodeUId: 'ghost',
            nodeRole: 'participant',
            isCoordinator: false,
          ),
        );
        await spy.settle();

        expect(
          state.connectedNodes.map((n) => n.uId),
          ['coord'],
          reason: 'a heartbeat is not an implicit join',
        );
        expect(spy.outgoing, isEmpty);
      });

      test('a connection test is answered with a confirmed response', () async {
        await handler.handleMessage(
          ConnectionTestMessage(fromNodeUId: 'p1', testId: 't-1'),
        );
        await spy.settle();

        final response = spy.sent<ConnectionTestResponseMessage>().single;
        expect(response.testId, 't-1');
        expect(response.confirmed, isTrue);
        expect(response.fromNodeUId, 'coord');
      });
    });

    group('stream lifecycle broadcasts', () {
      test(
        'each broadcast emits exactly one correctly typed message',
        () async {
          final config = streamConfig();
          final startAt = DateTime.utc(2026, 8, 9, 12);

          await handler.broadcastCreateStream('TestData', config);
          await handler.broadcastStartStream(
            'TestData',
            config,
            startAt: startAt,
          );
          await handler.broadcastStreamReady('TestData');
          await handler.broadcastPauseStream('TestData');
          await handler.broadcastResumeStream(
            'TestData',
            flushBeforeResume: false,
          );
          await handler.broadcastFlushStream('TestData');
          await handler.broadcastStopStream('TestData');
          await handler.broadcastDestroyStream('TestData');
          await spy.settle();

          expect(spy.outgoing.map((m) => m.type), [
            CoordinationMessageType.createStream,
            CoordinationMessageType.startStream,
            CoordinationMessageType.streamReady,
            CoordinationMessageType.pauseStream,
            CoordinationMessageType.resumeStream,
            CoordinationMessageType.flushStream,
            CoordinationMessageType.stopStream,
            CoordinationMessageType.destroyStream,
          ]);
          expect(spy.sent<StartStreamMessage>().single.startAt, startAt);
          expect(
            spy.sent<ResumeStreamMessage>().single.flushBeforeResume,
            isFalse,
          );
          expect(spy.outgoing.every((m) => m.fromNodeUId == 'coord'), isTrue);
        },
      );

      test(
        'a participant streamReady surfaces as a StreamReadyEvent',
        () async {
          await handler.handleMessage(
            StreamReadyMessage(fromNodeUId: 'p1', streamName: 'TestData'),
          );
          await spy.settle();

          final event = spy.emitted<StreamReadyEvent>().single;
          expect(event.streamName, 'TestData');
          expect(event.fromNodeUId, 'p1');
        },
      );

      test('sendJoinOffer targets a specific node', () async {
        await handler.sendJoinOffer(participant('p9'));
        await spy.settle();

        final offer = spy.sent<JoinOfferMessage>().single;
        expect(offer.targetNode.uId, 'p9');
        expect(offer.sessionId, 'TestSession');
      });
    });

    group('user messages and config', () {
      test('broadcastUserMessage preserves parentMessageId', () async {
        await handler.broadcastUserMessage('phase', 'start phase 1', {
          'phase': 1,
        }, 'parent-1');
        await spy.settle();

        final message = spy.sent<UserCoordinationMessage>().single;
        expect(message.messageType, 'phase');
        expect(message.payload, {'phase': 1});
        expect(message.parentMessageId, 'parent-1');
      });

      test('an inbound user message surfaces as the matching event', () async {
        await handler.handleMessage(
          UserCoordinationMessage(
            fromNodeUId: 'other',
            messageType: 'ping',
            description: 'd',
            payload: {'a': 1},
          ),
        );
        await handler.handleMessage(
          UserParticipantMessage(
            fromNodeUId: 'p1',
            messageType: 'pong',
            description: 'd',
            payload: {'b': 2},
          ),
        );
        await spy.settle();

        expect(spy.emitted<UserCoordinationEvent>().single.messageType, 'ping');
        expect(spy.emitted<UserParticipantEvent>().single.messageType, 'pong');
      });

      test('broadcastConfig sends the map verbatim', () async {
        await handler.broadcastConfig({'rate': 60});
        await spy.settle();
        expect(spy.sent<ConfigUpdateMessage>().single.config, {'rate': 60});
      });
    });
  });

  group('ParticipantMessageHandler', () {
    late CoordinationState state;
    late Node me;
    late ParticipantMessageHandler handler;
    late HandlerSpy spy;

    setUp(() {
      state = CoordinationState();
      me = participant('p1');
      state.becomeParticipant('coord');
      handler = ParticipantMessageHandler(
        state: state,
        thisNode: me,
        sessionConfig: sessionConfig(),
      );
      spy = HandlerSpy.participant(handler);
    });

    tearDown(() async {
      await spy.dispose();
      handler.dispose();
      state.dispose();
    });

    test('canHandle accepts the participant-facing types only', () {
      const expected = {
        CoordinationMessageType.joinAccept,
        CoordinationMessageType.joinReject,
        CoordinationMessageType.topologyUpdate,
        CoordinationMessageType.createStream,
        CoordinationMessageType.startStream,
        CoordinationMessageType.stopStream,
        CoordinationMessageType.userMessage,
        CoordinationMessageType.configUpdate,
        CoordinationMessageType.heartbeat,
        CoordinationMessageType.joinOffer,
        CoordinationMessageType.connectionTestResponse,
        // A participant answers connection tests too. Clock sync is per-inlet,
        // and the coordinator holds an inlet from every participant, so it
        // probes each of them — which means participants must respond.
        CoordinationMessageType.connectionTest,
        CoordinationMessageType.streamReady,
        CoordinationMessageType.pauseStream,
        CoordinationMessageType.resumeStream,
        CoordinationMessageType.flushStream,
        CoordinationMessageType.destroyStream,
      };
      for (final type in CoordinationMessageType.values) {
        expect(
          handler.canHandle(type),
          expected.contains(type),
          reason: '$type',
        );
      }
    });

    test(
      'a join accept for me moves to ready and installs the topology',
      () async {
        await handler.handleMessage(
          JoinAcceptMessage(
            fromNodeUId: 'coord',
            acceptedNodeUId: 'p1',
            currentTopology: [coordinatorNode('coord'), participant('p1')],
          ),
        );
        await spy.settle();

        expect(state.phase, CoordinationPhase.ready);
        expect(state.connectedNodes.map((n) => n.uId), ['coord', 'p1']);
      },
    );

    test('a join accept for someone else is ignored', () async {
      await handler.handleMessage(
        JoinAcceptMessage(
          fromNodeUId: 'coord',
          acceptedNodeUId: 'someone-else',
          currentTopology: [coordinatorNode('coord')],
        ),
      );
      await spy.settle();

      expect(state.phase, isNot(CoordinationPhase.ready));
      expect(state.connectedNodes, isEmpty);
    });

    test(
      'a join rejection for me throws so the session can surface it',
      () async {
        // The session turns this into a failed join(); example/multi_node_test
        // detects it by string-matching 'rejected'.
        await expectLater(
          handler.handleMessage(
            JoinRejectMessage(
              fromNodeUId: 'coord',
              rejectedNodeUId: 'p1',
              reason: 'Maximum nodes reached',
            ),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'a join offer completes the connection handshake, then joins',
      () async {
        // sendJoinRequestWithConfirmation blocks on a bidirectional connection
        // test before it will send the join request, so the offer cannot be
        // awaited until the coordinator's reply is fed back in.
        final offerHandled = handler.handleMessage(
          JoinOfferMessage(
            fromNodeUId: 'coord',
            sessionId: 'TestSession',
            targetNode: me,
          ),
        );
        await spy.settle();

        final test = spy.sent<ConnectionTestMessage>().single;
        expect(test.fromNodeUId, 'p1');
        expect(
          spy.sent<JoinRequestMessage>(),
          isEmpty,
          reason: 'the join request must wait for the handshake',
        );

        // Play the coordinator: confirm the test.
        await handler.handleMessage(
          ConnectionTestResponseMessage(
            fromNodeUId: 'coord',
            testId: test.testId,
            confirmed: true,
          ),
        );
        await offerHandled;
        await spy.settle();

        final request = spy.sent<JoinRequestMessage>().single;
        expect(request.fromNodeUId, 'p1');
        expect(request.requestingNode.uId, 'p1');
        expect(request.sessionId, 'TestSession');
      },
    );

    test('a join offer for another node is ignored', () async {
      await handler.handleMessage(
        JoinOfferMessage(
          fromNodeUId: 'coord',
          sessionId: 'TestSession',
          targetNode: participant('other'),
        ),
      );
      await spy.settle();
      expect(spy.outgoing, isEmpty);
    });

    test('topology updates add and remove by difference', () async {
      await handler.handleMessage(
        TopologyUpdateMessage(
          fromNodeUId: 'coord',
          topology: [coordinatorNode('coord'), participant('p1')],
        ),
      );
      await spy.settle();
      expect(state.connectedNodes.map((n) => n.uId), ['coord', 'p1']);

      await handler.handleMessage(
        TopologyUpdateMessage(
          fromNodeUId: 'coord',
          topology: [coordinatorNode('coord'), participant('p2')],
        ),
      );
      await spy.settle();
      expect(
        state.connectedNodes.map((n) => n.uId),
        unorderedEquals(['coord', 'p2']),
        reason: 'p1 dropped out of the topology and should be removed',
      );
    });

    test('sendHeartbeat and announceLeaving emit the right messages', () async {
      await handler.sendHeartbeat();
      await handler.announceLeaving();
      await spy.settle();

      final heartbeat = spy.sent<HeartbeatMessage>().single;
      expect(heartbeat.fromNodeUId, 'p1');
      expect(heartbeat.isCoordinator, isFalse);
      expect(spy.sent<NodeLeavingMessage>().single.leavingNodeUId, 'p1');
    });

    group('the ready gate', () {
      test(
        'stream commands are dropped before the participant is ready',
        () async {
          expect(state.phase, isNot(CoordinationPhase.ready));

          await handler.handleMessage(
            CreateStreamMessage(
              fromNodeUId: 'coord',
              streamName: 'TestData',
              streamConfig: streamConfig(),
            ),
          );
          await spy.settle();

          expect(
            spy.emitted<StreamCreateEvent>(),
            isEmpty,
            reason: 'commands arriving before readiness must not be acted on',
          );
        },
      );

      test('the same command is honoured once ready', () async {
        state.transitionTo(CoordinationPhase.ready);

        await handler.handleMessage(
          CreateStreamMessage(
            fromNodeUId: 'coord',
            streamName: 'TestData',
            streamConfig: streamConfig(),
          ),
        );
        await spy.settle();

        final event = spy.emitted<StreamCreateEvent>().single;
        expect(event.streamName, 'TestData');
        expect(event.streamConfig.channels, 2);
      });

      test('every stream command maps to its event once ready', () async {
        state.transitionTo(CoordinationPhase.ready);
        final config = streamConfig();

        await handler.handleMessage(
          StartStreamMessage(
            fromNodeUId: 'coord',
            streamName: 'TestData',
            streamConfig: config,
          ),
        );
        await handler.handleMessage(
          PauseStreamMessage(fromNodeUId: 'coord', streamName: 'TestData'),
        );
        await handler.handleMessage(
          ResumeStreamMessage(
            fromNodeUId: 'coord',
            streamName: 'TestData',
            flushBeforeResume: false,
          ),
        );
        await handler.handleMessage(
          FlushStreamMessage(fromNodeUId: 'coord', streamName: 'TestData'),
        );
        await handler.handleMessage(
          StopStreamMessage(fromNodeUId: 'coord', streamName: 'TestData'),
        );
        await handler.handleMessage(
          DestroyStreamMessage(fromNodeUId: 'coord', streamName: 'TestData'),
        );
        await spy.settle();

        expect(spy.emitted<StreamStartEvent>(), hasLength(1));
        expect(spy.emitted<StreamPauseEvent>(), hasLength(1));
        expect(
          spy.emitted<StreamResumeEvent>().single.flushBeforeResume,
          isFalse,
        );
        expect(spy.emitted<StreamFlushEvent>(), hasLength(1));
        expect(spy.emitted<StreamStopEvent>(), hasLength(1));
        expect(spy.emitted<StreamDestroyEvent>(), hasLength(1));
      });

      test('config updates surface as ConfigUpdateEvent once ready', () async {
        state.transitionTo(CoordinationPhase.ready);
        await handler.handleMessage(
          ConfigUpdateMessage(fromNodeUId: 'coord', config: {'rate': 60}),
        );
        await spy.settle();
        expect(spy.emitted<ConfigUpdateEvent>().single.config, {'rate': 60});
      });
    });
  });
}

JoinRequestMessage _join(String uId) => JoinRequestMessage(
  fromNodeUId: uId,
  requestingNode: participant(uId),
  sessionId: 'TestSession',
);
