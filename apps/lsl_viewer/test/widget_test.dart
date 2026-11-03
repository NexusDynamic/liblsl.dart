import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lsl_viewer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signal_viewer/signal_viewer.dart';

void main() {
  testWidgets('the welcome page offers LSL streams and XDF files', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await tester.runAsync(prefs.load);
    await tester.pumpWidget(
      SignalViewerApp(
        prefs: prefs,
        config: lslViewerConfig,
        providers: lslViewerProviders(),
      ),
    );
    await tester.pump();
    expect(find.text('LSL Viewer'), findsOneWidget);
    expect(find.text('Open recording…'), findsWidgets);
    // XDF recordings, and the Cyton's SD card recordings.
    expect(find.textContaining('.xdf, .txt files'), findsOneWidget);
    expect(find.text('View an LSL stream…'), findsOneWidget);
    // No device menu: that is hyprview's.
    expect(find.text('Device'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a synthetic stream opens in tabs from the welcome page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await tester.runAsync(prefs.load);
    await tester.pumpWidget(
      SignalViewerApp(
        prefs: prefs,
        config: lslViewerConfig,
        providers: lslViewerProviders(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Show a synthetic signal…'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic stream'), findsOneWidget);
    await tester.tap(find.text('Markers'));
    await tester.pump();
    await tester.tap(find.text('Show'));
    // Real time passes for the generator's clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Synthetic 1'), findsWidgets);
    expect(find.textContaining('Synthetic 1 markers'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
