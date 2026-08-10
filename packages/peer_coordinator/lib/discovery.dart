/// Transport-neutral peer discovery.
///
/// A transport implements [IDiscovery] over whatever mechanism it has, and the
/// coordination layer only ever speaks [DiscoveryQuery] and [PeerDescriptor].
library;

export 'src/discovery/discovery.dart';
export 'src/discovery/peer_descriptor.dart';
export 'src/discovery/peer_queries.dart';
export 'src/discovery/query.dart';
