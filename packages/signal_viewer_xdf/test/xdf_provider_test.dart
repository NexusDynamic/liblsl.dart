import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_xdf/signal_viewer_xdf.dart';

/// Pump until [done] or give up.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('an .xdf file opens with a tab per stream', (tester) async {
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(
      Preferences(),
      providers: [XdfProvider()],
      config: const ViewerConfig(title: 'Test', heading: 'Test viewer'),
    );
    await tester.pumpWidget(MaterialApp(home: MainWindow(state: state)));
    expect(find.text('Test viewer'), findsOneWidget);
    expect(find.textContaining('.xdf files'), findsOneWidget);

    await tester.runAsync(
      () => state.openFiles([
        fileAtPath('../xdf/test/fixtures/clock_resets.xdf')!,
      ]),
    );
    final session = state.sessions.single as XdfSession;
    await tester.runAsync(() => session.file.indexed);
    await _settle(
      tester,
      () =>
          state.tabs.length == 2 &&
          state.tabs.every((t) => t.controller.settled),
    );
    expect(state.tabs.map((t) => t.title), [
      'clock_resets.xdf · MyMarkerStream',
      'clock_resets.xdf · BioSemi',
    ]);
    expect(state.tabs.first.group.info.kind, Kind.event);
    final eeg = state.tabs.last;
    expect(eeg.group.info.kind, Kind.eeg);
    expect(eeg.group.info.rate, 100);

    state.current = 1;
    await _settle(tester, () => eeg.controller.data != null);
    expect(eeg.controller.data, isNotNull);

    state.current = 0;
    await tester.pump();
    final markers = state.tabs.first.controller.events();
    expect(markers.length, 175);
    expect(markers.markers, isTrue);

    await tester.runAsync(() => state.closeSession(session));
    expect(state.tabs, isEmpty);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
}
