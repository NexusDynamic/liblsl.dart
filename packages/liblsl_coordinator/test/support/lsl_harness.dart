/// Shared setup for tests that drive a real LSL network stack.
///
/// ## The one constraint that shapes every LSL test
///
/// `LSL.setConfigContent` writes a process-global configuration that liblsl
/// reads once, when the native library is first loaded. It cannot be changed
/// afterwards, and it cannot differ between nodes in the same process.
///
/// Every node in an LSL test therefore has to live in *one* process under
/// *one* config — which is exactly what `example/multi_node_test.dart` does.
/// Do not try to give nodes different LSL configs; instead isolate tests from
/// each other with [uniqueSessionName].
library;

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
// Re-exports package:liblsl/lsl.dart, which is where LSL/LSLApiConfig come
// from. That re-export is itself part of what couples callers to the LSL
// backend; it is scheduled to be narrowed when the transport is split out.
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:test/test.dart';

/// Multicast group used by the coordination tests.
///
/// Kept distinct from the group used by `example/multi_node_test.dart`
/// (224.0.0.183) and `benchmark/latency_bench.dart` (224.0.0.184) so a stray
/// example or benchmark process on the same machine cannot be discovered by,
/// or interfere with, a test run.
const String testMulticastGroup = '224.0.0.185';

int _sessionCounter = 0;

/// A session name unique to this process and call.
///
/// LSL resolution is machine-wide: any other process on the host running the
/// same session name would be discovered as a peer. Tests must not share one.
String uniqueSessionName([String prefix = 'CoordTest']) {
  _sessionCounter++;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return '${prefix}_${stamp}_$_sessionCounter';
}

/// Installs the process-global LSL configuration for a test file.
///
/// Call once, at the top of `main()`, before any test body runs.
void useLoopbackLsl() {
  setUpAll(() {
    LSL.setConfigContent(
      LSLApiConfig(
        // Pin everything to loopback so tests never touch a real network.
        ipv6: IPv6Mode.disable,
        resolveScope: ResolveScope.link,
        listenAddress: '127.0.0.1',
        addressesOverride: [testMulticastGroup],
        knownPeers: ['127.0.0.1'],
        // Scopes every stream this process creates at the liblsl level.
        // `dart test` runs each test file in its own process, so a
        // process-unique id keeps concurrent files from resolving each
        // other's streams. Within a file, tests additionally use unique
        // session/node/stream names — sessionId cannot vary per test because
        // LSL.setConfigContent is process-global and read once.
        sessionId: 'CoordTest_${DateTime.now().microsecondsSinceEpoch}',
        portRange: 128,
        // Silence the native logger; failures surface through Dart logging.
        logLevel: -2,
        // Aggressive RTTs: on loopback the default resolve timings dominate
        // test runtime. Mirrors packages/liblsl/test/liblsl_resolver_test.dart.
        unicastMinRTT: 0.1,
        multicastMinRTT: 0.1,
        // Tests are short; the watchdog would only add noise.
        watchdogCheckInterval: 600.0,
      ),
    );
  });
}

/// Session timings tuned for tests: several times faster than the defaults
/// (5s / 10s / 15s) but deliberately not as tight as they could be.
///
/// [nodeTimeout] must stay >= 2x [heartbeatInterval] or
/// `CoordinationSessionConfig.validate` rejects it. The ratio matters for more
/// than validation: the coordinator's timeout sweep runs every
/// `nodeTimeout ~/ 2`, and if a heartbeat can be late by more than
/// [nodeTimeout] under load the coordinator evicts a live node and re-admits
/// it moments later. That flapping is observable — it can transiently free a
/// slot and let a node in that should have been rejected for exceeding
/// maxNodes — so keep a wide margin here (4x, not the minimum 2x).
CoordinationSessionConfig testSessionConfig({
  required String sessionName,
  int maxNodes = 3,
  int minNodes = 1,
  bool consumeCoordinationStreamAsCoordinator = false,
}) => CoordinationSessionConfig(
  name: sessionName,
  maxNodes: maxNodes,
  minNodes: minNodes,
  heartbeatInterval: const Duration(milliseconds: 500),
  discoveryInterval: const Duration(milliseconds: 500),
  nodeTimeout: const Duration(seconds: 2),
  consumeCoordinationStreamAsCoordinator:
      consumeCoordinationStreamAsCoordinator,
);

/// Builds a full [CoordinationConfig] for one node in a test session.
///
/// Pass [randomRoll] to make election deterministic: the node with the
/// *lowest* roll wins, because [PromotionStrategyRandom] elects the peer whose
/// roll sorts first and a node becomes a participant as soon as it discovers
/// any peer rolling lower than itself.
CoordinationConfig testCoordinationConfig({
  required String sessionName,
  int maxNodes = 3,
  bool consumeCoordinationStreamAsCoordinator = false,
}) => CoordinationConfig(
  name: 'liblsl_coordinator_test',
  sessionConfig: testSessionConfig(
    sessionName: sessionName,
    maxNodes: maxNodes,
    consumeCoordinationStreamAsCoordinator:
        consumeCoordinationStreamAsCoordinator,
  ),
  topologyConfig: HierarchicalTopologyConfig(
    promotionStrategy: PromotionStrategyRandom(),
    maxNodes: maxNodes,
  ),
  streamConfig: CoordinationStreamConfig(
    name: 'coordination',
    sampleRate: 50.0,
  ),
  transportConfig: LSLTransportConfig(coordinationFrequency: 50.0),
);

/// Creates a node config with a fixed `randomRoll`, making election
/// deterministic across a test.
NodeConfig testNodeConfig({
  required String name,
  required double randomRoll,
  Set<NodeCapability> capabilities = const {
    NodeCapability.coordinator,
    NodeCapability.participant,
  },
}) => NodeConfig(
  name: name,
  id: name,
  capabilities: capabilities,
  metadata: {'randomRoll': randomRoll.toString()},
);
