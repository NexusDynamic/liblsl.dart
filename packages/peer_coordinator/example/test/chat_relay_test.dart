/// Proves the part of this example that is easy to get wrong: a participant's
/// line only ever reaches the coordinator, so without the relay in
/// [ChatSession] two participants would never see each other.
///
/// Runs three whole coordination sessions over one [InMemoryBus] — no hub, no
/// sockets, no timing luck.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator_example/src/chat/chat_message.dart';
import 'package:peer_coordinator_example/src/chat/chat_session.dart';

void main() {
  late InMemoryBus bus;
  late List<ChatSession> sessions;

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
    }
    sessions = [];
    bus.dispose();
  });

  /// Joins a node. Sequential calls decide the election: the default promotion
  /// strategy defers to the earliest starter, so the first node coordinates.
  Future<ChatSession> join(String name) async {
    final session = ChatSession(
      displayName: name,
      roomName: 'test_room',
      transportConfig: InMemoryTransportConfig(bus: bus),
      maxNodes: 3,
      heartbeatInterval: const Duration(milliseconds: 50),
      discoveryInterval: const Duration(milliseconds: 25),
      nodeTimeout: const Duration(milliseconds: 400),
    );
    sessions.add(session);
    final joined = await session.connect(
      timeout: const Duration(milliseconds: 500),
    );
    expect(joined, isTrue, reason: session.failureReason);
    return session;
  }

  List<ChatMessage> chatLines(ChatSession session) => session.messages.value
      .where((m) => m.kind == ChatMessageKind.chat)
      .toList(growable: false);

  /// Polls rather than waiting a fixed slice, so the test is neither flaky nor
  /// slower than it has to be.
  Future<void> waitForLines(ChatSession session, int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (chatLines(session).length < count) {
      if (!DateTime.now().isBefore(deadline)) {
        fail(
          'expected $count chat lines on ${session.displayName}, '
          'saw ${chatLines(session).length}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a lone node coordinates and sees its own line once', () async {
    final solo = await join('solo');
    expect(solo.isCoordinator.value, isTrue);

    await solo.send('hello');
    // Give any echo of its own broadcast time to come back and be deduped.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(chatLines(solo).map((m) => m.text), ['hello']);
  });

  test(
    'the coordinator relays a participant line to other participants',
    () async {
      final coordinator = await join('ana');
      final first = await join('bo');
      final second = await join('cy');

      expect(coordinator.isCoordinator.value, isTrue);
      expect(first.isCoordinator.value, isFalse);
      expect(second.isCoordinator.value, isFalse);

      await first.send('anyone there?');

      await waitForLines(coordinator, 1);
      await waitForLines(second, 1);

      // The relay must be invisible: the line still belongs to its author, not
      // to the coordinator that forwarded it.
      final onSecond = chatLines(second).single;
      expect(onSecond.text, 'anyone there?');
      expect(onSecond.fromName, 'bo');
      expect(onSecond.fromUId, first.thisNodeUId);

      expect(chatLines(coordinator).single.fromName, 'bo');
      expect(chatLines(first).single.text, 'anyone there?');
    },
  );

  test('a coordinator line reaches every participant', () async {
    final coordinator = await join('ana');
    final first = await join('bo');
    final second = await join('cy');

    await coordinator.send('welcome');

    await waitForLines(first, 1);
    await waitForLines(second, 1);

    expect(chatLines(first).single.fromName, 'ana');
    expect(chatLines(second).single.fromName, 'ana');
  });

  test('no line is ever rendered twice', () async {
    final coordinator = await join('ana');
    final participant = await join('bo');

    await coordinator.send('one');
    await participant.send('two');
    await participant.send('three');

    await waitForLines(coordinator, 3);
    await waitForLines(participant, 3);
    // Anything duplicated would land after the third line, so settle first.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    for (final session in [coordinator, participant]) {
      final lines = chatLines(session);
      expect(lines, hasLength(3), reason: session.displayName);
      expect(
        lines.map((m) => m.id).toSet(),
        hasLength(3),
        reason: 'duplicate ids on ${session.displayName}',
      );
      expect(lines.map((m) => m.text), containsAll(['one', 'two', 'three']));
    }
  });

  test('everyone sees everyone in the roster', () async {
    final coordinator = await join('ana');
    final participant = await join('bo');

    Future<void> waitForRoster(ChatSession session) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (session.roster.value.length < 2) {
        if (!DateTime.now().isBefore(deadline)) {
          fail('${session.displayName} never saw both nodes');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    await waitForRoster(coordinator);
    await waitForRoster(participant);

    expect(
      coordinator.roster.value.map((m) => m.name),
      containsAll(['ana', 'bo']),
    );
    expect(
      participant.roster.value.map((m) => m.name),
      containsAll(['ana', 'bo']),
    );
    expect(
      coordinator.roster.value.where((m) => m.isCoordinator).map((m) => m.name),
      ['ana'],
    );
  });
}
