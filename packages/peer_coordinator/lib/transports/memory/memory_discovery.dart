import 'dart:async';

import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/in_memory.dart';

/// A peer found on an [InMemoryBus].
///
/// There is no native resource behind this, so [take] is pure bookkeeping —
/// which is precisely the point: the same ownership assertions in the
/// conformance suite run against this and against LSL, where getting it wrong
/// frees a live pointer.
class InMemoryPeerHandle extends ManagedResource implements PeerHandle {
  InMemoryPeerHandle(this.descriptor, {super.manager})
    : super(id: 'memory-peer-${descriptor.endpointId}') {
    create();
  }

  @override
  final PeerDescriptor descriptor;

  bool _taken = false;

  @override
  bool get taken => _taken;

  @override
  bool get ownedByDiscovery => !_taken && manager != null;

  @override
  Object? get rawUnsafe => descriptor.endpointId;

  @override
  void take() {
    if (disposed) {
      throw StateError('Cannot take a disposed peer handle ($id)');
    }
    if (_taken) {
      throw StateError(
        'Peer handle $id has already been taken; ownership can only transfer '
        'once',
      );
    }
    _taken = true;
    manager?.releaseResource<InMemoryPeerHandle>(id);
  }
}

/// [IDiscovery] over an [InMemoryBus].
///
/// Because the bus already knows who is connected, discovery is a query
/// against [PeerRegistry] rather than a network resolve. The timing semantics
/// still have to match, though — see [discoverOnce].
class InMemoryDiscovery extends ManagedResource
    implements IDiscovery, IResourceManager {
  InMemoryDiscovery({
    required this.bus,
    required this.coordinationConfig,
    required super.id,
    super.manager,
  });

  final InMemoryBus bus;
  final CoordinationConfig coordinationConfig;

  final Map<String, InMemoryPeerHandle> _handles = {};
  final StreamController<DiscoveryEvent> _events =
      StreamController<DiscoveryEvent>();

  StreamSubscription<RegistryDelta>? _registrySubscription;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  DiscoveryQuery? _query;
  int? _maxPeers;

  bool _paused = false;

  @override
  bool get paused => _paused;

  @override
  Stream<DiscoveryEvent> get events => _events.stream;

  @override
  void manageResource<R extends IResource>(R resource) {
    if (resource is! InMemoryPeerHandle) {
      throw ArgumentError(
        'InMemoryDiscovery can only manage InMemoryPeerHandle instances, '
        'got ${resource.runtimeType}',
      );
    }
    resource.updateManager(this);
    _handles[resource.id] = resource;
  }

  @override
  R releaseResource<R extends IResource>(String resourceUId) {
    final resource = _handles.remove(resourceUId);
    if (resource == null) {
      throw ArgumentError('Resource with id $resourceUId not found');
    }
    resource.updateManager(null);
    return resource as R;
  }

  @override
  void start({
    required DiscoveryQuery query,
    Duration? timeout,
    int? maxPeers,
  }) {
    if (disposed) throw StateError('Discovery is disposed');
    stop();
    _query = query;
    _maxPeers = maxPeers ?? coordinationConfig.topologyConfig.maxNodes;

    if (timeout != null) {
      _timeoutTimer = Timer(timeout, () {
        if (disposed || _events.isClosed) return;
        _events.add(DiscoveryTimeoutEvent(query, timeout));
      });
    }

    // React to registry changes immediately, and also poll on the configured
    // interval so behaviour matches the LSL transport's periodic resolve
    // (which is what the timing in tests is tuned against).
    _registrySubscription = bus.registry.changes.listen((_) => _sweep());
    _pollTimer = Timer.periodic(
      coordinationConfig.sessionConfig.discoveryInterval,
      (_) => _sweep(),
    );
    _sweep();
  }

  void _sweep() {
    if (disposed || _paused || _query == null || _events.isClosed) return;

    final matches = bus.registry.match(_query!);
    if (matches.isEmpty) return; // Empty results are silent, as with LSL.

    final limited = matches.take(_maxPeers ?? matches.length);
    final handles = <InMemoryPeerHandle>[];
    for (final descriptor in limited) {
      final handle = InMemoryPeerHandle(descriptor);
      manageResource(handle);
      handles.add(handle);
    }
    _events.add(PeersDiscoveredEvent(_query!, handles));
  }

  @override
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _registrySubscription?.cancel();
    _registrySubscription = null;
    _releaseUntaken();
  }

  void _releaseUntaken() {
    for (final handle in _handles.values.toList(growable: false)) {
      if (handle.ownedByDiscovery && !handle.disposed) handle.dispose();
    }
    _handles.clear();
  }

  @override
  Future<List<PeerHandle>> discoverOnce(
    DiscoveryQuery query, {
    Duration timeout = const Duration(seconds: 2),
    int minPeers = 0,
    int maxPeers = 10,
  }) async {
    // Timing here is load-bearing, not incidental. Election concludes "there
    // is no better candidate" only by running this query and getting nothing
    // back *after waiting the full timeout*. Returning early on an empty
    // result would make every node elect itself instantly, and two nodes
    // starting together would both become coordinator.
    //
    // So: return as soon as minPeers are found, otherwise wait it out.
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final matches = bus.registry.match(query);
      if (matches.length >= minPeers && matches.isNotEmpty) {
        return matches
            .take(maxPeers)
            .map(InMemoryPeerHandle.new)
            .toList(growable: false);
      }
      if (minPeers == 0) return const [];
      if (!DateTime.now().isBefore(deadline)) return const [];
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  void pause() {
    _paused = true;
  }

  @override
  void resume() {
    if (!_paused) return;
    _paused = false;
    _sweep();
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    stop();
    await super.dispose();
    unawaited(_events.close());
  }
}
