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

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seed = widget.config.seedColor;
    return ListenableBuilder(
      listenable: widget.prefs,
      builder: (context, _) => MaterialApp(
        title: widget.config.title,
        debugShowCheckedModeBanner: false,
        themeMode: widget.prefs.themeMode,
        theme: ThemeData(colorSchemeSeed: seed, visualDensity: _density),
        darkTheme: ThemeData(
          colorSchemeSeed: seed,
          brightness: Brightness.dark,
          visualDensity: _density,
        ),
        home: MainWindow(state: _state, initialFiles: widget.files),
      ),
    );
  }
}
