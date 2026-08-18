// One-way latency, WebRTC against the WebSocket relay, in one process.
//
//   dart run benchmark/rtc_latency_bench.dart <rateHz> <seconds>
//
// Same two-node shape, same measurement and same statistics as
// `peer_coordinator/benchmark/ws_latency_bench.dart`, so the numbers line up
// with the ones already recorded there.
//
// **Read the two arms for what they are.** They do not share a medium, so the
// difference between them is not the thing this transport is for:
//
//   * `websocket` goes through a real loopback socket to a real hub and back
//     out — two hops, kernel networking on both.
//   * `webrtc (fake adapter)` goes through `FakeRtcPeerAdapter`, which is a
//     microtask hop in this process. There is no ICE, no SCTP and no network.
//
// So the WebRTC arm is a *floor*: it measures what the library itself costs —
// framing, routing fan-out, decode, clock stamping — with the network removed.
// That makes it a useful regression check on the transport's own overhead, and
// a useless estimate of what a real peer connection will do. The number that
// answers "is direct faster than the relay" has to come from two devices on one
// LAN with `webrtc_coordinator_flutter` supplying the adapter; the example app
// on the `Direct` transport is the way to get it.
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
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

Future<void> main(List<String> args) async {
  final rateHz = args.isNotEmpty ? double.parse(args[0]) : 60.0;
  final seconds = args.length > 1 ? int.parse(args[1]) : 5;

  Logger.root.level = Level.SEVERE;
  Logger.root.onRecord.listen(Log.defaultPrinter);

  stdout.writeln('Latency benchmark: $rateHz Hz for ${seconds}s\n');

  final hub = await CoordinationHub.serve();
  final hubUri = Uri.parse('ws://127.0.0.1:${hub.port}');

  try {
    final relay = await _run(
      label: 'websocket (relay, loopback socket)',
      hubUri: hubUri,
      rateHz: rateHz,
      seconds: seconds,
      run: 'ws',
      transportConfig: (_) => WebSocketTransportConfig(hubUri: hubUri),
    );
    relay.report(rateHz, seconds);

    // One bus per run, so the two nodes' fake adapters find each other and
    // nothing survives into a later run.
    final bus = FakeRtcBus();
    final direct = await _run(
      label: 'webrtc (fake adapter, in-process — library overhead only)',
      hubUri: hubUri,
      rateHz: rateHz,
      seconds: seconds,
      run: 'rtc',
      transportConfig: (_) => RtcTransportConfig(
        hubUri: hubUri,
        adapterFactory: (selfNodeUId) =>
            FakeRtcPeerAdapter(selfKey: selfNodeUId, bus: bus),
      ),
    );
    direct.report(rateHz, seconds);
  } finally {
    await hub.close();
  }
}

/// One arm: two nodes, one data stream, [rateHz] samples a second.
Future<_Measurements> _run({
  required String label,
  required Uri hubUri,
  required double rateHz,
  required int seconds,
  required String run,
  required ITransportConfig Function(int nodeIndex) transportConfig,
}) async {
  stdout.writeln('--- $label ---');
  final m = _Measurements(label);

  final coordinator = _session('coordinator', 0.1, run, transportConfig(0));
  final participant = _session('participant', 0.9, run, transportConfig(1));

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

    final streamName = 'BenchData-$run';
    final stream = await coordinator.createDataStream(
      DataStreamConfig(
        // [sendTimeMicros, sequence]
        name: streamName,
        channels: 2,
        sampleRate: rateHz,
        dataType: StreamDataType.double64,
        participationMode:
            StreamParticipationMode.sendParticipantsReceiveCoordinator,
      ),
    );
    final inbox = stream.inbox.listen(m.record);

    await coordinator.startStream(streamName);
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
      m.sent++;
    });

    await done.future;
    // Let the tail drain before measuring loss.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    await coordinator.stopStream(streamName);
    await inbox.cancel();
    await producerSub.cancel();
  } finally {
    await participant.leave();
    await participant.dispose();
    await coordinator.leave();
    await coordinator.dispose();
  }
  return m;
}

PeerSession _session(
  String name,
  double randomRoll,
  String run,
  ITransportConfig transportConfig,
) => PeerSession.create(
  CoordinationConfig(
    name: 'rtc_bench',
    sessionConfig: CoordinationSessionConfig(
      // Distinct per arm: the hub is shared across both runs, and a leftover
      // endpoint from the first arm resolved during the second would be
      // discovered as a peer.
      name: 'Bench-$run',
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
    streamConfig: CoordinationStreamConfig(name: 'coordination-$run'),
    transportConfig: transportConfig,
  ),
  thisNodeConfig: NodeConfig(
    name: name,
    id: '$name-$run',
    capabilities: {NodeCapability.coordinator, NodeCapability.participant},
    metadata: {PeerMetadataKeys.randomRoll: randomRoll.toString()},
  ),
);

/// What one arm observed.
class _Measurements {
  _Measurements(this.label);

  final String label;
  final List<int> latencies = [];
  final List<int> syncedLatencies = [];
  final List<int> uncertainties = [];
  int untimed = 0;
  int received = 0;
  int sent = 0;

  void record(IMessage message) {
    final now = DateTime.now().microsecondsSinceEpoch;
    latencies.add(now - (message.data[0]! as num).toInt());
    received++;

    // The measurement the library provides on its own: the sender's clock,
    // mapped into ours by the estimated offset. Unlike the wall-clock figure
    // above it does not need the send time smuggled through a data channel,
    // and it stays meaningful across machines.
    final timing = message.timing;
    final transit = timing?.transitMicros;
    if (transit == null) {
      // No accepted burst yet — reported, not silently averaged away.
      untimed++;
      return;
    }
    syncedLatencies.add(transit);
    final bound = timing!.uncertainty;
    if (bound != null) uncertainties.add((bound * 1e6 / 2).round());
  }

  void report(double rateHz, int seconds) {
    stdout.writeln('RESULT $label @ $rateHz Hz, ${seconds}s');
    stdout.writeln('  sent:     $sent');
    stdout.writeln('  received: $received (loss: ${sent - received})');
    if (latencies.isEmpty) {
      stdout.writeln('  no samples received\n');
      return;
    }
    // The clock-synced figure is the one that generalises: it uses the
    // estimated offset between the two peers' monotonic clocks, so it stays
    // meaningful when the peers are on different machines. The wall-clock
    // figure is only interpretable because both processes are on this host.
    _stats(
      'latency (one-way, synced clocks, µs)',
      syncedLatencies,
      suffix: untimed > 0 ? '  [$untimed before first offset]' : '',
    );
    _stats('  ± bound on the above (µs)', uncertainties);
    _stats('latency (one-way, wall clock, µs)', latencies);
    stdout.writeln('');
  }

  static void _stats(String label, List<int> samples, {String suffix = ''}) {
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
}
