// One-way latency over the WebSocket relay, on loopback.
//
//   dart run benchmark/ws_latency_bench.dart <rateHz> <seconds>
//
// Mirrors packages/liblsl_coordinator/benchmark/latency_bench.dart so the two
// transports can be compared directly: same two-node shape, same measurement,
// same reported statistics.
//
// Measured, not assumed: at 60 Hz on loopback the hub is roughly an order of
// magnitude FASTER than LSL (p50 ~0.7 ms vs ~6.1 ms), despite taking two hops
// instead of one. LSL's figure at this rate is bounded by its polling
// interval, not by the network, whereas the hub path is event-driven and
// delivers as soon as the frame lands.
//
// So the case for WebRTC DataChannels is not "the hub is too slow at low
// rates" — it is WAN round-trips and high sample rates, where the extra hop
// and the relay's fan-out start to dominate. Measure before assuming.
//
// Deliberately has no exit(0): a clean process exit doubles as the teardown
// regression check (no lingering timers, sockets or ports).
library;

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/websocket.dart';

Future<void> main(List<String> args) async {
  final rateHz = args.isNotEmpty ? double.parse(args[0]) : 60.0;
  final seconds = args.length > 1 ? int.parse(args[1]) : 5;

  Logger.root.level = Level.SEVERE;
  Logger.root.onRecord.listen(Log.defaultPrinter);

  stdout.writeln(
    'WebSocket latency benchmark: $rateHz Hz for ${seconds}s (loopback hub)',
  );

  final hub = await CoordinationHub.serve();
  final hubUri = Uri.parse('ws://127.0.0.1:${hub.port}');

  final latencies = <int>[];
  final syncedLatencies = <int>[];
  final uncertainties = <int>[];
  var untimed = 0;
  var received = 0;
  var sent = 0;

  final coordinator = _session('coordinator', 0.1, hubUri);
  final participant = _session('participant', 0.9, hubUri);

  try {
    await coordinator.initialize();
    await coordinator.join(const Duration(seconds: 3));
    await participant.initialize();
    await participant.join(const Duration(seconds: 3));
    await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 10));

    final producerReady = Completer<DataStream>();
    final producerSub = participant.events.streamStart.listen((event) async {
      if (producerReady.isCompleted) return;
      producerReady.complete(await participant.getDataStream(event.streamName));
    });

    final stream = await coordinator.createDataStream(
      DataStreamConfig(
        // [sendTimeMicros, sequence]
        name: 'BenchData',
        channels: 2,
        sampleRate: rateHz,
        dataType: StreamDataType.double64,
        participationMode:
            StreamParticipationMode.sendParticipantsReceiveCoordinator,
      ),
    );
    final inbox = stream.inbox.listen((message) {
      final now = DateTime.now().microsecondsSinceEpoch;
      final sentAt = (message.data[0]! as num).toInt();
      latencies.add(now - sentAt);
      received++;

      // The measurement the library now provides on its own: the sender's
      // clock, mapped into ours by the estimated offset. Unlike the wall-clock
      // figure above it does not need the send time smuggled through a data
      // channel, and it stays meaningful across machines.
      final timing = message.timing;
      final transit = timing?.transitMicros;
      if (transit == null) {
        // No accepted burst yet — reported, not silently averaged away.
        untimed++;
      } else {
        syncedLatencies.add(transit);
        final bound = timing!.uncertainty;
        if (bound != null) uncertainties.add((bound * 1e6 / 2).round());
      }
    });

    await coordinator.startStream('BenchData');
    final producer = await producerReady.future.timeout(
      const Duration(seconds: 10),
    );

    final period = Duration(microseconds: (1000000 / rateHz).round());
    final done = Completer<void>();
    var sequence = 0;
    Timer.periodic(period, (t) async {
      if (sequence >= rateHz * seconds) {
        t.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      final micros = DateTime.now().microsecondsSinceEpoch.toDouble();
      await producer.sendData([micros, sequence.toDouble()]);
      sequence++;
      sent++;
    });

    await done.future;
    // Let the tail drain before measuring loss.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    await coordinator.stopStream('BenchData');
    await inbox.cancel();
    await producerSub.cancel();
  } finally {
    await participant.leave();
    await participant.dispose();
    await coordinator.leave();
    await coordinator.dispose();
    await hub.close();
  }

  _report(
    rateHz,
    seconds,
    sent,
    received,
    latencies,
    syncedLatencies,
    uncertainties,
    untimed,
  );
}

PeerSession _session(String name, double randomRoll, Uri hubUri) =>
    PeerSession.create(
      CoordinationConfig(
        name: 'ws_bench',
        sessionConfig: CoordinationSessionConfig(
          name: 'WsBench',
          maxNodes: 2,
          minNodes: 1,
          heartbeatInterval: const Duration(milliseconds: 250),
          discoveryInterval: const Duration(milliseconds: 100),
          nodeTimeout: const Duration(seconds: 2),
          consumeCoordinationStreamAsCoordinator: false,
        ),
        topologyConfig: HierarchicalTopologyConfig(
          promotionStrategy: PromotionStrategyRandom(),
          maxNodes: 2,
        ),
        streamConfig: CoordinationStreamConfig(name: 'coordination'),
        transportConfig: WebSocketTransportConfig(hubUri: hubUri),
      ),
      thisNodeConfig: NodeConfig(
        name: name,
        id: name,
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
        metadata: {PeerMetadataKeys.randomRoll: randomRoll.toString()},
      ),
    );

void _report(
  double rateHz,
  int seconds,
  int sent,
  int received,
  List<int> latencies,
  List<int> syncedLatencies,
  List<int> uncertainties,
  int untimed,
) {
  stdout.writeln('RESULT @ $rateHz Hz, ${seconds}s');
  stdout.writeln('  sent:     $sent');
  stdout.writeln('  received: $received (loss: ${sent - received})');
  if (latencies.isEmpty) {
    stdout.writeln('  no samples received');
    return;
  }

  void stats(String label, List<int> samples, {String suffix = ''}) {
    if (samples.isEmpty) {
      stdout.writeln('  $label:');
      stdout.writeln('    (no samples)$suffix');
      return;
    }
    final sorted = List<int>.from(samples)..sort();
    int at(double q) =>
        sorted[(sorted.length * q).clamp(0, sorted.length - 1).toInt()];
    final mean = sorted.reduce((a, b) => a + b) ~/ sorted.length;
    stdout.writeln('  $label:');
    stdout.writeln(
      '    min: ${sorted.first}  mean: $mean  p50: ${at(0.50)}  '
      'p95: ${at(0.95)}  p99: ${at(0.99)}  max: ${sorted.last}$suffix',
    );
  }

  // The clock-synced figure is the one that generalises: it uses the estimated
  // offset between the two peers' monotonic clocks, so it stays meaningful when
  // the peers are on different machines. The wall-clock figure below is only
  // interpretable because both processes are on this host.
  stats(
    'latency (one-way, synced clocks, µs)',
    syncedLatencies,
    suffix: untimed > 0 ? '  [$untimed before first offset]' : '',
  );
  stats('  ± bound on the above (µs)', uncertainties);
  stats('latency (one-way, wall clock, µs) [loopback-only]', latencies);
}
