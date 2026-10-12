import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timing_core/timing_core.dart';
import 'package:transport_timing_analysis/src/report_page.dart';

void main() {
  testWidgets('the report shows each pair and its distribution', (
    tester,
  ) async {
    final buffer = BytesSink();
    final writer = RunLogWriter(
      buffer,
      RunHeader(
        runId: 'run1',
        startedAt: DateTime.utc(2026, 10, 6),
        deviceId: 'A',
        deviceName: 'a',
        sourceId: 'A',
        test: 'latency',
        backend: 'lsl',
        sampleRate: 100,
        receiveMode: 'polled',
        pollInterval: 0.005,
      ),
    );
    for (var seq = 1; seq <= 200; seq++) {
      writer.received(
        'B',
        seq,
        sourceClock: seq * 0.01,
        receivedClock: seq * 0.01 + 0.001 + (seq % 7) * 0.0002,
        clockOffset: 0,
        uncertainty: 0.0002,
      );
    }
    await tester.runAsync(writer.close);
    final report = analyse([RunLog.parse(buffer.takeBytes())]);

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReport(context, Future.value(report)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Run run1'), findsOneWidget);
    expect(find.text('B → a'), findsOneWidget);
    expect(find.text('polled'), findsOneWidget);
    expect(
      find.text('2.500'),
      findsOneWidget,
      reason: 'half the poll interval',
    );
    expect(find.textContaining('Median'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated runs are set side by side, and warnings shown', (
    tester,
  ) async {
    Future<RunLog> log(
      String runId,
      String device,
      String other, {
      required double latency,
      bool silent = false,
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
          sendMode: 'sync',
        ),
      );
      for (var seq = 1; seq <= 200; seq++) {
        writer.sent(seq, seq * 0.01);
        if (silent) continue;
        writer.received(
          other,
          seq,
          sourceClock: seq * 0.01,
          receivedClock: seq * 0.01 + latency,
          clockOffset: 0,
          uncertainty: 0.0002,
        );
      }
      await writer.close();
      return RunLog.parse(buffer.takeBytes());
    }

    final logs = (await tester.runAsync(
      () async => [
        await log('run1', 'A', 'B', latency: 0.001),
        await log('run1', 'B', 'A', latency: 0.001),
        await log('run2', 'A', 'B', latency: 0.003),
        await log('run2', 'B', 'A', latency: 0.003, silent: true),
      ],
    ))!;
    final report = analyse(logs);

    tester.view.physicalSize = const Size(2000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReport(context, Future.value(report)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // b -> a ran twice, at 1 ms and at 3 ms.
    expect(find.text('Repeated runs'), findsOneWidget);
    expect(find.text('2.000'), findsWidgets, reason: 'median of the medians');
    expect(
      find.text('Run run2: b received nothing from a, which sent 200.'),
      findsOneWidget,
    );
    expect(find.textContaining('a ↔ b: 1.000 ms p50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
