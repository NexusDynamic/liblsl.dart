/// An in-process coordination transport.
///
/// Every node shares one [InMemoryBus], which plays the part the network plays
/// for the LSL transport. Use it to test coordination logic without sockets,
/// native code or timing luck.
library;

export 'memory/memory_bus.dart';
export 'memory/memory_discovery.dart';
export 'memory/memory_stream.dart';
export 'memory/memory_transport.dart';
