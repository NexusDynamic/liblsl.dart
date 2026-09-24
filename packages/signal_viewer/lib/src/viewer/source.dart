import 'package:flutter/widgets.dart';

import '../model/stream_info.dart';
import '../platform/files.dart';
import '../sources/stream_source.dart';
import '../settings/prefs.dart';
import '../ui/app_state.dart';

/// One open source of streams: a recording, a live device, an LSL inlet.
///
/// Its [streams] are what the source setup (kinds, tab names, channel
/// names) applies to, by [StreamInfo.key]. Streams of a [groupable] session
/// share a clock, so streams with the same tab name and rate are merged
/// into one tab; others get a tab each.
abstract class SourceSession extends ChangeNotifier {
  /// Start of its tab titles, e.g. the file name, `HS` or `LSL`.
  String get label;

  /// End of its tab titles, e.g. ` (stopped)`.
  String get titleSuffix => '';

  /// Tooltip of its tabs, e.g. the file's path.
  String get tooltip;

  /// A one-line description for the status bar.
  String describe();

  /// The streams it has now (it may gain more, e.g. while indexing).
  List<StreamInfo> get streams;

  /// Whether its streams share a clock and can be merged into one tab.
  bool get groupable;

  /// The data behind a tab showing [info] (a stream, or several merged).
  StreamSource sourceFor(StreamInfo info);

  /// Identifies the session in settings remembered while the app runs,
  /// e.g. `file:<name>`.
  String get rememberKey;

  /// Progress (0-1) of indexing, while it runs.
  double? get progress => null;

  /// What its streams are called in the names of merged tabs, e.g. `ports`
  /// in "EEG · ports 0–3".
  String get memberNoun => 'streams';

  /// Whether it is a recording that can be played back as live streams
  /// (e.g. over LSL) through [sourceFor].
  bool get replayable => false;

  /// Whether event channels of [info] can be decoded as Manchester
  /// triggers (not for streams whose values are text).
  bool decodable(StreamInfo info) => true;

  bool get closed;

  Future<void> close();
}

/// An entry in a menu of the main window: the menu bar on wide screens,
/// the app bar's menu on narrow ones (which leaves out disabled entries).
class ViewerAction {
  /// The menu it belongs to, e.g. `Device` or `LSL`.
  final String menu;
  final String label;

  /// The label in the app bar's menu, where the menu's name is not shown.
  final String? narrowLabel;

  /// Null when disabled.
  final VoidCallback? onPressed;

  /// Whether it is checked, for toggles; null otherwise.
  final bool? checked;
  final IconData? icon;
  final MenuSerializableShortcut? shortcut;

  /// Position within its menu (lower first); a divider separates it from
  /// the previous entry if [divider].
  final int order;
  final bool divider;

  /// Whether it is only in the menu bar (wide screens).
  final bool wideOnly;

  const ViewerAction(
    this.menu,
    this.label, {
    this.narrowLabel,
    this.onPressed,
    this.checked,
    this.icon,
    this.shortcut,
    this.order = 0,
    this.divider = false,
    this.wideOnly = false,
  });
}

/// Something that opens [SourceSession]s: a file format, a device, a
/// network protocol. It adds its menus, toolbar, welcome screen and status
/// bar items to the main window; the window rebuilds when it notifies.
abstract class SourceProvider extends ChangeNotifier {
  late final AppState app;

  /// Keys (`group.name`) of the settings it keeps in [Preferences.extra].
  List<String> get prefsKeys => const [];

  /// Called once the preferences are loaded, before the app starts (e.g. to
  /// configure a library that must be set up first).
  Future<void> prepare(Preferences prefs) async {}

  /// Called once, when the app starts.
  void attach(AppState app) => this.app = app;

  /// Extensions of the files it opens, lower case without the dot.
  List<String> get fileExtensions => const [];

  /// Whether it opens [file].
  bool opens(PickedFile file) {
    final name = file.name.toLowerCase();
    return fileExtensions.any((e) => name.endsWith('.$e'));
  }

  /// Open a file with one of [fileExtensions].
  Future<SourceSession> openFile(PickedFile file) =>
      throw UnsupportedError('No files');

  /// Why files cannot be opened now (e.g. a device is streaming), or null.
  String? get blocksFiles => null;

  /// Menu entries.
  List<ViewerAction> actions(BuildContext context) => const [];

  /// Items for the toolbar (wide screens), before the Open button.
  List<Widget> toolbarLeading(BuildContext context) => const [];

  /// Items for the toolbar (wide screens), after the Open button.
  List<Widget> toolbar(BuildContext context) => const [];

  /// Icon buttons for the app bar (narrow screens).
  List<Widget> appBarActions(BuildContext context) => const [];

  /// Buttons for the welcome screen (no tabs open).
  List<Widget> welcome(BuildContext context) => const [];

  /// Items at the right of the status bar.
  List<Widget> status(BuildContext context) => const [];

  /// Keyboard shortcuts.
  Map<ShortcutActivator, VoidCallback> get shortcuts => const {};

  /// Called when the main window appears.
  void start() {}

  /// [session] is being closed (its last tab was closed), e.g. to stop
  /// what depends on it.
  void sessionClosed(SourceSession session) {}
}

/// How the app presents itself: its name, and what the welcome screen and
/// the About dialog say.
class ViewerConfig {
  final String title;

  /// Heading of the welcome screen.
  final String heading;

  /// For the About dialog.
  final String legalese;

  /// What the source setup (kinds, tab and channel names) is called, and
  /// the menu it is in.
  final String setupName;
  final String setupMenu;

  /// Seed of the colour scheme.
  final Color seedColor;

  const ViewerConfig({
    required this.title,
    required this.heading,
    this.legalese = '',
    this.setupName = 'Source setup',
    this.setupMenu = 'View',
    this.seedColor = const Color(0xFF2C728E),
  });
}
