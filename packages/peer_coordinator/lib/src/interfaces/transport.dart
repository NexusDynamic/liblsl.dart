import 'dart:async';

import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';

/// Interface for all transport configurations.
///
/// A config knows how to build its own transport. That is deliberately a
/// method here rather than a global transport registry: a registry would need
/// every transport to register itself at library-initialisation time, which
/// makes each one reachable from the core barrel and therefore un-tree-shakable
/// — so an app using only LSL would still compile in the WebSocket transport
/// and its dependencies. With this shape the only reference to a transport
/// class is from its own config, which nothing reaches unless the application
/// names it.
///
/// (If `CoordinationConfig.fromMap` is ever implemented, deserialisation *will*
/// need a registry keyed by a `transportKind` discriminator. Put it in the
/// deserialiser alone, so only callers who ask for it pay for it.)
abstract interface class ITransportConfig implements IConfig {
  /// Builds a transport from this configuration.
  ITransport createTransport();
}

/// A transport that must prove an identity to something remote.
///
/// Opt-in rather than part of [ITransport]: only a relay-backed transport has
/// anyone to authenticate *to*. LSL peers announce themselves on the local
/// network and the in-memory bus is inside one process, so neither has a
/// credential to present.
///
/// [PeerSession] sets [localNodeUId] before initialising the transport, because
/// a hub binds every endpoint a connection claims to the node that
/// authenticated on it — without the identity up front, a peer could claim an
/// endpoint id belonging to a node that has not registered yet.
abstract interface class IAuthenticatedTransport {
  /// The node identity this transport authenticates with.
  set localNodeUId(String nodeUId);
}

/// Interface for all transport implementations.
///
/// Transports are [IResourceManager]s because they are what actually own the
/// endpoints a session creates — outlets, inlets, sockets, discovery handles.
/// [CoordinationSession] delegates its own resource management straight
/// through to the transport, so this is a requirement in practice and is
/// stated here rather than discovered by a failed cast.
abstract interface class ITransport<T extends ITransportConfig>
    implements
        IConfigurable<T>,
        IInitializable,
        IIdentity,
        ILifecycle,
        IResourceManager {
  /// Builds this transport's streams.
  NetworkStreamFactory get streamFactory;

  /// Creates a discovery instance for finding peers on this transport.
  Future<IDiscovery> createDiscovery({
    required NetworkStreamConfig streamConfig,
    required CoordinationConfig coordinationConfig,
    required String id,
  });

  /// Per-peer clock offsets for this process, or null if this transport does
  /// not need them.
  ///
  /// An offset is a property of the peer *process*, not of any one stream, so
  /// there is one table per transport and every stream on it — coordination and
  /// data alike — reads the same entries.
  ///
  /// Null for LSL, which has native `lsl_time_correction` per inlet, and for
  /// the in-memory transport, whose peers share a clock so the offset is a
  /// known zero. Non-null for WebSocket, where the peers' monotonic epochs are
  /// unrelated and [ClockSyncService] fills this in.
  PeerClockOffsets? get clockOffsets;
}
