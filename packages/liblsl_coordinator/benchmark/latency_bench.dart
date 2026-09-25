// Loopback latency benchmark: one coordinator + one participant in a single
// process. The coordinator prints p50/p95/p99 plus loss for three measurements.
//
// Usage: dart run benchmark/latency_bench.dart [rateHz] [durationSeconds]
//
// Three numbers, because they answer different questions:
//
//   data (LSL clock)   `message.timing.transitSeconds` — the sender's LSL
//                      timestamp mapped into the local clock domain via
//                      lsl_time_correction, subtracted from the local clock at
//                      pull time. This is the real one-way transit and it stays
//                      meaningful across machines.
//   data (wall clock)  the old measurement: send time smuggled through channel
//                      0 and subtracted from DateTime.now(). Kept because it is
//                      the only number comparable with historic baselines, but
//                      it is the difference of two unsynchronised wall clocks
//                      and is only interpretable in one process on loopback.
//   coordination       the same LSL-clock measurement, taken on the low-rate
//                      coordination stream. A control message crosses the same
//                      network as a data sample; whether it can be characterised
//                      should not depend on how often it is sent.
//
// Deliberately has no exit(0): a clean process exit doubles as the teardown
// regression check (no lingering isolates, timers, or ports).

import 'dart:async';
import 'dart:math';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:logging/logging.dart';

Future<void> main(List<String> args) async {
  final rateHz = args.isNotEmpty ? double.tryParse(args[0]) ?? 60.0 : 60.0;
  final durationS = args.length > 1 ? int.tryParse(args[1]) ?? 10 : 10;

  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen(Log.defaultPrinter);

  print('Latency benchmark: $rateHz Hz for ${durationS}s (loopback)');

  final suffix = Random().nextInt(100000);
  final results = await Future.wait([
    _runNode('bench_$suffix', 'Coordinator', rateHz, durationS, delayMs: 0),
    _runNode('bench_$suffix', 'Participant', rateHz, durationS, delayMs: 500),
  ]);
  // One of the two futures carries the report (whichever became coordinator).
  for (final report in results) {
    if (report != null) print(report);
  }
}

Future<String?> _runNode(
  String sessionName,
  String nodeId,
  double rateHz,
  int durationS, {
  required int delayMs,
}) async {
  if (delayMs > 0) await Future.delayed(Duration(milliseconds: delayMs));

  final config = CoordinationConfig(
    name: 'LatencyBench',
    sessionConfig: CoordinationSessionConfig(
      name: sessionName,
      heartbeatInterval: Duration(seconds: 1),
      discoveryInterval: Duration(seconds: 2),
      nodeTimeout: Duration(seconds: 10),
      maxNodes: 2,
      consumeCoordinationStreamAsCoordinator: false,
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: 2,
    ),
    streamConfig: CoordinationStreamConfig(
      name: 'coordination',
      sampleRate: 50.0,
    ),
    transportConfig: LSLTransportConfig(
      lslApiConfig: LSLApiConfig(
        ipv6: IPv6Mode.disable,
        resolveScope: ResolveScope.link,
        listenAddress: '127.0.0.1',
        addressesOverride: ['224.0.0.184'],
        knownPeers: ['127.0.0.1'],
        logLevel: -2,
        portRange: 128,
      ),
    ),
  );

  final streamConfig = DataStreamConfig(
    name: 'BenchData',
    channels: 2, // [sendTimeMicros, sequence]
    sampleRate: rateHz,
    dataType: StreamDataType.double64,
    participationMode:
        StreamParticipationMode.sendParticipantsReceiveCoordinator,
  );

  final session = LSLCoordinationSession(
    config,
    thisNodeConfig: NodeConfigFactory().defaultConfig().copyWith(name: nodeId),
  );

  await session.initialize();
  await session.join();

  String? report;
  if (session.isCoordinator) {
    report = await _coordinatorRole(session, streamConfig, rateHz, durationS);
  } else {
    await _participantRole(session, rateHz, durationS);
  }

  await session.leave();
  await session.dispose();
  return report;
}

Future<String> _coordinatorRole(
  LSLCoordinationSession session,
  DataStreamConfig streamConfig,
  double rateHz,
  int durationS,
) async {
  await session.waitForMinNodes(2, timeout: Duration(seconds: 30));

  final wallMicros = <int>[];
  final lslMicros = <int>[];
  final coordMicros = <int>[];
  final seqs = <int>[];
  var coordPings = 0;
  var untimedData = 0;
  var untimedCoord = 0;

  final stream = await session.createDataStream(streamConfig);
  final sub = stream.inbox.listen((message) {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final data = message.data;
    wallMicros.add(nowMicros - (data[0] as double).toInt());
    seqs.add((data[1] as double).toInt());

    final transit = message.timing?.transitMicros;
    if (transit == null) {
      // Null means the clock offset was not yet estimated, not zero latency.
      untimedData++;
    } else {
      lslMicros.add(transit);
    }
  });

  // Coordination messages are the point of the exercise: same wire, ~1/100th
  // the rate, and until the timing survived the JSON decode there was no way
  // to measure them at all.
  final coordSub = session.events.userMessages.listen((event) {
    if (event.messageType != 'bench_ping') return;
    coordPings++;
    final transit = event.timing?.transitMicros;
    if (transit == null) {
      untimedCoord++;
    } else {
      coordMicros.add(transit);
    }
  });

  await session.startStream('BenchData');

  // Participant announces completion with its sent count. Uses the raw
  // event stream (not waitForUserMessage) so the same benchmark also runs
  // against older versions of the library for A/B comparisons.
  final done = await session.events.userMessages
      .firstWhere((e) => e.messageType == 'bench_done')
      .timeout(Duration(seconds: durationS + 30));
  final sent = done.payload['sent'] as int;

  // Allow in-flight samples to drain before stopping.
  await Future.delayed(Duration(milliseconds: 500));
  await session.stopStream('BenchData');
  await sub.cancel();
  await coordSub.cancel();

  return _report(
    rateHz: rateHz,
    durationS: durationS,
    sent: sent,
    wallMicros: wallMicros,
    lslMicros: lslMicros,
    coordMicros: coordMicros,
    coordPings: coordPings,
    untimedData: untimedData,
    untimedCoord: untimedCoord,
    seqs: seqs,
  );
}

Future<void> _participantRole(
  LSLCoordinationSession session,
  double rateHz,
  int durationS,
) async {
  final started = Completer<LSLDataStream>();
  session.events.streamStart.listen((event) async {
    if (!started.isCompleted) {
      started.complete(await session.getDataStream(event.streamName));
    }
  });

  final stream = await started.future.timeout(Duration(seconds: 60));

  final interval = Duration(microseconds: (1000000 / rateHz).round());
  var seq = 0;
  final endAt = DateTime.now().add(Duration(seconds: durationS));
  final finished = Completer<void>();

  Timer.periodic(interval, (timer) {
    if (DateTime.now().isAfter(endAt) || !stream.started) {
      timer.cancel();
      if (!finished.isCompleted) finished.complete();
      return;
    }
    stream.sendData([
      DateTime.now().microsecondsSinceEpoch.toDouble(),
      (seq++).toDouble(),
    ]);
  });

  // Low-rate coordination traffic alongside the data stream, so the report can
  // compare the two paths under the same conditions.
  var ping = 0;
  final coordTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
    if (DateTime.now().isAfter(endAt)) {
      timer.cancel();
      return;
    }
    unawaited(
      session.sendUserMessage('bench_ping', 'coordination latency probe', {
        'seq': ping++,
      }),
    );
  });

  await finished.future;
  coordTimer.cancel();
  await session.sendUserMessage('bench_done', 'benchmark complete', {
    'sent': seq,
  });
  // Give the coordinator time to process before teardown.
  await Future.delayed(Duration(seconds: 2));
}

String _report({
  required double rateHz,
  required int durationS,
  required int sent,
  required List<int> wallMicros,
  required List<int> lslMicros,
  required List<int> coordMicros,
  required int coordPings,
  required int untimedData,
  required int untimedCoord,
  required List<int> seqs,
}) {
  if (wallMicros.isEmpty) {
    return 'RESULT: no samples received (sent: $sent)';
  }

  String stats(List<int> samples, int untimed) {
    if (samples.isEmpty) {
      return '    (no timed samples; $untimed without a clock offset)';
    }
    final sorted = List<int>.from(samples)..sort();
    int pct(double p) => sorted[((sorted.length - 1) * p).round()];
    final mean = sorted.reduce((a, b) => a + b) / sorted.length;
    final suffix = untimed > 0 ? '  [$untimed untimed]' : '';
    return '    min: ${sorted.first}  mean: ${mean.toStringAsFixed(0)}  '
        'p50: ${pct(0.50)}  p95: ${pct(0.95)}  p99: ${pct(0.99)}  '
        'max: ${sorted.last}$suffix';
  }

  return '''
RESULT @ $rateHz Hz, ${durationS}s
  sent:     $sent
  received: ${wallMicros.length} (loss: ${sent - wallMicros.length})
  data latency (one-way, LSL clock + time correction, µs):
${stats(lslMicros, untimedData)}
  data latency (one-way, wall clock, µs) [loopback-only, historic baseline]:
${stats(wallMicros, 0)}
  coordination latency (one-way, LSL clock + time correction, µs):
    pings received: $coordPings
${stats(coordMicros, untimedCoord)}
''';
}
