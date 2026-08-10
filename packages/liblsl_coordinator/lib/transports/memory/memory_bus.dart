import 'dart:async';
import 'dart:math';

import 'package:liblsl_coordinator/framework.dart';

/// One published sample or message, as it travels over the bus.
class BusEnvelope {
  const BusEnvelope({
    required this.streamName,
    required this.fromEndpointId,
    required this.payload,
  });

  final String streamName;
  final String fromEndpointId;

  /// The message. Passed by reference — nodes share a heap here, so there is
  /// no serialisation step and none is simulated. That is a deliberate
  /// difference from a real transport and the reason the in-memory backend
  /// cannot catch serialisation bugs; the JSON round-trip tests cover those.
  final Object payload;
}

/// The shared medium every in-memory node connects to.
///
/// N sessions in one process share one instance, and it plays the part LSL's
/// network — or the WebSocket hub — plays elsewhere: it holds the peer
/// registry, the routing table, and delivers published messages to
/// subscribers.
///
/// Its purpose is to make the whole coordination stack testable with no
/// sockets, no native code and no timing luck, and to prove by construction
/// that the abstraction really is transport-neutral. Anything the coordination
/// layer needs that cannot be expressed here is coupling that leaked.
class InMemoryBus {
  InMemoryBus({
    this.latency = Duration.zero,
    this.dropRate = 0.0,
    Random? random,
  }) : _random = random ?? Random(),
       assert(dropRate >= 0.0 && dropRate <= 1.0);

  /// Artificial delivery delay, for exercising code that assumes messages are
  /// not instantaneous.
  final Duration latency;

  /// Fraction of messages to drop, for fault-injection tests.
  final double dropRate;

  final Random _random;

  final PeerRegistry registry = PeerRegistry();
  final RelayRouting routing = RelayRouting();

  /// Inboxes, keyed by subscriber endpoint id.
  final Map<String, StreamController<BusEnvelope>> _inboxes = {};

  bool _disposed = false;

  /// Registers an endpoint and returns its inbox.
  Stream<BusEnvelope> connect(String endpointId) {
    final controller = _inboxes.putIfAbsent(
      endpointId,
      () => StreamController<BusEnvelope>.broadcast(),
    );
    return controller.stream;
  }

  /// Removes an endpoint, its routes and its registry entry.
  void disconnect(String endpointId) {
    routing.removeEndpoint(endpointId);
    registry.detach(endpointId);
    final controller = _inboxes.remove(endpointId);
    controller?.close();
  }

  /// Publishes [payload] to everyone subscribed to this producer's stream.
  ///
  /// Delivery is *always* asynchronous, even with zero latency. Calling
  /// subscribers synchronously would let a handler re-enter the code that
  /// published, which no real transport can do — the conformance suite would
  /// then be validating behaviour that only exists in tests.
  void publish({
    required String streamName,
    required String fromEndpointId,
    required Object payload,
  }) {
    if (_disposed) return;
    final subscribers = routing.subscribersFor(
      streamName: streamName,
      producerEndpointId: fromEndpointId,
    );
    if (subscribers.isEmpty) return;

    final envelope = BusEnvelope(
      streamName: streamName,
      fromEndpointId: fromEndpointId,
      payload: payload,
    );

    for (final subscriber in subscribers) {
      if (dropRate > 0 && _random.nextDouble() < dropRate) continue;
      _deliver(subscriber, envelope);
    }
  }

  void _deliver(String endpointId, BusEnvelope envelope) {
    void send() {
      if (_disposed) return;
      final controller = _inboxes[endpointId];
      if (controller == null || controller.isClosed) return;
      controller.add(envelope);
    }

    if (latency == Duration.zero) {
      // Still a turn of the event loop: never synchronous.
      Timer.run(send);
    } else {
      Timer(latency, send);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final controller in _inboxes.values) {
      controller.close();
    }
    _inboxes.clear();
    routing.clear();
    registry.dispose();
  }
}
