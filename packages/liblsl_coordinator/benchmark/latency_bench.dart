// Loopback latency benchmark: one coordinator + one participant in a single
// process. The participant embeds its send time in channel 0 of each sample;
// the coordinator records receive deltas and prints p50/p95/p99 plus loss.
//
// Usage: dart run benchmark/latency_bench.dart [rateHz] [durationSeconds]
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
    participationMode: StreamParticipationMode.sendParticipantsReceiveCoordinator,
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

  final deltasMicros = <int>[];
  final seqs = <int>[];

  final stream = await session.createDataStream(streamConfig);
  final sub = stream.inbox.listen((message) {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final data = message.data;
    deltasMicros.add(nowMicros - (data[0] as double).toInt());
    seqs.add((data[1] as double).toInt());
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

  return _report(rateHz, durationS, sent, deltasMicros, seqs);
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

  await finished.future;
  await session.sendUserMessage('bench_done', 'benchmark complete', {
    'sent': seq,
  });
  // Give the coordinator time to process before teardown.
  await Future.delayed(Duration(seconds: 2));
}

String _report(
  double rateHz,
  int durationS,
  int sent,
  List<int> deltasMicros,
  List<int> seqs,
) {
  if (deltasMicros.isEmpty) {
    return 'RESULT: no samples received (sent: $sent)';
  }
  final sorted = List<int>.from(deltasMicros)..sort();
  int pct(double p) => sorted[((sorted.length - 1) * p).round()];
  final received = sorted.length;
  final mean = sorted.reduce((a, b) => a + b) / received;

  return '''
RESULT @ $rateHz Hz, ${durationS}s
  sent:     $sent
  received: $received (loss: ${sent - received})
  latency (one-way, wall clock, µs):
    min: ${sorted.first}  mean: ${mean.toStringAsFixed(0)}  p50: ${pct(0.50)}  p95: ${pct(0.95)}  p99: ${pct(0.99)}  max: ${sorted.last}
''';
}
