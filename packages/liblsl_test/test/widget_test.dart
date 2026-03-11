import 'package:flutter_test/flutter_test.dart';
import 'package:liblsl_test/main.dart';

/// This doesn't do much. See the integration test in integration_test/lsl_test.dart.
void main() {
  testWidgets('Liblsl native loads version', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LSLTestApp());

    // Verify that our counter starts at 0.
    //expect(find.text('Calculating answer...'), findsOneWidget);
    await tester.pumpAndSettle(Duration(seconds: 1));

    // Verify that our counter has incremented.
    expect(find.text('LSL Version 117'), findsOneWidget);
  });
}
