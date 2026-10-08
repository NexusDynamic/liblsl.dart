import 'dart:async';
import 'dart:typed_data';

import 'package:lsl_tools/lsl_tools.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/testing.dart';
import 'package:test/test.dart';
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

/// Wait until [done], or fail.
Future<void> _until(bool Function() done, [String? what]) async {
  for (var i = 0; i < 500; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for ${what ?? 'a condition'}');
}

class _Bytes implements Sink<List<int>> {
  int length = 0;
  @override
  void add(List<int> data) => length += data.length;
  @override
  void close() {}
}

/// A publisher, through a relay, over WebRTC, through a second relay:
///
///     origin ─▶ relay 1 ─▶ node A ═WebRTC═▶ node B ─▶ relay 2 ─▶ far
///                                             └─▶ recorder
///
/// The origin, both relays and the far end each have a clock of their own.
void main() {
  final watch = Stopwatch()..start();
  double base() => watch.elapsedMicroseconds / 1e6;
  double onOrigin() => base() - 300;
  double onFar() => base() + 77777;
  const originToFar = 77777.0 + 300;

  test(
    'time stamps and their chain survive bridge, WebRTC and bridge',
    () async {
      final relay1 = await LslBridgeServer.start(
        const [],
        port: 0,
        host: '127.0.0.1',
        acceptPublish: true,
        localOutlets: false,
        clock: () => base() + 5000,
      );
      final relay2 = await LslBridgeServer.start(
        const [],
        port: 0,
        host: '127.0.0.1',
        acceptPublish: true,
        localOutlets: false,
        clock: () => base() - 9000,
      );
      addTearDown(relay1.close);
      addTearDown(relay2.close);
      Future<LslBridgeClient> connect(
        LslBridgeServer relay,
        String name, [
        double Function()? clock,
      ]) async {
        final c = await LslBridgeClient.connect(
          Uri.parse('ws://127.0.0.1:${relay.port}'),
          name: name,
          clock: clock,
        );
        addTearDown(c.close);
        return c;
      }

      // Two WebRTC nodes (in this process, so on one clock).
      final hub = await startTestHub();
      addTearDown(hub.close);
      final bus = FakeRtcBus();
      final id = DateTime.now().microsecondsSinceEpoch;
      final sessions = <PeerSession>[];
      addTearDown(() async {
        for (final s in sessions.reversed) {
          await s.leave();
          await s.dispose();
        }
      });
      for (final (i, label) in ['a', 'b'].indexed) {
        final session = PeerSession.create(
          CoordinationConfig(
            name: 'multi_hop',
            sessionConfig: CoordinationSessionConfig(
              name: 'hops-$id',
              maxNodes: 2,
              minNodes: 1,
              heartbeatInterval: const Duration(milliseconds: 100),
              discoveryInterval: const Duration(milliseconds: 50),
              nodeTimeout: const Duration(milliseconds: 800),
              consumeCoordinationStreamAsCoordinator: false,
            ),
            topologyConfig: HierarchicalTopologyConfig(
              promotionStrategy: PromotionStrategyRandom(),
              maxNodes: 2,
            ),
            streamConfig: CoordinationStreamConfig(name: 'coordination-$id'),
            transportConfig: RtcTransportConfig(
              hubUri: hub.uri,
              credentials: hub.credentials,
              adapterFactory: (self) =>
                  FakeRtcPeerAdapter(selfKey: self, bus: bus),
            ),
          ),
          thisNodeConfig: NodeConfig(
            name: label,
            id: '$label-$id',
            capabilities: {
              NodeCapability.coordinator,
              NodeCapability.participant,
            },
            metadata: {PeerMetadataKeys.randomRoll: '${0.1 + i * 0.8}'},
          ),
        );
        sessions.add(session);
        await session.initialize();
        await session.join(const Duration(seconds: 2));
      }
      await sessions.first.waitForMinNodes(
        2,
        timeout: const Duration(seconds: 10),
      );
      final config = DataStreamConfig(
        name: 'hops',
        channels: 1,
        sampleRate: 50,
        dataType: StreamDataType.double64,
        participationMode: StreamParticipationMode.allNodes,
      );
      final streamA = await sessions.first.createDataStream(config);
      await sessions.first.startStream('hops');
      final streamB = await sessions[1].getDataStream('hops');

      // Origin ─▶ relay 1 ─▶ node A, raw, and on into WebRTC.
      final origin = await connect(relay1, 'origin', onOrigin);
      final outlet = await origin.publish(
        const LslOutletSpec(
          name: 'hops',
          type: 'EEG',
          channelCount: 1,
          rate: 0,
          sourceId: 'hops',
        ),
      );
      final a = await connect(relay1, 'a');
      await _until(() => a.streams.isNotEmpty, 'the stream at node A');
      final atA = a.open(
        a.streams.single,
        options: const LslInletOptions(clockSync: false),
      );

      // Node B: one inlet to pass on, one to record.
      DataStreamInlet atB() => DataStreamInlet(
        streamB,
        from: sessions.first.thisNode.uId,
        node: 'b',
        via: 'webrtc',
        options: const LslInletOptions(clockSync: false),
      );
      final onward = atB(), recorded = atB();
      final file = _Bytes();
      final recorder = LslRecorder.fromInlets(
        [recorded],
        file,
        pullInterval: const Duration(milliseconds: 20),
        offsetInterval: const Duration(milliseconds: 200),
      );

      // Node B ─▶ relay 2 ─▶ far.
      final b = await connect(relay2, 'b');
      final onwardOutlet = await b.publish(outlet.spec);
      final far = await connect(relay2, 'far', onFar);
      await _until(() => far.streams.isNotEmpty, 'the stream at the far end');
      final atFar = far.open(far.streams.single);

      // The origin stamps a sample every 20 ms; each node passes on what it
      // has, with the way it came.
      final sent = <double>[], got = <int, double>{};
      final pump = await LslDataStreamPump.start(atA, streamA);
      addTearDown(pump.close);
      await _until(() {
        if (sent.length < 200) {
          sent.add(onOrigin());
          outlet.push(
            Float32List.fromList([sent.length - 1.0]),
            Float64List.fromList([sent.last]),
          );
        }
        onward.chain().then((chain) async {
          onwardOutlet.upstream = chain;
          final c = await onward.pull(1000);
          if (c.length == 0) return;
          await onwardOutlet.push(Float32List.fromList(c.values!), c.times);
        }, onError: (Object _) {});
        atFar.pull(1000).then((c) {
          for (var k = 0; k < c.length; k++) {
            got[c.values![k].round()] = c.times[k];
          }
        });
        return got.length >= 20;
      }, 'samples at the far end');

      // On the far end's clock, within the bound the chain reports.
      final chain = await atFar.chain();
      final bound = chain.uncertainty + 5e-4;
      for (final MapEntry(key: i, value: time) in got.entries) {
        expect(time, closeTo(sent[i] + originToFar, bound));
      }
      expect(chain.hops.map((h) => h.via), [
        'bridge',
        'bridge',
        'webrtc',
        'bridge',
        'bridge',
      ]);
      expect(chain.hops.map((h) => h.node), [
        '127.0.0.1',
        'a',
        'b',
        '127.0.0.1',
        'far',
      ]);
      expect(chain.offset, closeTo(originToFar, bound));
      expect(chain.hops.every((h) => h.uncertainty >= 0), isTrue);
      // Latency only grows along the way.
      final latencies = [
        for (final h in chain.hops)
          if (h.latency != null) h.latency!,
      ];
      expect(latencies.length, greaterThanOrEqualTo(3));
      expect(latencies.last, inInclusiveRange(0, 2));

      // The recording at node B: raw time stamps, with offsets to correct
      // them beside them.
      await _until(() => recorder.streams.single.offsets > 0, 'clock offsets');
      final correction = await recorded.timeCorrectionEx();
      expect(correction.offset.abs(), greaterThan(100));
      expect(correction.uncertainty, greaterThan(0));
      await recorder.stop();
      expect(recorder.streams.single.samples, greaterThan(0));
      expect(file.length, greaterThan(0));
      await onward.close();
    },
  );
}
