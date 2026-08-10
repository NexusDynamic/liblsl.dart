/// Who receives what, on a relay-style transport.
///
/// LSL has no equivalent: an inlet connects straight to an outlet and the
/// network does the rest. A relay has to be told, so `addInlet` becomes a
/// subscription recorded here, and every published sample is fanned out to the
/// subscribers of that exact (stream, producer) pair.
///
/// Keeping the routing table separate from the socket handling is what lets
/// the in-memory transport and the WebSocket hub share it — and it means the
/// fan-out logic is unit-testable without any I/O.
class RelayRouting {
  /// (streamName, producerEndpointId) -> subscriber endpoint ids.
  final Map<String, Map<String, Set<String>>> _subscribers = {};

  /// Records that [subscriberEndpointId] wants [streamName] from
  /// [producerEndpointId].
  ///
  /// Idempotent: a repeated subscription is not an error, because discovery
  /// re-reports the same peer on every cycle.
  void subscribe({
    required String streamName,
    required String producerEndpointId,
    required String subscriberEndpointId,
  }) {
    _subscribers
        .putIfAbsent(streamName, () => {})
        .putIfAbsent(producerEndpointId, () => {})
        .add(subscriberEndpointId);
  }

  /// Removes one subscription.
  void unsubscribe({
    required String streamName,
    required String producerEndpointId,
    required String subscriberEndpointId,
  }) {
    final byProducer = _subscribers[streamName];
    if (byProducer == null) return;
    byProducer[producerEndpointId]?.remove(subscriberEndpointId);
    if (byProducer[producerEndpointId]?.isEmpty ?? false) {
      byProducer.remove(producerEndpointId);
    }
    if (byProducer.isEmpty) _subscribers.remove(streamName);
  }

  /// Drops every route mentioning [endpointId], as producer or subscriber.
  ///
  /// Called when a peer disconnects. Both directions matter: leaving a dead
  /// producer in the table wastes lookups, and leaving a dead subscriber means
  /// sending into a closed socket.
  void removeEndpoint(String endpointId) {
    for (final streamName in _subscribers.keys.toList(growable: false)) {
      final byProducer = _subscribers[streamName]!;
      byProducer.remove(endpointId);
      for (final producer in byProducer.keys.toList(growable: false)) {
        byProducer[producer]!.remove(endpointId);
        if (byProducer[producer]!.isEmpty) byProducer.remove(producer);
      }
      if (byProducer.isEmpty) _subscribers.remove(streamName);
    }
  }

  /// Who should receive a sample published on [streamName] by
  /// [producerEndpointId].
  Set<String> subscribersFor({
    required String streamName,
    required String producerEndpointId,
  }) {
    final direct = _subscribers[streamName]?[producerEndpointId];
    if (direct == null || direct.isEmpty) return const {};
    return Set.unmodifiable(direct);
  }

  /// Whether anyone is subscribed to this producer's stream.
  bool hasSubscribers({
    required String streamName,
    required String producerEndpointId,
  }) => _subscribers[streamName]?[producerEndpointId]?.isNotEmpty ?? false;

  void clear() => _subscribers.clear();
}
