/// What the inlet worker does when an event-driven inlet's sample listener
/// ends without having been stopped.
///
/// It used to do nothing: the dead subscription stayed registered, so the
/// inlet was never listened to again, the peer stayed admitted, and the only
/// sign was samples that stopped arriving. These pin that it is reported to
/// the main isolate every time, and restarted unless that is turned off.
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
        addressesOverride: ['224.0.0.187'],
        knownPeers: ['127.0.0.1'],
        sessionId: 'InletListenerTest_$stamp',
        portRange: 256,
        logLevel: -2,
        unicastMinRTT: 0.1,
        multicastMinRTT: 0.1,
      ),
    );
  });

  /// An event-driven worker reading one served outlet that is pushed to
  /// every 10 ms, whose first [faults] listeners die after one sample.
  Future<({StreamInletIsolate worker, List<InletHealth> health, String source})>
  listeningWorker(
    String id, {
    required int faults,
    bool restartFailedListeners = true,
  }) async {
    final sourceId = '$id-$stamp';
    final outletInfo = await LSL.createStreamInfo(
      streamName: id,
      channelCount: 2,
      sampleRate: 100.0,
      channelFormat: LSLChannelFormat.double64,
      sourceId: sourceId,
    );
    final outlet = await LSL.createOutlet(
      streamInfo: outletInfo,
      chunkSize: 1,
      useIsolates: false,
    );
    final resolved = await LSL.resolveStreamsByProperty(
      property: LSLStreamProperty.sourceId,
      value: sourceId,
      waitTime: 3.0,
      minStreamCount: 1,
    );
    expect(resolved, isNotEmpty, reason: 'the served outlet must resolve');

    final worker = IsolateStreamManager.createInletIsolate(
      streamId: id,
      dataType: StreamDataType.double64,
      useBusyWaitInlets: false,
      useBusyWaitOutlets: false,
      eventDrivenInlets: true,
      restartFailedListeners: restartFailedListeners,
      debugListenerFaults: faults,
      pollingInterval: const Duration(milliseconds: 5),
      isolateDebugName: 'inlet:$id',
    );
    await worker.create();
    final health = <InletHealth>[];
    final healthSub = worker.listenerHealth.listen(health.add);
    await worker.start();
    await worker.addInlet(resolved.first.streamInfo.address);

    final pusher = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => outlet.pushSampleSync([1.0, 2.0]),
    );
    addTearDown(() async {
      pusher.cancel();
      await healthSub.cancel();
      await worker.dispose();
      await outlet.destroy();
      for (final info in resolved) {
        info.destroy();
      }
    });
    return (worker: worker, health: health, source: sourceId);
  }

  Future<void> until(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    required String reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('a listener that dies is reported and restarted', () async {
    final (:worker, :health, :source) = await listeningWorker(
      'restarted',
      faults: 1,
    );
    var samples = 0;
    final sub = worker.incomingData.listen((_) => samples++);
    addTearDown(sub.cancel);

    await until(
      () => health.isNotEmpty && health.last.healthy,
      reason: 'the listener should have died and come back',
    );
    expect(health, hasLength(2));
    final down = health.first;
    expect(down.sourceId, source);
    expect(down.healthy, isFalse);
    expect(down.consecutiveFailures, 1);
    expect(down.willRetry, isTrue);
    expect(down.error, contains('debugFailAfter'));
    expect(health.last.sourceId, source);
    expect(health.last.consecutiveFailures, 0);

    final before = samples;
    await until(
      () => samples > before + 20,
      reason: 'samples should be arriving again',
    );
  });

  test('a listener that keeps dying gets a new inlet', () async {
    // Three failures in a row is where the worker stops trusting the inlet.
    final (:worker, :health, source: _) = await listeningWorker(
      'reopened',
      faults: 3,
    );
    var samples = 0;
    final sub = worker.incomingData.listen((_) => samples++);
    addTearDown(sub.cancel);

    await until(
      () => health.isNotEmpty && health.last.healthy,
      reason: 'the listener should have come back on a reopened inlet',
    );
    expect(
      [for (final h in health.where((h) => !h.healthy)) h.consecutiveFailures],
      [1, 2, 3],
    );
    final before = samples;
    await until(
      () => samples > before + 20,
      reason: 'samples should be arriving on the reopened inlet',
    );
  });

  test('with restarting off it is reported and left alone', () async {
    final (:worker, :health, source: _) = await listeningWorker(
      'left-alone',
      faults: 1,
      restartFailedListeners: false,
    );
    var samples = 0;
    final sub = worker.incomingData.listen((_) => samples++);
    addTearDown(sub.cancel);

    await until(() => health.isNotEmpty, reason: 'the death must be reported');
    expect(health.single.healthy, isFalse);
    expect(health.single.willRetry, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final afterDeath = samples;
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(samples, afterDeath, reason: 'nothing should be reading the inlet');
    expect(health, hasLength(1));

    // The way back that was always there: a resume listens to every inlet.
    await worker.pause();
    await worker.resume(flushBeforeResume: false);
    await until(
      () => samples > afterDeath + 20,
      reason: 'a resume should start a listener again',
    );
  });

  test('a pause cancels a pending restart; the resume replaces it', () async {
    final (:worker, :health, source: _) = await listeningWorker(
      'paused',
      // Two, so the second death arms a 200 ms restart to pause inside.
      faults: 2,
    );
    var samples = 0;
    final sub = worker.incomingData.listen((_) => samples++);
    addTearDown(sub.cancel);

    await until(
      () => health.where((h) => !h.healthy).length == 2,
      reason: 'both faulty listeners should have died',
    );
    await worker.pause();
    final paused = samples;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(samples, paused, reason: 'a paused worker must not restart');

    await worker.resume(flushBeforeResume: false);
    await until(
      () => health.last.healthy && samples > paused + 20,
      reason: 'the resume should bring the listener back',
    );
  });
}
