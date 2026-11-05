import 'package:flutter/material.dart';

import 'settings/prefs.dart';
import 'ui/app_state.dart';
import 'ui/main_window.dart';
import 'ui/widgets/widgets.dart';
import 'viewer/source.dart';

/// Load the preferences, let [providers] prepare, and run the viewer.
/// [args] are files to open (desktop); arguments starting with `-` are
/// ignored.
Future<void> runSignalViewer(
  List<String> args, {
  required ViewerConfig config,
  required List<SourceProvider> providers,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = Preferences(
    extraKeys: [for (final p in providers) ...p.prefsKeys],
  );
  await prefs.load();
  for (final p in providers) {
    await p.prepare(prefs);
  }
  runApp(
    SignalViewerApp(
      prefs: prefs,
      config: config,
      providers: providers,
      files: args.where((f) => !f.startsWith('-')).toList(),
    ),
  );
}

/// Compact controls with a mouse; full-size touch targets on phones and
/// tablets.
VisualDensity get _density =>
    touchPlatform ? VisualDensity.standard : VisualDensity.compact;

/// The viewer: a [MainWindow] over an [AppState] with [providers].
class SignalViewerApp extends StatefulWidget {
  final Preferences prefs;
  final ViewerConfig config;
  final List<SourceProvider> providers;
  final List<String> files;

  const SignalViewerApp({
    super.key,
    required this.prefs,
    required this.config,
    required this.providers,
    this.files = const [],
  });

  @override
  State<SignalViewerApp> createState() => _SignalViewerAppState();
}

class _SignalViewerAppState extends State<SignalViewerApp> {
  late final AppState _state = AppState(
    widget.prefs,
    providers: widget.providers,
    config: widget.config,
  );

  // Built once: seeded themes are costly, and the same instances let
  // MaterialApp skip a theme change.
  late final ThemeData _theme =
      widget.config.theme?.copyWith(visualDensity: _density) ??
      ThemeData(
        colorSchemeSeed: widget.config.seedColor,
        visualDensity: _density,
      );
  late final ThemeData _darkTheme =
      widget.config.darkTheme?.copyWith(visualDensity: _density) ??
      ThemeData(
        colorSchemeSeed: widget.config.seedColor,
        brightness: Brightness.dark,
        visualDensity: _density,
      );
  late final Widget _home = MainWindow(
    state: _state,
    initialFiles: widget.files,
  );
  late ThemeMode _themeMode = widget.prefs.themeMode;

  @override
  void initState() {
    super.initState();
    widget.prefs.addListener(_prefsChanged);
  }

  /// Only the theme mode matters here; [MainWindow] follows the rest.
  void _prefsChanged() {
    if (widget.prefs.themeMode != _themeMode) {
      setState(() => _themeMode = widget.prefs.themeMode);
    }
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_prefsChanged);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: widget.config.title,
    debugShowCheckedModeBanner: false,
    themeMode: _themeMode,
    theme: _theme,
    darkTheme: _darkTheme,
    home: _home,
  );
}
