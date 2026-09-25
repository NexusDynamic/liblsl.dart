import 'dart:async';

import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/in_memory.dart';

/// Configuration for the in-memory transport.
///
/// Every node that should see every other node must be given the *same*
/// [bus] instance — that shared object is what stands in for the network.
class InMemoryTransportConfig implements ITransportConfig {
  InMemoryTransportConfig({required this.bus});

  /// The medium shared by all nodes in the session.
  final InMemoryBus bus;

  @override
  String get id => 'memory_transport_config';

  @override
  String get name => 'In-Memory Transport Configuration';

  @override
  String get description => 'Configuration for the in-memory transport';

  @override
  ITransport createTransport() => InMemoryTransport(this);

  @override
  bool validate({bool throwOnError = false}) => true;

  @override
  InMemoryTransportConfig copyWith() => InMemoryTransportConfig(bus: bus);

  @override
  Map<String, dynamic> toMap() => {'type': 'memory'};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InMemoryTransportConfig && other.bus == bus;

  @override
  int get hashCode => bus.hashCode;
}

/// A transport that carries coordination entirely within one process.
///
/// Exists for two reasons. It makes the whole stack testable without sockets,
/// native code or timing luck — and it is a second, independent implementation
/// of the transport contract, which is the only way to know the abstraction is
/// real rather than LSL-shaped.
class InMemoryTransport extends ManagedResource
    implements ITransport<InMemoryTransportConfig>, IResourceManager {
  InMemoryTransport(this.config) : super(id: 'memory_transport');

  @override
  final InMemoryTransportConfig config;

  InMemoryBus get bus => config.bus;

  final Map<String, IResource> _resources = {};

  bool _initialized = false;

  @override
  String get name => 'In-Memory Transport';

  @override
  String get description =>
      'Coordination transport backed by an in-process bus';

  @override
  bool get initialized => _initialized;

  @override
  FutureOr<void> initialize() {
    _initialized = true;
  }

  @override
  NetworkStreamFactory get streamFactory => InMemoryNetworkStreamFactory(bus);

  // Null: both "peers" are objects in one process reading one PeerClock, so
  // there is no offset to estimate — it is a known zero, reported through
  // NetworkStream.sharesSenderClockDomain instead.
  @override
  PeerClockOffsets? get clockOffsets => null;

  @override
  Future<IDiscovery> createDiscovery({
    required NetworkStreamConfig streamConfig,
    required CoordinationConfig coordinationConfig,
    required String id,
  }) async {
    final discovery = InMemoryDiscovery(
      bus: bus,
      coordinationConfig: coordinationConfig,
      id: id,
    );
    await discovery.create();
    manageResource(discovery);
    return discovery;
  }

  @override
  void manageResource<R extends IResource>(R resource) {
    _resources[resource.id] = resource;
  }

  @override
  Future<R> releaseResource<R extends IResource>(String resourceId) async {
    final resource = _resources.remove(resourceId);
    if (resource == null) {
      throw ArgumentError('Resource with id $resourceId not found');
    }
    return resource as R;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    final pending = <Future<void>>[];
    for (final resource in _resources.values) {
      if (!resource.disposed) {
        final result = resource.dispose();
        if (result is Future<void>) pending.add(result);
      }
    }
    await Future.wait(pending);
    _resources.clear();
    // The bus is shared between nodes, so it is deliberately NOT disposed
    // here — whoever created it owns it.
    await super.dispose();
  }
}
