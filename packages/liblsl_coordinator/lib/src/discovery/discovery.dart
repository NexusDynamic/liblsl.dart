import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';

/// A discovered peer, together with whatever transport-owned resource is
/// needed to actually connect to it.
///
/// ## Ownership
///
/// This type exists to make a use-after-free unrepresentable rather than
/// merely commented.
///
/// Continuous discovery re-resolves on a timer and frees the resources from
/// the previous cycle. For LSL those resources are native `lsl_streaminfo`
/// pointers, so a handle that is still in use when its cycle ends becomes a
/// dangling pointer. The original code avoided this with a bare
/// `releaseResource` call at the one call site that needed it, guarded only by
/// a comment — and the *other* call site did it differently.
///
/// Now [take] transfers ownership explicitly, and
/// [NetworkStream.addInlet] calls it as its first action, so there is no
/// window in which a caller can consume a handle the discovery cycle still
/// believes it owns.
abstract class PeerHandle implements IResource {
  /// What was discovered.
  PeerDescriptor get descriptor;

  /// Whether the discovery instance still owns (and will free) the underlying
  /// resource.
  bool get ownedByDiscovery;

  /// Whether [take] has already been called.
  bool get taken;

  /// Detaches from the discovery manager, transferring ownership to the caller.
  ///
  /// After this the discovery cycle will never free the underlying resource;
  /// the caller must dispose it. Safe to call on a handle that was never owned
  /// by discovery (a one-shot `discoverOnce` result), where it is a no-op.
  ///
  /// Throws [StateError] if called twice, or after disposal.
  void take();

  /// The transport's private payload — an `LSLStreamInfo` for LSL, a
  /// connection id for a hub transport.
  ///
  /// Only the transport that produced this handle may interpret it. Reading it
  /// anywhere else re-couples the coordination layer to a specific backend,
  /// which is the coupling this whole abstraction exists to remove.
  Object? get rawUnsafe;
}

/// Something a discovery instance reports.
sealed class DiscoveryEvent {
  const DiscoveryEvent(this.query);

  /// The query that produced this event.
  final DiscoveryQuery query;
}

/// One or more peers matched.
///
/// Only emitted for non-empty results, matching the original LSL behaviour: a
/// resolve cycle that finds nothing is silent rather than emitting an empty
/// list.
final class PeersDiscoveredEvent extends DiscoveryEvent {
  const PeersDiscoveredEvent(super.query, this.peers);

  /// The matched peers. Ownership stays with discovery until [PeerHandle.take].
  final List<PeerHandle> peers;
}

/// A bounded discovery gave up before finding what it was asked for.
final class DiscoveryTimeoutEvent extends DiscoveryEvent {
  const DiscoveryTimeoutEvent(super.query, this.timeout);

  final Duration timeout;
}

/// Finds peers on the network.
///
/// Each transport implements this over whatever mechanism it has: LSL
/// multicast-resolves stream metadata, a hub transport asks the hub. The
/// coordination layer only ever speaks [DiscoveryQuery] and [PeerDescriptor].
abstract interface class IDiscovery implements IResource, IPausable {
  /// Peers found by the continuous discovery started with [start].
  Stream<DiscoveryEvent> get events;

  /// Begins continuous discovery, reporting matches on [events] until [stop].
  ///
  /// Only one continuous query runs at a time; calling this again replaces it.
  void start({required DiscoveryQuery query, Duration? timeout, int? maxPeers});

  /// Stops continuous discovery. Safe to call when not running.
  void stop();

  /// Runs a single bounded discovery.
  ///
  /// Returns as soon as [minPeers] have been found, or when [timeout] expires —
  /// so a query expected to match nothing costs the full [timeout]. Election
  /// relies on exactly that: "no better candidate" can only be concluded by
  /// waiting the query out.
  ///
  /// Handles returned here are not owned by any discovery cycle, so
  /// [PeerHandle.take] on them is a no-op and the caller is responsible for
  /// disposing any it does not pass to a stream.
  Future<List<PeerHandle>> discoverOnce(
    DiscoveryQuery query, {
    Duration timeout = const Duration(seconds: 2),
    int minPeers = 0,
    int maxPeers = 10,
  });
}
