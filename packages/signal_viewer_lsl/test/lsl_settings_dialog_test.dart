import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_lsl/signal_viewer_lsl.dart';

void main() {
  testWidgets('receiving as samples arrive is on, and can be turned off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = LslProvider();
    final state = AppState(
      Preferences(),
      providers: [provider],
      config: const ViewerConfig(title: 'Test', heading: 'Test'),
    );
    expect(state.prefs.lsl.inlet.eventDriven, isTrue);
    await tester.pumpWidget(MaterialApp(home: MainWindow(state: state)));
    final context = tester.element(find.byType(MainWindow));
    // ignore: unawaited_futures
    showLslSettings(context, provider);
    await tester.pumpAndSettle();

    final arriving = find.widgetWithText(
      SwitchListTile,
      'Receive as samples arrive',
    );
    expect(tester.widget<SwitchListTile>(arriving).value, isTrue);
    // The interval is then only for streams that cannot.
    expect(find.textContaining('over a bridge'), findsOneWidget);

    await tester.tap(arriving);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(arriving).value, isFalse);
    expect(find.text('How often new samples are picked up.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => state.dispose());
    await tester.pump(const Duration(seconds: 2));
  });
}
