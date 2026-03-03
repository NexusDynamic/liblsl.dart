import 'package:flutter/material.dart' show Key, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liblsl_test/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Ensure native bindings operate correctly', () {
    testWidgets('Wait for the version to load', (tester) async {
      await tester.pumpWidget(const LSLTestApp());
      // _setupLSL is synchronous; one pump is enough, but give a little margin.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('LSL Version 117'), findsOneWidget);
    });

    testWidgets('Start LSL stream and sample via app UI', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const LSLTestApp());
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('LSL Version 117'), findsOneWidget);

      // ── Producer ──────────────────────────────────────────────────────────
      // Default settings: 5 Hz, 5 seconds, 2 channels.
      await tester.tap(find.byKey(const Key('start_streaming')));

      // Let the outlet register on the network before searching.
      // Note: pumpAndSettle cannot be used here because the elapsed-time
      // timer fires every second and keeps the frame queue non-empty.
      await tester.pump(const Duration(milliseconds: 500));

      // ── Consumer: find streams ─────────────────────────────────────────
      await tester.tap(find.byKey(const Key('check_streams')));

      // resolveStreams uses waitTime: 2.0 s internally; allow 3 s of margin.
      await tester.pump(const Duration(seconds: 3));

      // Start Sampling button only appears once _foundStreams is non-empty.
      expect(find.byKey(const Key('start_sampling')), findsOneWidget);

      // ── Consumer: sample ──────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('start_sampling')));

      // Give the sampling timer at least one pull cycle (fires every 100 ms @ 10Hz).
      await tester.pump(const Duration(milliseconds: 500));

      // sample_data widget is always present; verify it holds real data.
      final sampleFinder = find.byKey(const Key('sample_data'));
      expect(sampleFinder, findsOneWidget);
      final sampleText = tester.widget<Text>(sampleFinder);
      expect(sampleText.data, startsWith('Sample:'));

      // ── Teardown ───────────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('stop_sampling')));
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
