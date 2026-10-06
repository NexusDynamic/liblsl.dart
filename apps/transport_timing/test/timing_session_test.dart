/// Three whole sessions over one [InMemoryBus] run a latency test and each
/// writes a log the analysis reads: the path from "start run" to a report,
/// with no network and no native code.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peer_coordinator/in_memory.dart';
import 'package:timing_core/timing_core.dart';
import 'package:transport_timing/src/log_store.dart';
import 'package:transport_timing/src/settings.dart';
import 'package:transport_timing/src/stream_run.dart';
import 'package:transport_timing/src/timing_session.dart';

void main() {
  late InMemoryBus bus;
  late Directory directory;
  late List<TimingSession> sessions;

  setUp(() {
    bus = InMemoryBus();
    directory = Directory.systemTemp.createTempSync('transport_timing_test');
    sessions = [];
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      try {
        await session.leave();
      } catch (_) {
        // Teardown must not mask the assertion that actually failed.
      }
    }
    bus.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<TimingSession> join(String name) async {
    final session = TimingSession(
      settings: AppSettings(deviceName: name, sessionName: 'test'),
      transportConfig: InMemoryTransportConfig(bus: bus),
      backendKey: 'memory',
      store: LogStore(directory: () async => directory),
      heartbeatInterval: const Duration(milliseconds: 50),
      discoveryInterval: const Duration(milliseconds: 25),
      nodeTimeout: const Duration(milliseconds: 400),
    );
    sessions.add(session);
    final joined = await session.connect(
      timeout: const Duration(milliseconds: 500),
    );
    expect(joined, isTrue, reason: session.notice);
    return session;
  }

  Future<void> waitFor(bool Function() condition, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!condition()) {
      if (!DateTime.now().isBefore(deadline)) fail('timed out: $what');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('nodeUIdOf reads both source id forms', () {
    expect(nodeUIdOf('abc'), 'abc');
    expect(nodeUIdOf('tt_run//participant//abc//ipad'), 'abc');
  });

  test('a run config survives the announcement', () {
    const config = RunConfig(
      runId: 'r',
      path: DataPath.rawLsl,
      sampleRate: 250,
      channels: 8,
      receiveMode: ReceiveMode.polled,
      pollIntervalMicros: 2000,
      sendMode: SendMode.syncBlocking,
      pushthrough: false,
    );
    expect(RunConfig.fromMap(config.toMap()).toMap(), config.toMap());
    expect(RunConfig.rawLslSweep(config), hasLength(9));
  });

  test('every device logs a run the analysis can read', () async {
    final a = await join('a');
    final b = await join('b');
    final c = await join('c');
    await waitFor(() => a.roster.value.length == 3, 'roster of 3');
    expect(a.isCoordinator.value, isTrue);

    const config = RunConfig(
      runId: 'run1',
      sampleRate: 100,
      channels: 4,
      durationSeconds: 1,
    );
    await a.startRuns([config]);
    for (final session in [a, b, c]) {
      await waitFor(
        () => session.results.value.length == 1 && session.run.value == null,
        'result on ${session.settings.deviceName}',
      );
    }

    final logs = [
      for (final session in [a, b, c])
        RunLog.parse(File(session.results.value.single.path).readAsBytesSync()),
    ];
    for (final log in logs) {
      expect(log.header.runId, 'run1');
      expect(log.header.backend, 'memory');
      expect(log.header.receiveMode, 'event');
      expect(log.header.channels, 4);
      expect(log.sent.length, 100);
      expect(log.events.map((e) => e.name), ['started', 'stopped']);
    }

    final run = analyse(logs).runs.single;
    expect(run.senders.map((s) => s.sent), [100, 100, 100]);
    // On the bus each device hears all three, itself included, and with no
    // sender reported they arrive as one source.
    for (final pair in run.pairs) {
      expect(pair.received, 300, reason: '${pair.from} -> ${pair.to}');
    }
    expect(a.results.value.single.report, contains('Run run1'));
  });
}
