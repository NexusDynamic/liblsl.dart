import 'dart:async';

import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

/// Tests for [LSLInlet.sampleStream]: samples delivered as they arrive, with
/// the local clock read when the pull returned.
void main() {
  setUpAll(() {
    LSL.setConfigContent(
      LSLApiConfig(
        ipv6: IPv6Mode.disable,
        resolveScope: ResolveScope.link,
        listenAddress: '127.0.0.1',
        addressesOverride: ['224.0.0.183'],
        knownPeers: ['127.0.0.1'],
        sessionId: 'LSLSampleStreamTestSession',
        portRange: 64,
      ),
    );
  });

  var streamCounter = 0;

  Future<(LSLOutlet, LSLInlet<T>, List<LSLStreamInfo>)> createPair<T>(
    LSLChannelFormat format, {
    bool inletIsolates = false,
  }) async {
    final name = 'SampleStreamTest_${streamCounter++}_${format.name}';
    final info = await LSL.createStreamInfo(
      streamName: name,
      channelCount: 2,
      channelFormat: format,
      sampleRate: 200,
      sourceId: name,
    );
    final outlet = await LSL.createOutlet(streamInfo: info, useIsolates: false);
    final resolved = await LSL.resolveStreamsByProperty(
      property: LSLStreamProperty.name,
      value: name,
      waitTime: 5,
      minStreamCount: 1,
    );
    final inlet = await LSL.createInlet<T>(
      streamInfo: resolved.first,
      useIsolates: inletIsolates,
    );
    outlet.waitForConsumerSync(timeout: 5);
    return (outlet, inlet, [info, ...resolved]);
  }

  test('delivers every sample in order with its receive clock', () async {
    final (outlet, inlet, infos) = await createPair<double>(
      LSLChannelFormat.double64,
    );
    final received = <LSLTimedSample<double>>[];
    final subscription = inlet.sampleStream().listen(received.add);

    const count = 200;
    for (var i = 0; i < count; i++) {
      outlet.pushSampleSync([i.toDouble(), -i.toDouble()]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (received.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await subscription.cancel();

    expect(received, hasLength(count));
    expect(
      [for (final s in received) s.data[0]],
      [for (var i = 0; i < count; i++) i.toDouble()],
    );
    expect(received.last.data[1], -(count - 1).toDouble());

    // Same process, same clock: received − sent is the latency itself. With
    // nothing polling it is far below the 5 ms between samples, however
    // busy this isolate's event loop was.
    final latencies = [for (final s in received) s.receivedClock - s.timestamp]
      ..sort();
    expect(latencies.first, greaterThan(0));
    expect(latencies[count ~/ 2], lessThan(0.002));

    await inlet.destroy();
    await outlet.destroy();
    for (final info in infos) {
      info.destroy();
    }
  }, tags: 'lsl');

  test('cancelling stops the isolate and frees the inlet', () async {
    final (outlet, inlet, infos) = await createPair<int>(
      LSLChannelFormat.int32,
    );
    final first = Completer<LSLTimedSample<int>>();
    final subscription = inlet
        .sampleStream(wakeInterval: 0.05)
        .listen((s) => first.isCompleted ? null : first.complete(s));
    outlet.pushSampleSync([7, 8]);
    expect((await first.future.timeout(const Duration(seconds: 5))).data, [
      7,
      8,
    ]);

    final watch = Stopwatch()..start();
    await subscription.cancel();
    expect(watch.elapsedMilliseconds, lessThan(1000));

    // The inlet is this isolate's again.
    outlet.pushSampleSync([9, 10]);
    final sample = inlet.pullSampleSync(timeout: 2);
    expect(sample.data, [9, 10]);

    // And can be listened to again.
    final again = inlet.sampleStream().first;
    outlet.pushSampleSync([11, 12]);
    expect((await again.timeout(const Duration(seconds: 5))).data, [11, 12]);
    // `first` cancels as it completes; let the isolate leave before destroy.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    await inlet.destroy();
    await outlet.destroy();
    for (final info in infos) {
      info.destroy();
    }
  }, tags: 'lsl');

  test('needs a direct-mode inlet', () async {
    final (outlet, inlet, infos) = await createPair<double>(
      LSLChannelFormat.float32,
      inletIsolates: true,
    );
    expect(inlet.sampleStream, throwsA(isA<LSLException>()));
    await inlet.destroy();
    await outlet.destroy();
    for (final info in infos) {
      info.destroy();
    }
  }, tags: 'lsl');
}
