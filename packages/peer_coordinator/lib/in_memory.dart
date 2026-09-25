/// An in-process coordination transport.
///
/// Every node shares one [InMemoryBus], which plays the part the network plays
/// for a real transport. Use it to test coordination logic without sockets,
/// native code or timing luck.
library;

export 'transports/memory/memory_bus.dart';
export 'transports/memory/memory_discovery.dart';
export 'transports/memory/memory_stream.dart';
export 'transports/memory/memory_transport.dart';
