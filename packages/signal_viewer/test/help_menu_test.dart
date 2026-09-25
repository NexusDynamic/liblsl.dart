import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phones show keyboard help only once a keyboard is used', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(
      Preferences(),
      providers: const [],
      config: const ViewerConfig(title: 'Test', heading: 'Test'),
    );
    await tester.pumpWidget(MaterialApp(home: MainWindow(state: state)));
    await _openMenu(tester);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Keyboard and mouse'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await _openMenu(tester);
    expect(find.text('Keyboard and mouse'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
