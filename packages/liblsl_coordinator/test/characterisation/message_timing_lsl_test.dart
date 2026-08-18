/// Timing survives the trip on a real LSL network, for coordination messages
/// as well as data samples.
///
/// The in-memory equivalent (`peer_coordinator`'s `message_timing_test.dart`)
/// proves the plumbing; this proves the LSL end of it — that the sender's
/// `lsl_local_clock()` reading and the `lsl_time_correction` needed to
/// interpret it both reach the consumer, on the coordination stream and not
/// only the data stream.
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

void main() {
  useLoopbackLsl();

  late List<LSLCoordinationSession> sessions;
  late String sessionName;

  setUp(() {
    sessions = [];
    sessionName = uniqueSessionName('TimingTest');
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
  });

  Future<LSLCoordinationSession> joined(
    String name, {
    required double randomRoll,
  }) async {
    final session = LSLCoordinationSession(
      testCoordinationConfig(sessionName: sessionName, maxNodes: 2),
      thisNodeConfig: testNodeConfig(name: name, randomRoll: randomRoll),
    );
    sessions.add(session);
    await session.initialize();
    await session.join(const Duration(seconds: 3));
    return session;
  }

  group('coordination stream timing', () {
    test('a user message carries the sender LSL clock and a correction', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));

      final delivered = participant.waitForUserMessage(
        'probe',
        timeout: const Duration(seconds: 5),
      );
      await coordinator.sendUserMessage('probe', 'timing probe', {'n': 1});
      final event = await delivered;

      final timing = event.timing;
      expect(
        timing,
        isNotNull,
        reason:
            'coordination events must carry timing; this is the whole point — '
            'the transport measured the trip and the decode used to discard it',
      );

      // The sender's lsl_local_clock() reading, arriving as the LSL sample
      // timestamp. LSL clocks start at process load, so this is a positive
      // number of seconds, not an epoch timestamp.
      expect(timing!.sourceClock, isNotNull);
      expect(timing.sourceClock!, greaterThan(0));

      // Captured in the inlet isolate at pull time, in the local LSL domain.
      expect(timing.receivedClock, greaterThan(0));

      // Both nodes are in one process, so they share an LSL clock and the
      // correction is ~0 — but it must be *present*, because null would mean
      // "no estimate yet" and make transit unknowable.
      expect(
        timing.clockOffset,
        isNotNull,
        reason: 'the inlet should have a time-correction estimate by now',
      );
      expect(timing.clockOffset!.abs(), lessThan(0.1));

      // The LSL source_id of the sending outlet.
      expect(timing.sourceId, isNotNull);
      expect(timing.sourceId, isNotEmpty);
    });

    test('transit time is finite and small on loopback', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));

      final delivered = participant.waitForUserMessage(
        'probe',
        timeout: const Duration(seconds: 5),
      );
      await coordinator.sendUserMessage('probe', 'timing probe', {});
      final event = await delivered;

      final transit = event.timing!.transitSeconds;
      expect(transit, isNotNull);
      // Deliberately loose. This asserts the arithmetic is in seconds and the
      // two readings share a clock domain, not that loopback is fast. A tiny
      // negative value is legitimate — the correction is an estimate with its
      // own uncertainty — so the lower bound allows for it rather than
      // pretending the estimate is exact.
      expect(transit!, greaterThan(-0.05));
      expect(transit, lessThan(2.0));
    });
  });

  group('data stream timing', () {
    test(
      'data samples carry the same timing as coordination messages',
      () async {
        final coordinator = await joined('coord', randomRoll: 0.1);
        final participant = await joined('participant', randomRoll: 0.9);
        await coordinator.waitForMinNodes(
          2,
          timeout: const Duration(seconds: 5),
        );

        final streamConfig = DataStreamConfig(
          name: 'TimingData',
          channels: 2,
          sampleRate: 20.0,
          dataType: StreamDataType.double64,
          participationMode:
              StreamParticipationMode.sendParticipantsReceiveCoordinator,
        );

        final received = Completer<IMessage>();
        final stream = await coordinator.createDataStream(streamConfig);
        final sub = stream.inbox.listen((message) {
          if (!received.isCompleted) received.complete(message);
        });

        final producerReady = Completer<LSLDataStream>();
        final startSub = participant.events.streamStart.listen((event) async {
          if (!producerReady.isCompleted) {
            producerReady.complete(
              await participant.getDataStream(event.streamName),
            );
          }
        });

        await coordinator.startStream('TimingData');
        final producer = await producerReady.future.timeout(
          const Duration(seconds: 10),
        );

        final pump = Timer.periodic(const Duration(milliseconds: 50), (_) {
          if (producer.started) producer.sendData([1.0, 2.0]);
        });

        final message = await received.future.timeout(
          const Duration(seconds: 10),
        );
        pump.cancel();
        await sub.cancel();
        await startSub.cancel();

        final timing = message.timing;
        expect(timing, isNotNull);
        expect(timing!.sourceClock, isNotNull);
        expect(timing.receivedClock, greaterThan(0));
        expect(timing.sourceId, isNotNull);

        await coordinator.stopStream('TimingData');
      },
    );
  });
}
