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
}
