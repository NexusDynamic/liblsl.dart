/// How the inlet worker admits a peer it has to open.
///
/// Two field faults are pinned here, both from the 2026-09-11 session:
///
///  * An inlet that failed to open was reported as a success. The main isolate
///    kept the peer registered, so it was never retried, and the node looked
///    connected while nothing was read from it.
///  * Opening ran as a synchronous native call on the worker thread, so while
///    one inlet was being opened no other inlet on that stream was polled. On
///    the coordination stream that is every peer's heartbeat: the coordinator
///    read nothing from any node for 2.5 s.
@Tags(['lsl'])
library;

import 'dart:async';

import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl/isolate/isolate_manager.dart';
import 'package:test/test.dart';

void main() {
  final stamp = DateTime.now().microsecondsSinceEpoch;

  setUpAll(() {
    LSL.setConfigContent(
      LSLApiConfig(
        ipv6: IPv6Mode.disable,
        resolveScope: ResolveScope.link,
        listenAddress: '127.0.0.1',
        // Distinct from the groups the other LSL tests and examples use.
        addressesOverride: ['224.0.0.186'],
        knownPeers: ['127.0.0.1'],
        sessionId: 'InletOpenTest_$stamp',
        portRange: 256,
        logLevel: -2,
        unicastMinRTT: 0.1,
        multicastMinRTT: 0.1,
      ),
    );
  });

  Future<StreamInletIsolate> startedWorker(String id) async {
    final worker = IsolateStreamManager.createInletIsolate(
      streamId: id,
      dataType: StreamDataType.double64,
      useBusyWaitInlets: false,
      useBusyWaitOutlets: false,
      pollingInterval: const Duration(milliseconds: 5),
      isolateDebugName: 'inlet:$id',
    );
    await worker.create();
    await worker.start();
    return worker;
  }

  /// A stream info nothing publishes. Opening an inlet on it cannot succeed,
  /// and takes the full create timeout to find that out.
  Future<LSLStreamInfo> unservedInfo(String name) => LSL.createStreamInfo(
    streamName: name,
    channelCount: 2,
    sampleRate: 100.0,
    channelFormat: LSLChannelFormat.double64,
    sourceId: '$name-$stamp',
  );

  test('a peer that cannot be opened is reported, not admitted', () async {
    final worker = await startedWorker('unopenable');
    addTearDown(worker.dispose);
    final info = await unservedInfo('Nobody');
    addTearDown(info.destroy);

    await expectLater(
      worker.addInlet(info.streamInfo.address),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'opening an unreachable peer does not stop the others being polled',
    () async {
      final worker = await startedWorker('shared');
      addTearDown(worker.dispose);

      final servedSourceId = 'served-$stamp';
      final outletInfo = await LSL.createStreamInfo(
        streamName: 'Served',
        channelCount: 2,
        sampleRate: 100.0,
        channelFormat: LSLChannelFormat.double64,
        sourceId: servedSourceId,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: outletInfo,
        chunkSize: 1,
        useIsolates: false,
      );
      addTearDown(outlet.destroy);

      final resolved = await LSL.resolveStreamsByProperty(
        property: LSLStreamProperty.sourceId,
        value: servedSourceId,
        waitTime: 3.0,
        minStreamCount: 1,
      );
      expect(resolved, isNotEmpty, reason: 'the served outlet must resolve');
      await worker.addInlet(resolved.first.streamInfo.address);

      final arrivals = <DateTime>[];
      final sub = worker.incomingData.listen((_) => arrivals.add(DateTime.now()));
      addTearDown(sub.cancel);

      final pusher = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => outlet.pushSampleSync([1.0, 2.0]),
      );
      addTearDown(pusher.cancel);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (arrivals.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(arrivals, isNotEmpty, reason: 'samples should flow before the fault');

      final unserved = await unservedInfo('Unreachable');
      addTearDown(unserved.destroy);

      final windowStart = DateTime.now();
      await expectLater(
        worker.addInlet(unserved.streamInfo.address),
        throwsA(isA<StateError>()),
      );
      final windowEnd = DateTime.now();

      final during = [
        windowStart,
        ...arrivals.where(
          (t) => t.isAfter(windowStart) && t.isBefore(windowEnd),
        ),
        windowEnd,
      ];
      var worstGap = Duration.zero;
      for (var i = 1; i < during.length; i++) {
        final gap = during[i].difference(during[i - 1]);
        if (gap > worstGap) worstGap = gap;
      }

      expect(
        windowEnd.difference(windowStart),
        greaterThan(const Duration(milliseconds: 1500)),
        reason: 'the failed open should have taken most of its timeout, or '
            'this test measured nothing',
      );
      expect(
        worstGap,
        lessThan(const Duration(seconds: 1)),
        reason: 'the served inlet must keep delivering while another peer is '
            'being opened',
      );
    },
  );
}
