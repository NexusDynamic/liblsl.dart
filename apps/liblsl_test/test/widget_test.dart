import 'package:flutter_test/flutter_test.dart';
import 'package:liblsl_test/main.dart';

/// This doesn't do much. See the integration test in integration_test/lsl_test.dart.
void main() {
  testWidgets('Liblsl native loads version', (WidgetTester tester) async {
    await tester.pumpWidget(const LSLTestApp());

    await tester.pumpAndSettle(Duration(seconds: 1));

    expect(find.text('LSL Version 117'), findsOneWidget);
  });
}
