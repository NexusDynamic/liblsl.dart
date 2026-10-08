import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mode after [mode] in the order the toggle goes through: system,
/// light, dark.
ThemeMode nextThemeMode(ThemeMode mode) => switch (mode) {
  ThemeMode.system => ThemeMode.light,
  ThemeMode.light => ThemeMode.dark,
  ThemeMode.dark => ThemeMode.system,
};

/// The application's theme mode, remembered between launches.
///
/// It follows the system until the user chooses otherwise.
class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController([super.value = ThemeMode.system]);

  static const _key = 'theme_mode';

  /// A controller with the stored choice, or [ThemeMode.system] without one.
  static Future<ThemeModeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = ThemeMode.values.asNameMap()[prefs.getString(_key)];
    return ThemeModeController(stored ?? ThemeMode.system);
  }

  /// Sets and stores [mode].
  Future<void> set(ThemeMode mode) async {
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  /// Moves to the next mode; see [nextThemeMode].
  Future<void> toggle() => set(nextThemeMode(value));
}

/// A button that shows the theme [mode] and asks for the next one when
/// pressed.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: switch (mode) {
      ThemeMode.system => 'Theme: system',
      ThemeMode.light => 'Theme: light',
      ThemeMode.dark => 'Theme: dark',
    },
    onPressed: () => onChanged(nextThemeMode(mode)),
    icon: Icon(switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    }),
  );
}

/// Makes a [ThemeModeController] available to the widgets below, so that a
/// [ThemeModeToggle] can be placed in any app bar.
class ThemeModeScope extends InheritedNotifier<ThemeModeController> {
  const ThemeModeScope({
    super.key,
    required ThemeModeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeModeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeModeScope>()!.notifier!;
}

/// The [ThemeModeButton] of the enclosing [ThemeModeScope].
class ThemeModeToggle extends StatelessWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeModeScope.of(context);
    return ThemeModeButton(mode: controller.value, onChanged: controller.set);
  }
}
