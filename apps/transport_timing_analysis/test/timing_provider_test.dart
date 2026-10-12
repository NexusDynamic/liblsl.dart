import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:timing_core/timing_core.dart';
import 'package:transport_timing_analysis/src/report_page.dart';
import 'package:transport_timing_analysis/src/timing_provider.dart';
import 'package:transport_timing_analysis/src/timing_session.dart';

/// The log of [device] in [runId]: it sent 100 samples and received the
/// other device's, 1 ms after they were sent.
Future<Uint8List> log(
  String runId,
  String device,
  String other, {
  int? repetition,
  String sendMode = 'sync',
}) async {
  final buffer = BytesSink();
  final writer = RunLogWriter(
    buffer,
    RunHeader(
      runId: runId,
      startedAt: DateTime.utc(2026, 10, 12),
      deviceId: device,
      deviceName: device.toLowerCase(),
      sourceId: device,
      test: 'latency',
      backend: 'lsl',
      sampleRate: 100,
      receiveMode: 'event',
      sendMode: sendMode,
      extra: {'repetition': ?repetition},
    ),
  );
  for (var seq = 1; seq <= 100; seq++) {
    writer
      ..sent(seq, seq * 0.01)
      ..received(
        other,
        seq,
        sourceClock: seq * 0.01,
        receivedClock: seq * 0.01 + 0.001,
        clockOffset: 0,
        uncertainty: 0.0002,
      );
  }
  await writer.close();
  return buffer.takeBytes();
}

PickedFile file(String name, Uint8List bytes) =>
    PickedFile(name, ByteSourceSpec.bytes(bytes, name: name));

AppState appWith(TimingProvider provider) => AppState(
  Preferences(),
  providers: [provider],
  config: const ViewerConfig(title: 'Test', heading: 'Test'),
);

void main() {
  test('one run opens with a tab for each sender', () async {
    final provider = TimingProvider();
    final app = appWith(provider);
    await app.openFiles([
      file('a.xdf', await log('run1', 'A', 'B')),
      file('b.xdf', await log('run1', 'B', 'A')),
    ]);
    expect(app.tabs.map((t) => t.title), ['a.xdf · b → a', 'b.xdf · a → b']);
    expect(app.openingTotal, 0);
    expect((await provider.report()).runs.single.pairs, hasLength(2));
    app.dispose();
  });

  test('many logs open for their report, with tabs on request', () async {
    final provider = TimingProvider();
    final app = appWith(provider);
    // Progress is counted over the files picked together.
    final totals = <int>{};
    app.addListener(() => totals.add(app.openingTotal));

    await app.openFiles([
      for (final (index, run) in ['r1', 'r2', 'r3'].indexed) ...[
        file('${run}_a.xdf', await log(run, 'A', 'B', repetition: index + 1)),
        file('${run}_b.xdf', await log(run, 'B', 'A', repetition: index + 1)),
      ],
      file('notes.xdf', Uint8List.fromList([1, 2, 3])),
    ]);
    expect(totals, containsAll([7, 0]));
    expect(app.error, contains('notes.xdf is not a transport_timing run log'));
    expect(app.sessions, hasLength(6));
    // In the order they were picked, though several open at once.
    expect(
      [for (final s in app.sessions) (s as TimingSession).name],
      ['r1_a.xdf', 'r1_b.xdf', 'r2_a.xdf', 'r2_b.xdf', 'r3_a.xdf', 'r3_b.xdf'],
    );
    expect(app.tabs, isEmpty);

    final report = await provider.report();
    expect(report.runs.map((r) => r.runId), ['r1', 'r2', 'r3']);
    expect(identical(await provider.report(), report), isTrue);
    expect(app.working, isEmpty);

    // A trace, asked for: one tab, named for its condition.
    final session = app.sessions[2] as TimingSession;
    session.show(0);
    expect(app.tabs.single.title, 'event · sync · rep 2 · b → a');

    // Closing the tab leaves the log open, and in the report.
    await app.closeTab(0);
    expect(app.tabs, isEmpty);
    expect(app.sessions, hasLength(6));
    expect(identical(await provider.report(), report), isTrue);

    // Closing a log does not.
    await app.closeSession(session);
    final after = await provider.report();
    expect(after, isNot(same(report)));
    expect(after.runs, hasLength(3));
    expect(after.runs[1].pairs.map((p) => '${p.from} → ${p.to}'), [
      'A → b',
    ], reason: 'only b\'s log of r2 is left, and a is known by its id');
    app.dispose();
  });

  testWidgets('the report narrows down, and opens and closes what it lists', (
    tester,
  ) async {
    final logs = (await tester.runAsync(
      () async => [
        for (final (run, send) in [('r1', 'sync'), ('r2', 'async')])
          for (final (device, other) in [('A', 'B'), ('B', 'A')])
            RunLog.parse(await log(run, device, other, sendMode: send)),
      ],
    ))!;
    final opened = <String>[];
    final closed = <Set<String>?>[];

    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReport(
              context,
              Future.value(analyse(logs)),
              actions: ReportActions(
                hasTrace: (run, pair) => true,
                openTrace: (run, pair) =>
                    opened.add('${run.runId} ${pair.from} → ${pair.to}'),
                closeRuns: (runIds) async {
                  closed.add(runIds);
                  return runIds == null ? null : analyse(logs.sublist(2));
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('4 of 4 rows'), findsOneWidget);
    expect(find.text('Run r1'), findsOneWidget);

    // By direction, then by how it was sent as well.
    await tester.tap(find.widgetWithText(FilterChip, 'a → b'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 4 rows'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'async'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 rows'), findsOneWidget);
    // What is left is what is selected.
    expect(find.text('Run r2'), findsOneWidget);
    expect(find.text('Latency, a → b'), findsOneWidget);

    await tester.tap(find.text('Close this run\'s logs'));
    await tester.pumpAndSettle();
    expect(closed, [
      {'r2'},
    ]);
    expect(find.text('2 of 2 rows'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.show_chart).first);
    await tester.pumpAndSettle();
    expect(opened, ['r2 b → a']);
    // The trace is behind the report, which has gone.
    expect(find.text('Timing report'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
