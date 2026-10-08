/// A stream's receive health has to reach the session's events.
///
/// A transport can lose its receiving end for one peer without losing the
/// peer: on LSL, the isolate listening to an inlet can end while the inlet
/// stays open. The stream reports that on `inletHealth`, which nobody
/// listens to unless they hold the stream. The session's events are where an
/// application is already listening, so that is where it has to appear, for
/// data streams and for the coordination stream alike.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBus bus;
  late PeerSession session;
  late _ReportingTransport transport;

  setUp(() async {
    bus = InMemoryBus();
    transport = _ReportingTransport(InMemoryTransportConfig(bus: bus));
    session = PeerSession(
      CoordinationConfig(
        name: 'receive_health_test',
        sessionConfig: CoordinationSessionConfig(
          name: 'ReceiveHealthSession',
          maxNodes: 2,
          minNodes: 1,
          heartbeatInterval: const Duration(milliseconds: 50),
          discoveryInterval: const Duration(milliseconds: 25),
          nodeTimeout: const Duration(milliseconds: 400),
        ),
        topologyConfig: HierarchicalTopologyConfig(
          promotionStrategy: PromotionStrategyRandom(),
          maxNodes: 2,
        ),
        streamConfig: CoordinationStreamConfig(name: 'coordination'),
        transportConfig: InMemoryTransportConfig(bus: bus),
      ),
      transport: transport,
      thisNodeConfig: NodeConfig(
        name: 'solo',
        id: 'solo',
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
      ),
    );
    await session.initialize();
    await session.join(const Duration(milliseconds: 500));
  });

  tearDown(() async {
    try {
      await session.leave();
    } catch (_) {
      // Teardown must not mask the assertion that failed.
    }
    try {
      await session.dispose();
    } catch (_) {}
    await transport.health.close();
    bus.dispose();
  });

  test('a data stream that stops receiving from a peer says so', () async {
    await session.createDataStream(
      DataStreamConfig(
        name: 'Data',
        channels: 1,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
      ),
    );
    final events = <StreamReceiveHealthEvent>[];
    final sub = session.events.streamReceiveHealth
        .where((e) => e.streamName == 'Data')
        .listen(events.add);
    addTearDown(sub.cancel);

    transport.health.add(
      const InletHealth(
        sourceId: 'peer',
        healthy: false,
        consecutiveFailures: 2,
        error: 'listener ended',
        willRetry: true,
      ),
    );
    transport.health.add(const InletHealth(sourceId: 'peer', healthy: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(events, hasLength(2));
    final down = events.first;
    expect(down.sourceId, 'peer');
    expect(down.healthy, isFalse);
    expect(down.consecutiveFailures, 2);
    expect(down.error, 'listener ended');
    expect(down.willRetry, isTrue);
    expect(down.fromNodeUId, session.thisNode.uId);
    expect(events.last.healthy, isTrue);
    expect(events.last.consecutiveFailures, 0);
  });

  test('so does the coordination stream', () async {
    final event = session.events.streamReceiveHealth
        .where((e) => e.streamName == 'coordination')
        .first;
    transport.health.add(
      const InletHealth(sourceId: 'coordinator', healthy: false),
    );
    final down = await event.timeout(const Duration(seconds: 2));
    expect(down.sourceId, 'coordinator');
    expect(down.healthy, isFalse);
    expect(down.willRetry, isFalse);
  });
}

/// In-memory streams have no receiving end that can fail on its own, so
/// these report whatever the test says happened.
class _ReportingDataStream extends InMemoryDataStream {
  _ReportingDataStream(
    this._health, {
    required super.config,
    required super.bus,
    required super.sessionName,
    required super.streamNode,
  });

  final Stream<InletHealth> _health;

  @override
  Stream<InletHealth> get inletHealth => _health;
}

class _ReportingCoordinationStream extends InMemoryCoordinationStream {
  _ReportingCoordinationStream(
    this._health, {
    required super.config,
    required super.bus,
    required super.sessionName,
    required super.streamNode,
  });

  final Stream<InletHealth> _health;

  @override
  Stream<InletHealth> get inletHealth => _health;
}

class _ReportingFactory extends InMemoryNetworkStreamFactory {
  _ReportingFactory(super.bus, this._health);

  final Stream<InletHealth> _health;

  @override
  Future<InMemoryDataStream> createDataStream(
    DataStreamConfig config,
    CoordinationSession session,
  ) async => _ReportingDataStream(
    _health,
    config: config,
    bus: bus,
    sessionName: session.config.name,
    streamNode: session.thisNode,
  );

  @override
  Future<InMemoryCoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config,
    CoordinationSession session,
  ) async => _ReportingCoordinationStream(
    _health,
    config: config,
    bus: bus,
    sessionName: session.config.name,
    streamNode: session.thisNode,
  );
}

class _ReportingTransport extends InMemoryTransport {
  _ReportingTransport(super.config);

  final StreamController<InletHealth> health =
      StreamController<InletHealth>.broadcast();

  @override
  NetworkStreamFactory get streamFactory =>
      _ReportingFactory(bus, health.stream);
}
