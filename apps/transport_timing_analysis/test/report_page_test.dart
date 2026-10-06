import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timing_core/timing_core.dart';
import 'package:transport_timing_analysis/src/report_page.dart';

void main() {
  testWidgets('the report shows each pair and its distribution', (
    tester,
  ) async {
    final buffer = StringBuffer();
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
    final report = analyse([
      RunLog.parse(const LineSplitter().convert(buffer.toString())),
    ]);

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReport(context, report),
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
}
