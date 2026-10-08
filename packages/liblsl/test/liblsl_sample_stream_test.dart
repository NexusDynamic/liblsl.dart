import 'dart:async';
import 'dart:io' show sleep;
import 'dart:math';
import 'dart:typed_data';

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

  test('a listener that dies reports why, then ends the stream', () async {
    final (outlet, inlet, infos) = await createPair<int>(
      LSLChannelFormat.int32,
    );
    final samples = <LSLTimedSample<int>>[];
    final errors = <Object>[];
    final done = Completer<void>();
    inlet
        .sampleStream(debugFailAfter: 2)
        .listen(
          samples.add,
          onError: (Object e) => errors.add(e),
          onDone: done.complete,
        );
    for (var i = 0; i < 4; i++) {
      outlet.pushSampleSync([i, i]);
    }
    await done.future.timeout(const Duration(seconds: 5));

    expect([for (final s in samples) s.data[0]], [0, 1]);
    expect(errors, hasLength(1));
    final error = errors.single as LSLSampleListenerException;
    expect(error.errorCode, isNull);
    expect(error.isLost, isFalse);
    expect(error.message, contains('debugFailAfter'));
    expect(error.stackTrace, isNotEmpty);

    // The inlet survives its listener: the samples it did not take are
    // still queued for the next one.
    final next = await inlet.sampleStream().first.timeout(
      const Duration(seconds: 5),
    );
    expect(next.data, [2, 2]);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    await inlet.destroy();
    await outlet.destroy();
    for (final info in infos) {
      info.destroy();
    }
  }, tags: 'lsl');

  test('a cancelled listener ends without an error', () async {
    final (outlet, inlet, infos) = await createPair<int>(
      LSLChannelFormat.int32,
    );
    final errors = <Object>[];
    final subscription = inlet
        .sampleStream(wakeInterval: 0.05)
        .listen((_) {}, onError: (Object e) => errors.add(e));
    outlet.pushSampleSync([1, 2]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(errors, isEmpty);

    await inlet.destroy();
    await outlet.destroy();
    for (final info in infos) {
      info.destroy();
    }
  }, tags: 'lsl');

  test('works on an isolate-mode inlet, which keeps answering', () async {
    final (outlet, inlet, infos) = await createPair<double>(
      LSLChannelFormat.float32,
      inletIsolates: true,
    );
    final first = inlet.sampleStream().first;
    outlet.pushSampleSync([1.5, 2.5]);
    expect((await first.timeout(const Duration(seconds: 5))).data, [1.5, 2.5]);
    // The inlet's own isolate is free: it is not the one pulling.
    final correction = await inlet.getTimeCorrectionEx(timeout: 5);
    expect(correction.offset.abs(), lessThan(0.1));
    await Future<void>.delayed(const Duration(milliseconds: 250));

    await inlet.destroy();
    await outlet.destroy();
    for (final info in infos) {
      info.destroy();
    }
  }, tags: 'lsl');

  group('a listener that falls behind', () {
    Future<void> cleanUp(
      LSLOutlet outlet,
      LSLInlet<dynamic> inlet,
      List<LSLStreamInfo> infos,
    ) async {
      await inlet.destroy();
      await outlet.destroy();
      for (final info in infos) {
        info.destroy();
      }
    }

    /// Pushes [count] samples and keeps this isolate busy for long enough
    /// that the listening isolate has pulled whatever it is going to.
    void pushWhileBusy(LSLOutlet outlet, int count) {
      for (var i = 0; i < count; i++) {
        outlet.pushSampleSync([i, i]);
      }
      sleep(const Duration(milliseconds: 400));
    }

    Future<void> until(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('is told, and loses nothing, when there is no limit', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      final received = <int>[];
      final reports = <LSLBacklog>[];
      final subscription = inlet
          .sampleStream(onBacklog: reports.add)
          .listen((s) => received.add(s.data[0]));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      const count = 3000;
      pushWhileBusy(outlet, count);
      await until(() => received.length == count);
      await subscription.cancel();

      expect(received, [for (var i = 0; i < count; i++) i]);
      // All of them were queued when this isolate got to the first.
      expect(reports.first.cleared, isFalse);
      expect(reports.first.queued, greaterThan(2500));
      expect(reports.last.cleared, isTrue);
      expect(reports.last.peak, reports.first.queued);
      expect(reports.where((r) => r.cleared), hasLength(1));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('is not told about a queue below the threshold', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      var received = 0;
      final reports = <LSLBacklog>[];
      final subscription = inlet
          .sampleStream(onBacklog: reports.add)
          .listen((_) => received++);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      pushWhileBusy(outlet, 500);
      await until(() => received == 500);
      await subscription.cancel();

      expect(received, 500);
      expect(reports, isEmpty);

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('with maxBacklog the queue stays within it and the rest waits in '
        'the inlet', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      final received = <int>[];
      final reports = <LSLBacklog>[];
      final subscription = inlet
          .sampleStream(
            maxBacklog: 100,
            backlogWarnAt: 1,
            onBacklog: reports.add,
          )
          .listen((s) => received.add(s.data[0]));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      const count = 3000;
      pushWhileBusy(outlet, count);
      await until(() => received.length == count);
      await subscription.cancel();

      expect(received, [for (var i = 0; i < count; i++) i]);
      expect(reports, isNotEmpty);
      expect(reports.map((r) => r.peak).reduce(max), lessThanOrEqualTo(100));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('with maxBacklog a paused subscription stops the pulling', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      final received = <LSLTimedSample<int>>[];
      final subscription = inlet
          .sampleStream(wakeInterval: 0.05, maxBacklog: 1000)
          .listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      subscription.pause();
      // The pull it was in when it was paused has timed out by then.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (var i = 0; i < 50; i++) {
        outlet.pushSampleSync([i, i]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(received, isEmpty);

      final resumedAt = LSL.localClock();
      subscription.resume();
      await until(() => received.length == 50);
      expect(
        [for (final s in received) s.data[0]],
        [for (var i = 0; i < 50; i++) i],
      );
      // They waited in the inlet, not in the stream: none was pulled until
      // the subscription was resumed.
      expect(
        received.map((s) => s.receivedClock).reduce(min),
        greaterThanOrEqualTo(resumedAt),
      );

      // Cancelling does not wait for a paused listener to be resumed.
      subscription.pause();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final watch = Stopwatch()..start();
      await subscription.cancel();
      expect(watch.elapsedMilliseconds, lessThan(1000));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('chunks count their samples', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      var received = 0;
      final reports = <LSLBacklog>[];
      final subscription = inlet
          .chunkStream(
            maxSamples: 64,
            backlogWarnAt: 500,
            onBacklog: reports.add,
          )
          .listen((c) => received += c.sampleCount);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      pushWhileBusy(outlet, 3000);
      await until(() => received == 3000);
      await subscription.cancel();

      expect(received, 3000);
      expect(reports.first.queued, greaterThan(2000));
      expect(reports.last.cleared, isTrue);

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');
  });

  group('an inlet that is being listened to', () {
    test('cannot be pulled from or flushed', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      final subscription = inlet.sampleStream().listen((_) {});
      expect(() => inlet.pullSampleSync(), throwsA(isA<LSLException>()));
      expect(() => inlet.pullChunkSync(), throwsA(isA<LSLException>()));
      expect(() => inlet.pullChunkTypedSync(), throwsA(isA<LSLException>()));
      expect(() => inlet.flushSync(), throwsA(isA<LSLException>()));
      expect(inlet.flush(), throwsA(isA<LSLException>()));
      await subscription.cancel();

      outlet.pushSampleSync([1, 2]);
      expect(inlet.pullSampleSync(timeout: 2).data, [1, 2]);
      expect(inlet.flushSync(), 0);

      await inlet.destroy();
      await outlet.destroy();
      for (final info in infos) {
        info.destroy();
      }
    }, tags: 'lsl');

    for (final isolates in [false, true]) {
      test('stops its listener when it is destroyed '
          '(${isolates ? 'isolate' : 'direct'} mode)', () async {
        final (outlet, inlet, infos) = await createPair<int>(
          LSLChannelFormat.int32,
          inletIsolates: isolates,
        );
        final samples = <int>[];
        final errors = <Object>[];
        final done = Completer<void>();
        inlet.sampleStream().listen(
          (s) => samples.add(s.data[0]),
          onError: (Object e) => errors.add(e),
          onDone: done.complete,
        );
        outlet.pushSampleSync([5, 5]);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (samples.isEmpty && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(samples, [5]);

        // Not cancelled first.
        await inlet.destroy();
        await done.future.timeout(const Duration(seconds: 5));
        expect(errors.single, isA<LSLSampleListenerException>());
        expect('${errors.single}', contains('destroyed'));

        await outlet.destroy();
        for (final info in infos) {
          info.destroy();
        }
      }, tags: 'lsl');
    }
  });

  group('chunkStream', () {
    Future<void> cleanUp(
      LSLOutlet outlet,
      LSLInlet<dynamic> inlet,
      List<LSLStreamInfo> infos,
    ) async {
      await inlet.destroy();
      await outlet.destroy();
      for (final info in infos) {
        info.destroy();
      }
    }

    test('delivers every sample in order, as typed data', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        LSLChannelFormat.float32,
      );
      final chunks = <LSLTimedChunk>[];
      final subscription = inlet.chunkStream().listen(chunks.add);

      const count = 300;
      for (var i = 0; i < count; i++) {
        outlet.pushSampleSync([i.toDouble(), -i.toDouble()]);
        if (i % 10 == 9) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      int received() => chunks.fold(0, (n, c) => n + c.sampleCount);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (received() < count && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await subscription.cancel();

      expect(received(), count);
      final values = [for (final c in chunks) ...(c.data! as Float32List)];
      expect(values, [
        for (var i = 0; i < count; i++) ...[i.toDouble(), -i.toDouble()],
      ]);
      for (final c in chunks) {
        expect(c.channelCount, 2);
        expect(c.strings, isNull);
        expect(c.data!.lengthInBytes, c.sampleCount * 2 * 4);
        // Same process, same clock: the first sample was sent before it
        // was received, and not long before.
        expect(c.receivedClock - c.timestamps.first, inInclusiveRange(0, 0.5));
      }
      // Samples pushed together come together.
      expect(chunks.length, lessThan(count));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('a burst that was waiting arrives as one chunk', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      for (var i = 0; i < 50; i++) {
        outlet.pushSampleSync([i, i]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final chunk = await inlet.chunkStream().first.timeout(
        const Duration(seconds: 5),
      );
      expect(chunk.sampleCount, 50);
      expect((chunk.data! as Int32List).last, 49);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('maxSamples bounds a chunk and loses nothing', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int16,
      );
      for (var i = 0; i < 25; i++) {
        outlet.pushSampleSync([i, i]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final chunks = <LSLTimedChunk>[];
      final subscription = inlet.chunkStream(maxSamples: 10).listen(chunks.add);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await subscription.cancel();

      expect([for (final c in chunks) c.sampleCount], [10, 10, 5]);
      expect((chunks.last.data! as Int16List).last, 24);

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('coalesce gathers samples that arrive one by one', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        LSLChannelFormat.double64,
      );
      final chunks = <LSLTimedChunk>[];
      final subscription = inlet.chunkStream(coalesce: 0.1).listen(chunks.add);
      const count = 100;
      for (var i = 0; i < count; i++) {
        outlet.pushSampleSync([i.toDouble(), 0.0]);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await subscription.cancel();

      expect(chunks.fold<int>(0, (n, c) => n + c.sampleCount), count);
      // About one every 100 ms over half a second, not one per sample.
      expect(chunks.length, lessThan(15));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('readyCount is what was there when the clock was read', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        LSLChannelFormat.int32,
      );
      for (var i = 0; i < 50; i++) {
        outlet.pushSampleSync([i, i]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final chunks = <LSLTimedChunk>[];
      final subscription = inlet.chunkStream(coalesce: 0.2).listen(chunks.add);
      // These arrive while it is collecting.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (var i = 50; i < 60; i++) {
        outlet.pushSampleSync([i, i]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await subscription.cancel();

      expect(chunks.first.sampleCount, 60);
      expect(chunks.first.readyCount, 50);
      // Without coalesce, everything in a chunk was ready.
      for (var i = 0; i < 5; i++) {
        outlet.pushSampleSync([i, i]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final chunk = await inlet.chunkStream().first.timeout(
        const Duration(seconds: 5),
      );
      expect(chunk.readyCount, chunk.sampleCount);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test("a sender's chunking is in the first sample's latency and not in "
        "the last ready one's", () async {
      final (outlet, inlet, infos) = await createPair<double>(
        LSLChannelFormat.double64,
      );
      final chunks = <LSLTimedChunk>[];
      final subscription = inlet.chunkStream().listen(chunks.add);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // 20 samples at 200 Hz: liblsl spreads their time stamps over 95 ms
      // and sends them together.
      for (var k = 0; k < 10; k++) {
        outlet.pushChunkSync([
          for (var i = 0; i < 20; i++) [i.toDouble(), 0.0],
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await subscription.cancel();

      expect(chunks.fold<int>(0, (n, c) => n + c.sampleCount), 200);
      final whole = chunks.where((c) => c.sampleCount == 20).toList();
      expect(whole, isNotEmpty);
      for (final c in whole) {
        expect(c.receivedClock - c.timestamps.first, greaterThan(0.09));
        expect(
          c.receivedClock - c.timestamps[c.readyCount - 1],
          lessThan(0.02),
        );
      }

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('string streams come as strings', () async {
      final (outlet, inlet, infos) = await createPair<String>(
        LSLChannelFormat.string,
      );
      final chunks = <LSLTimedChunk>[];
      final subscription = inlet.chunkStream().listen(chunks.add);
      outlet.pushSampleSync(['go', 'left']);
      outlet.pushSampleSync(['stop', 'right']);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (chunks.fold<int>(0, (n, c) => n + c.sampleCount) < 2 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await subscription.cancel();

      expect(chunks.every((c) => c.data == null), isTrue);
      expect(
        [for (final c in chunks) ...c.strings!],
        ['go', 'left', 'stop', 'right'],
      );

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test('works on an isolate-mode inlet', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        LSLChannelFormat.float32,
        inletIsolates: true,
      );
      final first = inlet.chunkStream().first;
      outlet.pushSampleSync([3.0, 4.0]);
      final chunk = await first.timeout(const Duration(seconds: 5));
      expect(chunk.data, [3, 4]);
      expect(
        (await inlet.getTimeCorrectionEx(timeout: 5)).offset.abs(),
        lessThan(0.1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      await cleanUp(outlet, inlet, infos);
    }, tags: 'lsl');

    test(
      'a listener that dies reports why; a cancelled one does not',
      () async {
        final (outlet, inlet, infos) = await createPair<int>(
          LSLChannelFormat.int32,
        );
        final errors = <Object>[];
        final done = Completer<void>();
        var samples = 0;
        inlet
            .chunkStream(debugFailAfter: 1)
            .listen(
              (c) => samples += c.sampleCount,
              onError: (Object e) => errors.add(e),
              onDone: done.complete,
            );
        outlet.pushSampleSync([1, 1]);
        await done.future.timeout(const Duration(seconds: 5));
        expect(samples, 1);
        expect(errors.single, isA<LSLSampleListenerException>());
        expect('${errors.single}', contains('debugFailAfter'));

        errors.clear();
        final subscription = inlet
            .chunkStream(wakeInterval: 0.05)
            .listen((_) {}, onError: (Object e) => errors.add(e));
        outlet.pushSampleSync([2, 2]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await subscription.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(errors, isEmpty);

        await cleanUp(outlet, inlet, infos);
      },
      tags: 'lsl',
    );
  });
}
