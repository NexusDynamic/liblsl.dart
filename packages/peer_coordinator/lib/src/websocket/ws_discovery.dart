import 'dart:async';

import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/src/websocket/ws_connection.dart';
import 'package:peer_coordinator/src/websocket/ws_protocol.dart';

/// A peer the hub told us about.
class WsPeerHandle extends ManagedResource implements PeerHandle {
  WsPeerHandle(this.descriptor, {this.slot, super.manager})
    : super(id: 'ws-peer-${descriptor.endpointId}') {
    create();
  }

  @override
  final PeerDescriptor descriptor;

  /// The hub's numeric id for this endpoint, used in binary sample frames.
  final int? slot;

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
    manager?.releaseResource<WsPeerHandle>(id);
  }
}

/// [IDiscovery] backed by the hub's peer registry.
///
/// The hub already knows who is connected, so a query is a round trip rather
/// than a network resolve — but the *timing* contract is the same as LSL's,
/// which matters for election. See [discoverOnce].
class WsDiscovery extends ManagedResource
    implements IDiscovery, IResourceManager {
  WsDiscovery({
    required this.connection,
    required this.coordinationConfig,
    required super.id,
    super.manager,
  });

  final WsConnection connection;
  final CoordinationConfig coordinationConfig;

  final Map<String, WsPeerHandle> _handles = {};
  final StreamController<DiscoveryEvent> _events =
      StreamController<DiscoveryEvent>();

  StreamSubscription<WsFrame>? _controlSubscription;
  Timer? _timeoutTimer;
  int? _queryId;
  bool _paused = false;

  @override
  bool get paused => _paused;

  @override
  Stream<DiscoveryEvent> get events => _events.stream;

  @override
  void manageResource<R extends IResource>(R resource) {
    if (resource is! WsPeerHandle) {
      throw ArgumentError(
        'WsDiscovery can only manage WsPeerHandle instances, '
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

    _controlSubscription = connection.control.listen((frame) {
      if (frame.type != WsControl.queryResult) return;
      if (frame.payload['qid'] != _queryId) return;
      if (_paused || disposed || _events.isClosed) return;

      final peers = _peersFrom(frame);
      if (peers.isEmpty) return;
      for (final handle in peers) {
        manageResource(handle);
      }
      _events.add(PeersDiscoveredEvent(query, peers));
    });

    if (timeout != null) {
      _timeoutTimer = Timer(timeout, () {
        if (disposed || _events.isClosed) return;
        _events.add(DiscoveryTimeoutEvent(query, timeout));
      });
    }

    // The hub pushes an updated result whenever the matching set grows, so no
    // polling is needed here — unlike LSL, which must re-resolve on a timer.
    _queryId = connection.query(query, continuous: true);
  }

  List<WsPeerHandle> _peersFrom(WsFrame frame) => [
    for (final entry in (frame.payload['peers'] as List))
      WsPeerHandle(
        PeerDescriptor.fromJson(
          (entry as Map<String, dynamic>)['peer'] as Map<String, dynamic>,
        ),
        slot: entry['slot'] as int?,
      ),
  ];

  @override
  void stop() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _controlSubscription?.cancel();
    _controlSubscription = null;
    if (_queryId != null) {
      connection.unquery(_queryId!);
      _queryId = null;
    }
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
    // Election depends on this waiting out the timeout when nothing matches:
    // "no better candidate exists" is only knowable by asking and hearing
    // nothing back for long enough. Returning early on an empty result would
    // make every node elect itself and split the session.
    final deadline = DateTime.now().add(timeout);
    final results = <WsPeerHandle>[];
    final completer = Completer<void>();

    final qid = connection.query(query, continuous: true);
    final subscription = connection.control.listen((frame) {
      if (frame.type != WsControl.queryResult) return;
      if (frame.payload['qid'] != qid) return;
      results
        ..clear()
        ..addAll(_peersFrom(frame));
      if (results.length >= minPeers &&
          results.isNotEmpty &&
          !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      if (minPeers > 0) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining > Duration.zero) {
          await completer.future.timeout(remaining, onTimeout: () {});
        }
      } else {
        // Give the hub one round trip to answer.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      await subscription.cancel();
      connection.unquery(qid);
    }

    if (results.length < minPeers) return const [];
    return results.take(maxPeers).toList(growable: false);
  }

  @override
  void pause() {
    _paused = true;
  }

  @override
  void resume() {
    _paused = false;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    stop();
    await super.dispose();
    unawaited(_events.close());
  }
}
