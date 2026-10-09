import 'dart:async';
import 'dart:isolate';

import 'package:liblsl/lsl.dart';
import 'package:liblsl/native_liblsl.dart' show lsl_inlet;
import 'package:test/test.dart';

/// Seconds the killed isolate's listener thread waits inside a pull before it
/// looks at its stop flag: how long it can outlive the isolate.
const _killedWakeInterval = 0.1;

/// Idle [LSLInlet.sampleStream] listeners must not starve the isolate that
/// started them.
///
/// In 1.1.0 each listener was an isolate that spent its life inside a
/// blocking pull. The Dart VM bounds how many isolates of a group are entered
/// at once and one blocked in a native call still counts, so from sixteen
/// idle listeners on (on a 12-core Mac) the main isolate waited for one of
/// them to time out before it could handle its next event: a 120 Hz timer ran
/// at 57 Hz beside 16 listeners and at 8 Hz beside 32. Seen 2026-10-09 in an
/// application whose physics loop was that timer.
void main() {
  setUpAll(() {
    LSL.setConfigContent(
      LSLApiConfig(
        ipv6: IPv6Mode.disable,
        resolveScope: ResolveScope.link,
        listenAddress: '127.0.0.1',
        addressesOverride: ['224.0.0.183'],
        knownPeers: ['127.0.0.1'],
        sessionId: 'LSLIdleListenerTestSession',
        portRange: 64,
      ),
    );
  });

  /// Rate a 120 Hz timer achieves over [window] with [listeners] idle
  /// listeners running, in hertz.
  Future<double> timerRateWith(
    int listeners, {
    Duration window = const Duration(seconds: 3),
  }) async {
    final name = 'IdleListenerTest_$listeners';
    final info = await LSL.createStreamInfo(
      streamName: name,
      channelCount: 2,
      channelFormat: LSLChannelFormat.double64,
      sampleRate: 100,
      sourceId: name,
    );
    final outlet = await LSL.createOutlet(streamInfo: info, useIsolates: false);
    final resolved = await LSL.resolveStreamsByProperty(
      property: LSLStreamProperty.name,
      value: name,
      waitTime: 5,
      minStreamCount: 1,
    );
    final inlets = <LSLInlet<double>>[];
    final subscriptions = <StreamSubscription<void>>[];
    for (var i = 0; i < listeners; i++) {
      final inlet = await LSL.createInlet<double>(
        streamInfo: resolved.first,
        useIsolates: false,
      );
      inlets.add(inlet);
      subscriptions.add(inlet.sampleStream().listen((_) {}));
    }
    // Let every listener isolate start and settle into its pull.
    await Future<void>.delayed(const Duration(seconds: 1));

    var ticks = 0;
    final watch = Stopwatch()..start();
    final timer = Timer.periodic(
      const Duration(microseconds: 8333),
      (_) => ticks++,
    );
    await Future<void>.delayed(window);
    timer.cancel();
    final rate = ticks / (watch.elapsedMicroseconds / 1e6);

    // Together: each cancel waits for its thread to come out of its pull.
    await Future.wait([for (final s in subscriptions) s.cancel()]);
    for (final inlet in inlets) {
      await inlet.destroy();
    }
    await outlet.destroy();
    info.destroy();
    for (final r in resolved) {
      r.destroy();
    }
    return rate;
  }

  test(
    'a 120 Hz timer keeps its rate beside idle listeners',
    () async {
      final baseline = await timerRateWith(0);
      // Sixteen was where 1.1.0 began to starve. No more than this: an inlet
      // takes about half a second to destroy, which is most of the test.
      for (final n in [16, 64]) {
        final rate = await timerRateWith(n);
        expect(rate, greaterThan(baseline * 0.9), reason: '$n idle listeners');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    tags: 'lsl',
  );

  test(
    'an isolate that is killed while listening takes nothing with it',
    () async {
      // Its listener thread goes on handing over blocks that nobody is there
      // to take. That must be harmless to the rest of the process.
      //
      // The finalizer stops that thread and nothing more: the inlet is a
      // native object and outlives the isolate that opened it. It is
      // destroyed here, by address. Left alone it would notice its outlet
      // going and send resolve queries to find it again until the process
      // ended, into whichever test file runs next.
      const name = 'IdleListenerTest_killed';
      final info = await LSL.createStreamInfo(
        streamName: name,
        channelCount: 2,
        channelFormat: LSLChannelFormat.double64,
        sampleRate: 100,
        sourceId: name,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        useIsolates: false,
      );
      final listening = ReceivePort();
      final isolate = await Isolate.spawn(_listenUntilKilled, (
        name,
        listening.sendPort,
      ));
      final (inletAddress, resolvedAddress) =
          await listening.first.timeout(const Duration(seconds: 10))
              as (int, int);
      isolate.kill(priority: Isolate.immediate);

      for (var i = 0; i < 200; i++) {
        outlet.pushSampleSync([i.toDouble(), 0.0]);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      // Still here, and still able to use liblsl.
      expect(LSL.localClock(), greaterThan(0));

      // The finalizer does not wait for the thread, which may be inside a
      // pull for one more wake interval. Destroying the inlet under it would
      // be a use after free, so give it several, and a slow runner some more.
      await Future<void>.delayed(
        Duration(milliseconds: (_killedWakeInterval * 3000).round() + 500),
      );
      final resolved = LSLStreamInfo.fromStreamInfoAddr(resolvedAddress);
      final orphan = LSLInlet<double>(resolved, useIsolates: false);
      await orphan.createFromPointer(
        lsl_inlet.fromAddress(inletAddress),
        takeOwnership: true,
      );
      await orphan.destroy();
      resolved.destroy();

      await outlet.destroy();
      info.destroy();
    },
    tags: 'lsl',
  );
}

/// Listens to the stream called `name`, sends the addresses of its inlet and
/// of the stream info it resolved on the port, and waits to be killed.
Future<void> _listenUntilKilled((String, SendPort) args) async {
  final (name, port) = args;
  final resolved = await LSL.resolveStreamsByProperty(
    property: LSLStreamProperty.name,
    value: name,
    waitTime: 5,
    minStreamCount: 1,
  );
  final inlet = await LSL.createInlet<double>(
    streamInfo: resolved.first,
    useIsolates: false,
  );
  inlet.sampleStream(wakeInterval: _killedWakeInterval).listen((_) {});
  await Future<void>.delayed(const Duration(milliseconds: 500));
  port.send((inlet.inlet.address, resolved.first.streamInfo.address));
  await Completer<void>().future;
}
