/// The `removeInlet` half of the stream contract.
///
/// `addInlet` has always had no counterpart. That was survivable while every
/// transport was a relay — a stale route is inert and the hub drops it when the
/// producer's socket closes — but a peer-to-peer transport holds a live
/// connection behind each inlet and has to release it on departure.
///
/// These tests pin the contract itself (idempotence, the no-op default) and the
/// two relay implementations, against the hub's routing table where possible so
/// the assertion is about what the network does, not about a private field.
@Tags(['integration'])
library;

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:test/test.dart';

void main() {
  group('the default is a no-op', () {
    test('removing an inlet on a stream that never had one is not an error',
        () async {
      final bus = InMemoryBus();
      addTearDown(bus.dispose);

      final node = Node(NodeConfig(name: 'n', id: 'n'));
      final stream = InMemoryDataStream(
        config: DataStreamConfig(
        name: 'Data',
        channels: 1,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
      ),
        bus: bus,
        sessionName: 'S',
        streamNode: node,
      );
      await stream.create();
      addTearDown(stream.dispose);

      // Idempotent, and safe for a uId that was never subscribed.
      await stream.removeInlet('never-seen');
      await stream.removeInlet('never-seen');
    });
  });

  group('in-memory', () {
    late InMemoryBus bus;

    setUp(() => bus = InMemoryBus());
    tearDown(() => bus.dispose());

    /// A stream published by [uId], plus a consumer subscribed to it.
    Future<(InMemoryDataStream, InMemoryDataStream, String)> pair() async {
      final config = DataStreamConfig(
        name: 'Data',
        channels: 1,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
      );
      final producerNode = Node(NodeConfig(name: 'p', id: 'p'));
      final consumerNode = Node(NodeConfig(name: 'c', id: 'c'));

      final producer = InMemoryDataStream(
        config: config,
        bus: bus,
        sessionName: 'S',
        streamNode: producerNode,
      );
      final consumer = InMemoryDataStream(
        config: config,
        bus: bus,
        sessionName: 'S',
        streamNode: consumerNode,
      );
      await producer.create();
      await consumer.create();
      await producer.createOutlet();
      await consumer.createInletsForNodes([producerNode]);
      return (producer, consumer, producerNode.uId);
    }

    test('drops the route it installed', () async {
      final (producer, consumer, producerUId) = await pair();
      addTearDown(producer.dispose);
      addTearDown(consumer.dispose);

      final producerEndpoint = 'S/$producerUId/Data';
      expect(
        bus.routing.subscribersFor(
          streamName: 'Data',
          producerEndpointId: producerEndpoint,
        ),
        isNotEmpty,
        reason: 'createInletsForNodes should have installed a route',
      );

      await consumer.removeInlet(producerUId);

      expect(
        bus.routing.subscribersFor(
          streamName: 'Data',
          producerEndpointId: producerEndpoint,
        ),
        isEmpty,
      );
    });

    test('is idempotent and lets the peer be re-added', () async {
      final (producer, consumer, producerUId) = await pair();
      addTearDown(producer.dispose);
      addTearDown(consumer.dispose);

      final producerEndpoint = 'S/$producerUId/Data';

      await consumer.removeInlet(producerUId);
      await consumer.removeInlet(producerUId);

      // A peer that leaves and rejoins must not be blocked by the dedupe set
      // that addInlet keeps.
      await consumer.createInletsForNodes([producer.streamNode]);
      expect(
        bus.routing.subscribersFor(
          streamName: 'Data',
          producerEndpointId: producerEndpoint,
        ),
        isNotEmpty,
      );
    });
  });

  group('websocket', () {
    late CoordinationHub hub;
    late Uri hubUri;

    setUp(() async {
      hub = await CoordinationHub.serve();
      hubUri = Uri.parse('ws://127.0.0.1:${hub.port}');
    });
    tearDown(() => hub.close());

    test('tears the hub route down, not just the local filter', () async {
      final config = DataStreamConfig(
        name: 'Data',
        channels: 1,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
      );
      final producerNode = Node(NodeConfig(name: 'p', id: 'p'));
      final consumerNode = Node(NodeConfig(name: 'c', id: 'c'));

      final producerConnection = WsConnection(hubUri);
      final consumerConnection = WsConnection(hubUri);
      await producerConnection.connect();
      await consumerConnection.connect();
      addTearDown(producerConnection.close);
      addTearDown(consumerConnection.close);

      final producer = WsDataStream(
        config: config,
        connection: producerConnection,
        sessionName: 'S',
        streamNode: producerNode,
      );
      final consumer = WsDataStream(
        config: config,
        connection: consumerConnection,
        sessionName: 'S',
        streamNode: consumerNode,
      );
      await producer.create();
      await consumer.create();
      await producer.createOutlet();
      await consumer.createInletsForNodes([producerNode]);
      // `subscribe` is fire-and-forget over the socket; let the hub see it.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final producerEndpoint = 'S/${producerNode.uId}/Data';
      expect(
        hub.subscribersFor(
          streamName: 'Data',
          producerEndpointId: producerEndpoint,
        ),
        isNotEmpty,
      );

      await consumer.removeInlet(producerNode.uId);
      // The frame is fire-and-forget; give the hub a turn to process it.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        hub.subscribersFor(
          streamName: 'Data',
          producerEndpointId: producerEndpoint,
        ),
        isEmpty,
        reason: 'WsControl.unsubscribe should have reached the hub',
      );

      await producer.dispose();
      await consumer.dispose();
    });
  });
}
