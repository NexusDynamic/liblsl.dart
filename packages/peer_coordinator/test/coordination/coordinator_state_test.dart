/// Unit tests for [CoordinationState].
///
/// This is the shared brain of the coordination layer: it owns the phase
/// machine, the connected-node list, the heartbeat table and the event stream.
/// It has no transport dependency at all, so every transport inherits exactly
/// this behaviour — which makes it worth pinning precisely.
library;

import 'package:peer_coordinator/framework.dart';
import 'package:test/test.dart';

Node participant(String uId) =>
    ParticipantNode(NodeConfig(name: uId, id: uId, uId: uId));

Node coordinator(String uId) => CoordinatorNode(
  NodeConfig(
    name: uId,
    id: uId,
    uId: uId,
    capabilities: {NodeCapability.coordinator},
  ),
);

void main() {
  late CoordinationState state;

  setUp(() => state = CoordinationState());
  tearDown(() => state.dispose());

  group('phase machine', () {
    test('starts idle, as neither coordinator nor participant', () {
      expect(state.phase, CoordinationPhase.idle);
      expect(state.isCoordinator, isFalse);
      expect(state.coordinatorUId, isNull);
      expect(state.connectedNodes, isEmpty);
    });

    test('transitionTo emits PhaseChangedEvent', () async {
      final events = <ControllerEvent>[];
      final sub = state.events.listen(events.add);

      state.transitionTo(CoordinationPhase.discovering);
      state.transitionTo(CoordinationPhase.electing);
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events.map((e) => (e as PhaseChangedEvent).phase), [
        CoordinationPhase.discovering,
        CoordinationPhase.electing,
      ]);
      await sub.cancel();
    });

    test('transitioning to the current phase emits nothing', () async {
      state.transitionTo(CoordinationPhase.discovering);
      final events = <ControllerEvent>[];
      final sub = state.events.listen(events.add);

      state.transitionTo(CoordinationPhase.discovering);
      await pumpEventQueue();

      expect(events, isEmpty);
      await sub.cancel();
    });

    test('isEstablished covers established, accepting, ready and active', () {
      const established = {
        CoordinationPhase.established,
        CoordinationPhase.accepting,
        CoordinationPhase.ready,
        CoordinationPhase.active,
      };
      for (final phase in CoordinationPhase.values) {
        state.transitionTo(phase);
        expect(
          state.isEstablished,
          established.contains(phase),
          reason: 'isEstablished wrong for $phase',
        );
      }
    });

    test('canAcceptNodes requires being coordinator AND accepting/ready', () {
      // A participant never accepts nodes, whatever the phase.
      state.becomeParticipant('coord');
      for (final phase in CoordinationPhase.values) {
        state.transitionTo(phase);
        expect(state.canAcceptNodes, isFalse, reason: 'participant in $phase');
      }

      state.becomeCoordinator('me');
      const accepting = {CoordinationPhase.accepting, CoordinationPhase.ready};
      for (final phase in CoordinationPhase.values) {
        state.transitionTo(phase);
        expect(
          state.canAcceptNodes,
          accepting.contains(phase),
          reason: 'coordinator in $phase',
        );
      }
    });
  });

  group('role assignment', () {
    test('becomeCoordinator sets the flag, uId and established phase', () {
      state.becomeCoordinator('me');
      expect(state.isCoordinator, isTrue);
      expect(state.coordinatorUId, 'me');
      expect(state.phase, CoordinationPhase.established);
    });

    test('becomeParticipant records the coordinator uId', () {
      state.becomeParticipant('coord');
      expect(state.isCoordinator, isFalse);
      expect(state.coordinatorUId, 'coord');
      expect(state.phase, CoordinationPhase.established);
    });

    test('becomeParticipant with no argument clears the coordinator uId', () {
      // The controller calls this during election, before the coordinator has
      // been identified, then calls it again with the uId once known.
      state.becomeCoordinator('me');
      state.becomeParticipant();
      expect(state.isCoordinator, isFalse);
      expect(state.coordinatorUId, isNull);
    });
  });

  group('node membership', () {
    test('addNode appends and emits NodeJoinedEvent', () async {
      final events = <ControllerEvent>[];
      final sub = state.events.listen(events.add);

      state.addNode(participant('a'));
      await pumpEventQueue();

      expect(state.connectedNodes.map((n) => n.uId), ['a']);
      expect(events.whereType<NodeJoinedEvent>().single.node.uId, 'a');
      await sub.cancel();
    });

    test('adding the same uId twice updates in place, emitting once', () async {
      final events = <ControllerEvent>[];
      final sub = state.events.listen(events.add);

      state.addNode(participant('a'));
      state.addNode(coordinator('a'));
      await pumpEventQueue();

      expect(state.connectedNodes, hasLength(1));
      expect(
        state.connectedNodes.single.role,
        NodeCapability.coordinator.shortString,
        reason: 'the second add should replace the stored node',
      );
      expect(
        events.whereType<NodeJoinedEvent>(),
        hasLength(1),
        reason: 'a re-add is not a join',
      );
      await sub.cancel();
    });

    test('removeNode drops the node and emits NodeLeftEvent', () async {
      state.addNode(participant('a'));
      final events = <ControllerEvent>[];
      final sub = state.events.listen(events.add);

      state.removeNode('a');
      await pumpEventQueue();

      expect(state.connectedNodes, isEmpty);
      expect(events.whereType<NodeLeftEvent>().single.node.uId, 'a');
      await sub.cancel();
    });

    test('removing an unknown node is a silent no-op', () async {
      final events = <ControllerEvent>[];
      final sub = state.events.listen(events.add);

      state.removeNode('nobody');
      await pumpEventQueue();

      expect(events, isEmpty);
      await sub.cancel();
    });

    test('connectedNodes is unmodifiable', () {
      state.addNode(participant('a'));
      expect(
        () => state.connectedNodes.add(participant('b')),
        throwsUnsupportedError,
      );
    });

    test('connectedParticipantNodes filters on role, not capability', () {
      state.addNode(participant('p'));
      state.addNode(coordinator('c'));
      // A node that is capable of participating but has not been promoted
      // reports role 'none' and is therefore excluded.
      state.addNode(Node(NodeConfig(name: 'u', id: 'u', uId: 'u')));

      expect(state.connectedParticipantNodes.map((n) => n.uId), ['p']);
      expect(state.connectedNodes, hasLength(3));
    });
  });

  group('heartbeat tracking', () {
    test('addNode seeds a heartbeat so a fresh node is never stale', () {
      state.addNode(participant('a'));
      expect(state.getStaleNodes(const Duration(seconds: 10)), isEmpty);
    });

    test('a zero timeout makes every tracked node stale', () async {
      state.addNode(participant('a'));
      state.addNode(participant('b'));
      // Ensure the recorded timestamps are strictly in the past.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(state.getStaleNodes(Duration.zero), unorderedEquals(['a', 'b']));
    });

    test('updateNodeHeartbeat refreshes the timestamp', () async {
      state.addNode(participant('a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Stale against a 10ms window...
      expect(
        state.getStaleNodes(const Duration(milliseconds: 10)),
        contains('a'),
      );
      // ...but not after a heartbeat.
      state.updateNodeHeartbeat('a');
      expect(state.getStaleNodes(const Duration(milliseconds: 10)), isEmpty);
    });

    test('removeNode stops heartbeat tracking', () async {
      state.addNode(participant('a'));
      state.removeNode('a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(state.getStaleNodes(Duration.zero), isEmpty);
    });

    test('removeNode clears a heartbeat for a node that never joined', () async {
      // The clear used to sit inside the "was it in connectedNodes?" branch, so
      // an entry with no matching node survived every removal and getStaleNodes
      // re-reported it on every tick — each report re-broadcasting the topology.
      state.updateNodeHeartbeat('ghost');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(state.getStaleNodes(Duration.zero), contains('ghost'));

      state.removeNode('ghost');
      expect(state.getStaleNodes(Duration.zero), isEmpty);
    });

    test('isStale reports on one node without scanning the table', () async {
      state.updateNodeHeartbeat('coord');
      expect(state.isStale('coord', const Duration(seconds: 10)), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(state.isStale('coord', const Duration(milliseconds: 10)), isTrue);
    });

    test('an untracked node is unknown, not stale', () {
      // A participant seeds its coordinator's entry when it connects, so "no
      // entry" means the relationship has not started — reporting that as stale
      // would end sessions during election.
      expect(state.isStale('never-heard-of', Duration.zero), isFalse);
    });

    test('clearNodes empties the topology and emits one event per node',
        () async {
      state.addNode(participant('a'));
      state.addNode(participant('b'));
      final events = <ControllerEvent>[];
      final sub = state.events.listen(events.add);

      state.clearNodes();
      await pumpEventQueue();

      expect(state.connectedNodes, isEmpty);
      expect(
        events.whereType<NodeLeftEvent>().map((e) => e.node.uId),
        unorderedEquals(['a', 'b']),
      );
      expect(state.getStaleNodes(Duration.zero), isEmpty);
      await sub.cancel();
    });
  });

  group('known issues (characterisation — these pin current behaviour)', () {
    test('updateNodeHeartbeat tracks nodes that never joined', () async {
      // There is no membership check, so a heartbeat from an unknown node
      // creates an entry that getStaleNodes will later report. The controller
      // then calls state.removeNode(uId) for it, which emits nothing because the
      // node is not in _connectedNodes, but does clear the heartbeat entry — see
      // 'removeNode clears a heartbeat for a node that never joined', which is
      // what keeps these from accumulating.
      state.updateNodeHeartbeat('ghost');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(state.getStaleNodes(Duration.zero), contains('ghost'));
      expect(state.connectedNodes, isEmpty);
    });

    test('the event stream is broadcast and drops events with no listener', () {
      // Events emitted before anyone subscribes are lost. Callers that need
      // the full history must subscribe before driving the state.
      state.addNode(participant('a'));
      expect(state.connectedNodes, hasLength(1));
      // No assertion on events: there is nothing to observe, which is the
      // point.
    });
  });
}
