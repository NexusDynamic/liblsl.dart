import 'dart:async';
import 'dart:isolate';

import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

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

    for (final s in subscriptions) {
      await s.cancel();
    }
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
      for (final n in [16, 64, 200]) {
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
      await listening.first.timeout(const Duration(seconds: 10));
      isolate.kill(priority: Isolate.immediate);

      for (var i = 0; i < 200; i++) {
        outlet.pushSampleSync([i.toDouble(), 0.0]);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      // Still here, and still able to use liblsl.
      expect(LSL.localClock(), greaterThan(0));
      await outlet.destroy();
      info.destroy();
    },
    tags: 'lsl',
  );
}

/// Listens to the stream called `name`, says so on the port, and waits to be
/// killed.
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
  inlet.sampleStream().listen((_) {});
  await Future<void>.delayed(const Duration(milliseconds: 500));
  port.send(true);
  await Completer<void>().future;
}
