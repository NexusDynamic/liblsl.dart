/// Two sessions in this process over real LSL on the loopback interface:
/// a coordinator-stream run, then raw LSL runs in each receive mode.
///
/// Needs liblsl and working multicast on loopback, so it is tagged `lsl`
/// and left out of the default test run:
///
///     flutter test --tags lsl
///
/// It prints each report; the numbers are this machine's.
@Tags(['lsl'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:timing_core/timing_core.dart';
import 'package:transport_timing/src/log_store.dart';
import 'package:transport_timing/src/settings.dart';
import 'package:transport_timing/src/timing_session.dart';

void main() {
  late Directory directory;
  final sessions = <TimingSession>[];

  setUp(() {
    // TT_LOG_DIR keeps the logs, e.g. to open in the analysis app.
    final keep = Platform.environment['TT_LOG_DIR'];
    directory = keep == null
        ? Directory.systemTemp.createTempSync('transport_timing_lsl')
        : (Directory(keep)..createSync(recursive: true));
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      await session.leave();
    }
    sessions.clear();
    if (Platform.environment['TT_LOG_DIR'] == null) {
      directory.deleteSync(recursive: true);
    }
  });

  Future<TimingSession> join(
    String name,
    String sessionName, {
    bool eventDriven = false,
  }) async {
    final session = TimingSession(
      settings: AppSettings(deviceName: name, sessionName: sessionName),
      transportConfig: LSLTransportConfig(
        eventDrivenInlets: eventDriven,
        lslApiConfig: LSLApiConfig(
          ipv6: IPv6Mode.disable,
          resolveScope: ResolveScope.link,
          listenAddress: '127.0.0.1',
          addressesOverride: ['224.0.0.184'],
          knownPeers: ['127.0.0.1'],
          logLevel: -2,
          portRange: 128,
        ),
      ),
      store: LogStore(directory: () async => directory),
      heartbeatInterval: const Duration(seconds: 1),
      discoveryInterval: const Duration(seconds: 1),
      nodeTimeout: const Duration(seconds: 10),
    );
    sessions.add(session);
    expect(await session.connect(), isTrue, reason: session.notice);
    return session;
  }

  Future<void> waitFor(bool Function() condition, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!condition()) {
      if (!DateTime.now().isBefore(deadline)) {
        fail(
          'timed out: $what\n${[
            for (final s in sessions) '${s.settings.deviceName}: ${[for (final r in s.results.value) r.config.runId]}',
          ].join('\n')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('stream and raw LSL runs on loopback', () async {
    final name = 'tt_${DateTime.now().millisecondsSinceEpoch}';
    final a = await join('a', name);
    final b = await join('b', name);
    await waitFor(() => a.roster.value.length == 2, 'roster of 2');
    final coordinator = a.isCoordinator.value ? a : b;

    final configs = [
      const RunConfig(runId: 'stream', sampleRate: 500, durationSeconds: 3),
      for (final mode in ReceiveMode.values)
        RunConfig(
          runId: 'raw-${mode.key}',
          path: DataPath.rawLsl,
          sampleRate: 500,
          durationSeconds: 3,
          receiveMode: mode,
          pollIntervalMicros: 5000,
        ),
      const RunConfig(
        runId: 'raw-blocking-send',
        path: DataPath.rawLsl,
        sampleRate: 500,
        durationSeconds: 3,
        sendMode: SendMode.syncBlocking,
      ),
      const RunConfig(
        runId: 'raw-async-send',
        path: DataPath.rawLsl,
        sampleRate: 500,
        durationSeconds: 3,
        sendMode: SendMode.async,
      ),
    ];
    await coordinator.startRuns(configs);
    for (final session in [a, b]) {
      await waitFor(
        () =>
            session.results.value.length == configs.length &&
            session.run.value == null,
        'results on ${session.settings.deviceName}',
      );
    }

    final report = analyse([
      for (final session in [a, b])
        for (final result in session.results.value)
          RunLog.parse(File(result.path).readAsLinesSync()),
    ]);
    // ignore: avoid_print
    print(formatReport(report));

    expect(report.runs, hasLength(configs.length));
    for (final run in report.runs) {
      expect(run.senders, hasLength(2), reason: run.runId);
      for (final pair in run.pairs) {
        final where = '${run.runId} ${pair.from} -> ${pair.to}';
        expect(pair.lossRate, lessThan(0.01), reason: where);
        expect(pair.latency, isNotNull, reason: where);
        expect(
          pair.latency!.p50,
          inInclusiveRange(-0.001, 0.05),
          reason: where,
        );
      }
    }
    // Raw runs include each device's own stream.
    final raw = report.runs.firstWhere((r) => r.runId == 'raw-event');
    expect(raw.pairs, hasLength(4));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a stream run with event-driven inlets has no polling delay', () async {
    final name = 'tt_event_${DateTime.now().millisecondsSinceEpoch}';
    final a = await join('a', name, eventDriven: true);
    final b = await join('b', name, eventDriven: true);
    await waitFor(() => a.roster.value.length == 2, 'roster of 2');
    final coordinator = a.isCoordinator.value ? a : b;

    await coordinator.startRuns([
      const RunConfig(runId: 'event', sampleRate: 100, durationSeconds: 3),
    ]);
    for (final session in [a, b]) {
      await waitFor(
        () => session.results.value.length == 1 && session.run.value == null,
        'result on ${session.settings.deviceName}',
      );
    }
    final report = analyse([
      for (final session in [a, b])
        RunLog.parse(File(session.results.value.single.path).readAsLinesSync()),
    ]);
    // ignore: avoid_print
    print(formatReport(report));
    for (final pair in report.runs.single.pairs) {
      expect(pair.receiveMode, 'event');
      expect(pair.pollInterval, isNull);
      // Polled at this rate, the median would be near 5 ms.
      expect(
        pair.latency!.p50,
        lessThan(0.003),
        reason: '${pair.from} -> ${pair.to}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
