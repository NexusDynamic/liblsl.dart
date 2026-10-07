/// Two sessions over a real WebSocket hub on loopback run a latency test:
/// the relay backend end to end, and that its clock estimates reach the log.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:timing_core/timing_core.dart';
import 'package:transport_timing/src/log_store.dart';
import 'package:transport_timing/src/settings.dart';
import 'package:transport_timing/src/timing_session.dart';

void main() {
  late Directory directory;
  late CoordinationHub hub;
  late HubCredentials credentials;
  final sessions = <TimingSession>[];

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('transport_timing_ws');
    credentials = HubCredentials(session: 'ws_test', secret: 'test-secret');
    hub = await CoordinationHub.serve(credentials: credentials);
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      await session.leave();
    }
    sessions.clear();
    await hub.close();
    directory.deleteSync(recursive: true);
  });

  Future<TimingSession> join(String name) async {
    final session = TimingSession(
      settings: AppSettings(deviceName: name, sessionName: 'ws_test'),
      transportConfig: WebSocketTransportConfig(
        hubUri: hub.uri,
        credentials: credentials,
      ),
      backendKey: Backend.websocket.key,
      store: LogStore(directory: () async => directory),
      heartbeatInterval: const Duration(milliseconds: 250),
      discoveryInterval: const Duration(milliseconds: 100),
      nodeTimeout: const Duration(seconds: 3),
    );
    sessions.add(session);
    expect(await session.connect(), isTrue, reason: session.notice);
    return session;
  }

  Future<void> waitFor(bool Function() condition, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!condition()) {
      if (!DateTime.now().isBefore(deadline)) fail('timed out: $what');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a run over the hub is timed, with its clock estimates', () async {
    final a = await join('a');
    final b = await join('b');
    await waitFor(() => a.roster.value.length == 2, 'roster of 2');
    final coordinator = a.isCoordinator.value ? a : b;

    await coordinator.startRuns([
      const RunConfig(runId: 'ws', sampleRate: 100, durationSeconds: 8),
    ]);
    for (final session in [a, b]) {
      await waitFor(
        () => session.results.value.length == 1 && session.run.value == null,
        'result on ${session.settings.deviceName}',
      );
    }

    final logs = [
      for (final session in [a, b])
        RunLog.parse(File(session.results.value.single.path).readAsBytesSync()),
    ];
    final report = analyse(logs);
    // ignore: avoid_print
    print(formatReport(report));

    for (final log in logs) {
      expect(log.header.backend, 'websocket');
      expect(log.header.receiveMode, 'event');
      expect(log.header.pollInterval, isNull);
    }
    for (final own in report.runs.single.pairs.where((p) => p.loopback)) {
      expect(own.untimed, 0, reason: 'a node needs no offset to itself');
      expect(own.latency!.p50, inInclusiveRange(0, 0.05));
    }
    final between = report.runs.single.pairs.where((p) => !p.loopback).toList();
    expect(between, hasLength(2));
    for (final pair in between) {
      final where = '${pair.from} -> ${pair.to}';
      expect(pair.lossRate, lessThan(0.01), reason: where);
      expect(pair.latency, isNotNull, reason: where);
      expect(pair.latency!.p50, inInclusiveRange(-0.005, 0.05), reason: where);
      expect(pair.clock, isNotNull, reason: where);
    }
    // The estimates themselves are in the log, not inferred from samples.
    final other = {for (final log in logs) log.header.sourceId};
    for (final log in logs) {
      final syncs = log.syncs.entries.where((e) => other.contains(e.key));
      expect(syncs, isNotEmpty, reason: log.header.deviceName);
      expect(syncs.first.value.remoteTime.first, isNot(isNaN));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
