/// `LSLTransportConfig.eventDrivenInlets` on a real LSL network: samples are
/// received as they arrive instead of at the next poll, and the stream
/// lifecycle (pause, resume, flush, stop) still behaves as it does when
/// polling.
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
    sessionName = uniqueSessionName('EventDriven');
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
      testCoordinationConfig(
        sessionName: sessionName,
        maxNodes: 2,
        eventDrivenInlets: true,
      ),
      thisNodeConfig: testNodeConfig(name: name, randomRoll: randomRoll),
    );
    sessions.add(session);
    await session.initialize();
    await session.join(const Duration(seconds: 3));
    return session;
  }

  test(
    'a data stream delivers every sample without the polling delay',
    () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));

      // At 20 Hz a polled inlet is read every 10 ms (the slowest it polls), so
      // polled transit times average about 5 ms.
      final stream = await coordinator.createDataStream(
        DataStreamConfig(
          name: 'EventData',
          channels: 1,
          sampleRate: 20.0,
          dataType: StreamDataType.double64,
          participationMode:
              StreamParticipationMode.sendParticipantsReceiveCoordinator,
        ),
      );
      final received = <IMessage>[];
      final sub = stream.inbox.listen(received.add);

      final producerReady = Completer<LSLDataStream>();
      final startSub = participant.events.streamStart.listen((event) async {
        if (!producerReady.isCompleted) {
          producerReady.complete(
            await participant.getDataStream(event.streamName),
          );
        }
      });
      await coordinator.startStream('EventData');
      final producer = await producerReady.future.timeout(
        const Duration(seconds: 10),
      );

      Future<void> send(int from, int count) async {
        for (var i = from; i < from + count; i++) {
          await producer.sendData([i.toDouble()]);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      Future<void> settle(int count) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (received.length < count && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      // Until the outlet has its consumer, liblsl drops what is pushed.
      await Future<void>.delayed(const Duration(seconds: 1));
      await send(0, 50);
      await settle(50);
      expect(
        [for (final m in received) m.data[0]],
        [for (var i = 0; i < 50; i++) i.toDouble()],
      );

      final transits = [for (final m in received) ?m.timing?.transitSeconds]
        ..sort();
      expect(transits, isNotEmpty);
      expect(
        transits[transits.length ~/ 2],
        lessThan(0.003),
        reason: 'median transit should be well under the 10 ms poll interval',
      );

      // Paused, nothing is read; what was sent meanwhile is dropped by the
      // flush on resume, as it is when polling.
      await stream.pauseStream();
      await send(100, 5);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(received, hasLength(50));
      await stream.resumeStream(flushBeforeResume: true);
      await send(200, 5);
      await settle(55);
      expect(
        [for (final m in received.skip(50)) m.data[0]],
        [for (var i = 200; i < 205; i++) i.toDouble()],
      );

      await sub.cancel();
      await startSub.cancel();
      await coordinator.stopStream('EventData');
    },
  );

  test('coordination messages arrive without the polling delay', () async {
    final coordinator = await joined('coord', randomRoll: 0.1);
    final participant = await joined('participant', randomRoll: 0.9);
    await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));
    // Let the first clock-offset estimate arrive.
    await Future<void>.delayed(const Duration(seconds: 1));

    final transits = <double>[];
    final sub = participant.events.userMessages.listen((event) {
      final transit = event.timing?.transitSeconds;
      if (event.messageType == 'probe' && transit != null) {
        transits.add(transit);
      }
    });
    for (var i = 0; i < 20; i++) {
      await coordinator.sendUserMessage('probe', 'timing probe', {'n': i});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();

    expect(transits.length, greaterThanOrEqualTo(15));
    transits.sort();
    expect(transits[transits.length ~/ 2], lessThan(0.003));
  });
}
