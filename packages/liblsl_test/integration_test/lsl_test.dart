import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liblsl_test/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Ensure native bindings operate correctly', () {
    testWidgets('Wait for the version to load', (tester) async {
      // Load app widget.
      await tester.pumpWidget(const MyApp());

      // Verify the counter starts at 0.
      expect(find.text('Calculating answer...'), findsOneWidget);

      // Trigger a frame, wait 1 second, the default of 100ms is too short.
      await tester.pumpAndSettle(Duration(seconds: 1));

      // Verify the counter increments by 1.
      expect(find.text('LSL Version 116'), findsOneWidget);
    });
  });
}
