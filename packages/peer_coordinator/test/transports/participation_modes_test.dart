/// Runs the participation-mode scenarios against every transport in this
/// package.
///
/// Both backends must agree: the mode is a property of the coordination
/// layer, not of how bytes move, so any divergence here is a transport bug.
@Tags(['integration'])
library;

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:test/test.dart';

import 'package:peer_coordinator/testing.dart';

class _InMemoryHarness extends ParticipationHarness {
  InMemoryBus? _bus;

  @override
  String get name => 'in-memory';

  @override
  Duration get joinTimeout => const Duration(milliseconds: 500);

  @override
  Duration get settleTimeout => const Duration(milliseconds: 300);

  @override
  Future<void> setUp() async => _bus = InMemoryBus();

  @override
  Future<void> tearDown() async {
    _bus?.dispose();
    _bus = null;
  }

  @override
  ITransportConfig transportConfigFor(int nodeIndex) =>
      InMemoryTransportConfig(bus: _bus!);
}

class _WebSocketHarness extends ParticipationHarness {
  CoordinationHub? _hub;

  @override
  String get name => 'websocket';

  @override
  Duration get joinTimeout => const Duration(seconds: 2);

  @override
  Duration get settleTimeout => const Duration(seconds: 1);

  @override
  Future<void> setUp() async => _hub = await CoordinationHub.serve();

  @override
  Future<void> tearDown() async {
    await _hub?.close();
    _hub = null;
  }

  @override
  ITransportConfig transportConfigFor(int nodeIndex) =>
      WebSocketTransportConfig(
        hubUri: Uri.parse('ws://127.0.0.1:${_hub!.port}'),
      );
}

void main() {
  runParticipationScenarios(_InMemoryHarness());
  runParticipationScenarios(_WebSocketHarness());
}
