import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_lsl/signal_viewer_lsl.dart';

void main() {
  testWidgets('the share dialog starts a relay and shows how to connect', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = LslProvider();
    final state = AppState(
      Preferences(),
      providers: [provider],
      config: const ViewerConfig(title: 'Test', heading: 'Test'),
    );
    await tester.pumpWidget(MaterialApp(home: MainWindow(state: state)));
    final context = tester.element(find.byType(MainWindow));
    // ignore: unawaited_futures
    showLslShare(context, provider);
    await tester.pumpAndSettle();
    expect(find.text('Share or relay LSL streams'), findsOneWidget);

    await tester.tap(find.text('Relay only'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Port'), '0');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Relay'));
      for (var i = 0; i < 50 && provider.bridgeServer == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // Addresses are looked up in the background.
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    final server = provider.bridgeServer!;
    expect(server.acceptsPublish, isTrue);
    expect(server.localOutlets, isFalse);
    expect(find.text('Relaying streams between clients'), findsOneWidget);
    expect(find.text('ws://127.0.0.1:${server.port}'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(provider.stopSharing);
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Relay'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => state.dispose());
    await tester.pump(const Duration(seconds: 2));
  });
}
