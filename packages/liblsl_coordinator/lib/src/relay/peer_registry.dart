import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';

/// How a registered peer changed.
enum RegistryChange { attached, updated, detached }

/// A change to the set of registered peers.
class RegistryDelta {
  const RegistryDelta(this.change, this.descriptor);

  final RegistryChange change;
  final PeerDescriptor descriptor;

  @override
  String toString() => '${change.name}: $descriptor';
}

/// The set of peers currently reachable on a relay-style transport.
///
/// Where LSL discovers peers by multicast-resolving the network, a hub or an
/// in-process bus already *knows* who is connected — so discovery reduces to
/// querying this table. Both the in-memory transport and the WebSocket hub use
/// it, which is what lets the hub stay a dumb relay: it holds a registry and a
/// routing table and no protocol logic at all.
///
/// Peers are keyed by [PeerDescriptor.endpointId]: one entry per published
/// stream per node, matching LSL's one-outlet-per-stream model.
class PeerRegistry {
  final Map<String, PeerDescriptor> _peers = {};
  final StreamController<RegistryDelta> _changes =
      StreamController<RegistryDelta>.broadcast();

  /// Emitted whenever a peer is attached, updated or detached.
  Stream<RegistryDelta> get changes => _changes.stream;

  /// Every registered peer.
  Iterable<PeerDescriptor> get peers => List.unmodifiable(_peers.values);

  int get length => _peers.length;

  PeerDescriptor? operator [](String endpointId) => _peers[endpointId];

  /// Registers [descriptor], or updates it if the endpoint is already known.
  ///
  /// Re-registering the same endpoint is an update rather than an error: a
  /// node republishes its descriptor after election changes its role, which is
  /// the relay equivalent of LSL's "recreate the outlet".
  void attach(PeerDescriptor descriptor) {
    final existing = _peers[descriptor.endpointId];
    _peers[descriptor.endpointId] = descriptor;
    if (existing == null) {
      _emit(RegistryChange.attached, descriptor);
    } else if (existing != descriptor) {
      _emit(RegistryChange.updated, descriptor);
    }
  }

  /// Removes a peer. Returns the removed descriptor, or null if unknown.
  PeerDescriptor? detach(String endpointId) {
    final removed = _peers.remove(endpointId);
    if (removed != null) _emit(RegistryChange.detached, removed);
    return removed;
  }

  /// Removes every endpoint belonging to [nodeUId].
  ///
  /// Used when a connection drops: one node may publish several streams, and
  /// all of them die with the connection.
  List<PeerDescriptor> detachNode(String nodeUId) {
    final doomed = _peers.values
        .where((p) => p.nodeUId == nodeUId)
        .map((p) => p.endpointId)
        .toList(growable: false);
    return [for (final endpointId in doomed) detach(endpointId)!];
  }

  /// Every peer matching [query].
  ///
  /// The query is evaluated directly — no compilation step — because a relay
  /// transport holds the descriptors in memory. This is the same
  /// [DiscoveryQuery] the LSL transport compiles to XPath, so both backends
  /// answer identically.
  List<PeerDescriptor> match(DiscoveryQuery query) =>
      _peers.values.where(query.matches).toList(growable: false);

  void _emit(RegistryChange change, PeerDescriptor descriptor) {
    if (_changes.isClosed) return;
    _changes.add(RegistryDelta(change, descriptor));
  }

  void clear() => _peers.clear();

  void dispose() {
    _peers.clear();
    _changes.close();
  }
}
