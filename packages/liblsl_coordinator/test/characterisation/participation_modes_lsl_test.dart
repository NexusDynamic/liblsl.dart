/// Runs the shared participation-mode conformance scenarios over LSL.
///
/// The same assertions run against the in-memory and WebSocket transports in
/// `peer_coordinator`. Participation mode is a property of the coordination
/// layer, not of how bytes move, so a divergence here is an LSL transport
/// issue rather than a difference of opinion — see [_LslHarness.skippedModes]
/// for what this suite found.
///
/// Tagged `lsl` because it needs a real LSL stack on loopback: excluded from
/// the default run, included by `melos run test:lsl`.
@Tags(['lsl', 'integration'])
library;

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:peer_coordinator/testing.dart';
import 'package:test/test.dart';

import '../support/lsl_harness.dart';

class _LslHarness extends ParticipationHarness {
  late String _sessionName;

  @override
  String get name => 'lsl';

  // Generous: every node runs a real resolve, and the eventual coordinator
  // always waits out its election timeout in full.
  @override
  Duration get joinTimeout => const Duration(seconds: 4);

  @override
  Duration get settleTimeout => const Duration(seconds: 4);

  // LSL builds a TCP connection per inlet/outlet pair, and an outlet drops
  // what it is given until a consumer is actually attached.
  @override
  Duration get warmup => const Duration(milliseconds: 1500);

  @override
  Duration get sendInterval => const Duration(milliseconds: 20);

  // Each test builds three full LSL sessions, whose isolates, outlets and
  // inlets do not all die synchronously with dispose().
  @override
  Duration get teardownSettle => const Duration(seconds: 5);

  @override
  String get sessionName => _sessionName;

  /// Findings from running this shared matrix over LSL. The in-memory and
  /// WebSocket transports satisfy the whole matrix; everything here is
  /// LSL-specific.
  @override
  // None. All five modes pass over LSL.
  //
  // They did not at first, and both causes were self-inflicted rather than
  // LSL limitations: createInletsForNodes excluded the local node (so
  // self-delivery never happened, breaking allNodes and
  // sendAllReceiveCoordinator), and it retried with short one-shot resolves
  // that each restarted the resolver from cold instead of using a continuous
  // one.
  @override
  Map<StreamParticipationMode, String> get skippedModes => const {};

  @override
  Future<void> setUp() async {
    // LSL resolution is machine-wide, so each run needs its own session name
    // or a concurrent run would be discovered as a peer. The scenario runner
    // additionally uniquifies node ids and stream names per test.
    _sessionName = uniqueSessionName('Participation');
  }

  @override
  Future<void> tearDown() async {}

  @override
  ITransportConfig transportConfigFor(int nodeIndex) =>
      LSLTransportConfig(coordinationFrequency: 50.0);
}

void main() {
  // Installs the process-global loopback LSL config. Must run before any node
  // is constructed; see the harness for why every node shares one config.
  useLoopbackLsl();

  runParticipationScenarios(_LslHarness());
}
