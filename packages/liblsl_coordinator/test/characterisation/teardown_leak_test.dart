/// Does a disposed session actually release its LSL resources?
///
/// The participation-mode conformance suite showed a mode that passes alone
/// but fails once another three-node test has run in the same process, with
/// no error from `leave()` or `dispose()`. That points at resources surviving
/// a teardown that reports success.
///
/// This measures it directly rather than inferring it: after a session is
/// fully disposed, nothing it published should still be resolvable on the
/// network. A leak here matters well beyond tests — it would accumulate in any
/// long-running process that creates and tears down sessions or streams.
@Tags(['lsl', 'integration'])
library;

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:test/test.dart';

import '../support/lsl_harness.dart';

/// Streams still published for [sessionName], resolved with a predicate
/// scoped to exactly this session.
///
/// A predicate rather than `LSL.resolveStreams` plus string matching: resolve
/// is machine-wide, `dart test` runs files in parallel, and other LSL suites
/// publish at the same time. Scoping the query to the session under test makes
/// the assertion immune to that instead of merely unlikely to trip on it.
Future<List<String>> resolveSession(String sessionName) async {
  final streams = await LslDiscovery.discoverOnceByPredicate(
    LSLStreamInfoHelper.generatePredicate(sessionName: sessionName),
    timeout: const Duration(milliseconds: 500),
    maxStreams: 50,
  );
  final found = [
    for (final info in streams) '${info.streamName} | ${info.sourceId}',
  ];
  for (final info in streams) {
    info.destroy();
  }
  return found;
}

/// Waits until nothing is published for [sessionName], returning what remains
/// (empty on success).
///
/// Polling rather than a fixed pause: outlets are torn down asynchronously and
/// LSL's resolver caches for `forgetAfter`, so release time varies with load.
/// A real leak still fails — it just takes the full deadline to say so.
Future<List<String>> awaitReleased(
  String sessionName, {
  // Deliberately generous. Release is asynchronous and its duration varies
  // with machine load — after the other LSL suites have run, 20s was
  // occasionally too tight and produced a false leak report. A real leak
  // still fails, it just takes the full deadline to say so, and only a
  // failing run pays the cost.
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  var remaining = await resolveSession(sessionName);
  while (remaining.isNotEmpty && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    remaining = await resolveSession(sessionName);
  }
  return remaining;
}

void main() {
  useLoopbackLsl();

  /// Builds, joins, uses and disposes one coordinator + one participant, all
  /// named with [marker] so their streams can be found afterwards.
  Future<String> runSession(
    String marker, {
    required bool withDataStream,
  }) async {
    final sessionName = uniqueSessionName(marker);
    final sessions = <LSLCoordinationSession>[];

    for (final entry in {'coord-$marker': 0.1, 'part-$marker': 0.9}.entries) {
      final session = LSLCoordinationSession(
        testCoordinationConfig(sessionName: sessionName, maxNodes: 2),
        thisNodeConfig: testNodeConfig(
          name: entry.key,
          randomRoll: entry.value,
        ),
      );
      sessions.add(session);
      await session.initialize();
      await session.join(const Duration(seconds: 3));
    }

    await sessions.first.waitForMinNodes(
      2,
      timeout: const Duration(seconds: 10),
    );

    if (withDataStream) {
      final config = DataStreamConfig(
        name: 'Leak-$marker',
        channels: 2,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
        participationMode:
            StreamParticipationMode.sendParticipantsReceiveCoordinator,
      );
      // Only the coordinator creates the stream. Participants build theirs
      // automatically when the createStream command arrives, and the
      // coordinator's createDataStream does not return until they report
      // ready — so subscribing to streamCreate here would create each
      // participant stream twice.
      await sessions.first.createDataStream(config);
      await sessions.first.startStream('Leak-$marker');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sessions.first.stopStream('Leak-$marker');
    }

    for (final session in sessions.reversed) {
      await session.leave();
      await session.dispose();
    }
    return sessionName;
  }

  group('resource release after teardown', () {
    test('a coordination-only session leaves nothing resolvable', () async {
      final sessionName = await runSession(
        'LeakCoordOnly',
        withDataStream: false,
      );

      expect(
        await awaitReleased(sessionName),
        isEmpty,
        reason:
            'every outlet from a disposed session must be gone; anything '
            'still resolvable is a leaked LSL resource',
      );
    });

    test('a session with a data stream leaves nothing resolvable', () async {
      final sessionName = await runSession(
        'LeakWithData',
        withDataStream: true,
      );

      expect(
        await awaitReleased(sessionName),
        isEmpty,
        reason: 'data-stream outlets must be released along with the session',
      );
    });

    test('creating the same data stream twice leaks nothing', () async {
      // Regression test for how the "teardown leak" actually arose.
      //
      // Participants build their streams automatically on the coordinator's
      // createStream command, so application code that also calls
      // createDataStream — a reasonable reaction to a streamCreate event —
      // used to run the setup path twice. Two concurrent createOutlet() calls
      // both passed its null check (it awaited before assigning), both built
      // an outlet, and the second overwrote the first. The orphan stayed
      // published with nothing referencing it, so dispose() could not reach
      // it, and the second listen on the single-subscription outgoing
      // controller threw `Bad state: Stream has already been listened to`.
      const marker = 'LeakDoubleCreate';
      final sessionName = uniqueSessionName(marker);
      final sessions = <LSLCoordinationSession>[];

      for (final entry in {'c-$marker': 0.1, 'p-$marker': 0.9}.entries) {
        final session = LSLCoordinationSession(
          testCoordinationConfig(sessionName: sessionName, maxNodes: 2),
          thisNodeConfig: testNodeConfig(
            name: entry.key,
            randomRoll: entry.value,
          ),
        );
        sessions.add(session);
        await session.initialize();
        await session.join(const Duration(seconds: 3));
      }
      await sessions.first.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 10),
      );

      final config = DataStreamConfig(
        name: 'Leak-$marker',
        channels: 2,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
        participationMode:
            StreamParticipationMode.sendParticipantsReceiveCoordinator,
      );

      final first = await sessions.first.createDataStream(config);

      // Sequential and concurrent repeats must both be safe.
      final second = await sessions.first.createDataStream(config);
      final concurrent = await Future.wait([
        sessions.first.createDataStream(config),
        sessions.first.createDataStream(config),
      ]);

      expect(identical(first, second), isTrue, reason: 'must be idempotent');
      for (final stream in concurrent) {
        expect(identical(first, stream), isTrue);
      }

      // The participant was told to create its stream too; asking it again
      // must not build a second outlet behind its back.
      await sessions[1].createDataStream(config);

      for (final session in sessions.reversed) {
        await session.leave();
        await session.dispose();
      }
      expect(
        await awaitReleased(marker),
        isEmpty,
        reason: 'a duplicated create must not leave an orphaned outlet',
      );
    });

    test('repeated create/dispose cycles do not accumulate streams', () async {
      // The shape that broke the conformance suite: several full sessions in
      // one process, one after another.
      final sessionNames = <String>[];
      for (var cycle = 0; cycle < 3; cycle++) {
        sessionNames.add(
          await runSession('LeakCycles$cycle', withDataStream: true),
        );
      }

      for (final sessionName in sessionNames) {
        expect(
          await awaitReleased(sessionName),
          isEmpty,
          reason: 'nothing from cycle $sessionName should still be published',
        );
      }
    });
  });
}
