import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_branding/nexus_branding.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('follows the system until a mode is chosen', () async {
    final controller = await ThemeModeController.load();
    expect(controller.value, ThemeMode.system);
  });

  test('goes through system, light and dark in order', () async {
    final controller = await ThemeModeController.load();
    await controller.toggle();
    expect(controller.value, ThemeMode.light);
    await controller.toggle();
    expect(controller.value, ThemeMode.dark);
    await controller.toggle();
    expect(controller.value, ThemeMode.system);
  });

  test('a chosen mode is restored', () async {
    await (await ThemeModeController.load()).set(ThemeMode.dark);
    expect((await ThemeModeController.load()).value, ThemeMode.dark);
  });

  test('an unknown stored value falls back to the system', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
    expect((await ThemeModeController.load()).value, ThemeMode.system);
  });

  testWidgets('the button shows the mode and asks for the next one', (
    tester,
  ) async {
    final controller = ThemeModeController();
    await tester.pumpWidget(
      ThemeModeScope(
        controller: controller,
        child: const MaterialApp(home: Scaffold(body: ThemeModeToggle())),
      ),
    );
    expect(find.byIcon(Icons.brightness_auto), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(controller.value, ThemeMode.light);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
  });

  test('the themes use the brand colours', () {
    expect(nexusLightTheme().colorScheme.brightness, Brightness.light);
    expect(nexusLightTheme().colorScheme.primary, NexusColors.brand700);
    expect(nexusDarkTheme().colorScheme.brightness, Brightness.dark);
    expect(nexusDarkTheme().colorScheme.surface, NexusColors.zinc950);
  });
}
