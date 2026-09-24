import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signal_core/signal_core.dart';

import '../model/groups.dart';
import '../model/stream_info.dart';
import '../model/view_settings.dart';
import '../platform/files.dart';
import '../settings/prefs.dart';
import '../viewer/source.dart';
import 'stream_controller.dart';

/// One tab: a stream group of a source.
class TabEntry {
  final StreamController controller;
  final SourceSession session;
  final StreamGroup group;

  TabEntry(this.controller, this.session, this.group);

  String get title =>
      '${session.label} · ${group.info.name}${session.titleSuffix}';

  String get tooltip => session.tooltip;
}

/// Settings a tab had, kept for the session so regrouping or reopening
/// keeps hidden and bad channels (matched by label).
class _Remembered {
  final ViewSettings settings;

  /// Where each channel came from, to map settings onto the new tab's
  /// channels (their names may have changed).
  final List<ChannelRef> channels;
  _Remembered(this.settings, this.channels);
}

/// Everything open in the app: the sources ([sessions]) that
/// [providers] opened, and a tab per stream group.
class AppState extends ChangeNotifier {
  final Preferences prefs;
  final ViewerConfig config;
  final List<SourceProvider> providers;

  final List<SourceSession> sessions = [];
  final List<TabEntry> tabs = [];
  int _current = 0;

  String status = '';
  String? error;

  /// Files being opened (name → null while starting).
  final Set<String> opening = {};

  final Map<String, _Remembered> _remembered = {};
  final Map<SourceSession, Set<String>> _streamKeys = {};

  AppState(
    this.prefs, {
    required this.providers,
    this.config = const ViewerConfig(title: 'Viewer', heading: 'Viewer'),
  }) {
    for (final p in providers) {
      p.attach(this);
      p.addListener(notifyListeners);
    }
  }

  /// The provider of type [T].
  T provider<T extends SourceProvider>() => providers.whereType<T>().first;

  int get current => tabs.isEmpty ? 0 : _current.clamp(0, tabs.length - 1);

  set current(int i) {
    if (tabs.isEmpty) return;
    _current = i % tabs.length;
    _syncActive();
    notifyListeners();
  }

  TabEntry? get currentTab => tabs.isEmpty ? null : tabs[current];

  void _syncActive() {
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].controller.active = i == current;
    }
  }

  void setStatus(String s) {
    status = s;
    notifyListeners();
  }

  /// Show [message] as an error in the status bar.
  void setError(String message) {
    error = message;
    setStatus(message);
  }

  // -- files ----------------------------------------------------------------

  /// Extensions of the files the providers open.
  List<String> get fileExtensions => [
    for (final p in providers) ...p.fileExtensions,
  ];

  /// Why files cannot be opened now, or null.
  String? get blocksFiles {
    for (final p in providers) {
      final b = p.blocksFiles;
      if (b != null) return b;
    }
    return null;
  }

  Future<void> openFiles(List<PickedFile> picked) async {
    for (final f in picked) {
      final provider = providers.where((p) => p.opens(f)).firstOrNull;
      if (provider == null) {
        final types = [for (final e in fileExtensions) '.$e'].join(', ');
        setStatus('Not a recording ($types): ${f.name}');
        continue;
      }
      opening.add(f.name);
      setStatus('Opening ${f.name}…');
      try {
        final session = await provider.openFile(f);
        if (f.path != null) {
          prefs.addRecent(f.path!);
          final sep = f.path!.contains('\\') ? '\\' : '/';
          prefs.lastDir = f.path!.substring(0, f.path!.lastIndexOf(sep) + 1);
        }
        addSession(session);
      } catch (e) {
        setError('Could not open ${f.name}: $e');
      } finally {
        opening.remove(f.name);
        notifyListeners();
      }
    }
  }

  // -- sessions -------------------------------------------------------------

  /// Show [session]'s streams in tabs (more appear as it finds more), and
  /// select the first.
  void addSession(SourceSession session) {
    sessions.add(session);
    session.addListener(() => _onSessionChanged(session));
    final before = tabs.length;
    _rebuildTabs(session);
    if (tabs.length > before) current = before;
    setStatus(session.describe());
  }

  void _onSessionChanged(SourceSession session) {
    if (session.closed || !sessions.contains(session)) return;
    // New streams can appear (a recording being indexed, a device's ports
    // starting to send).
    final keys = {for (final s in session.streams) s.key};
    if (!setEquals(keys, _streamKeys[session])) {
      final before = tabs.length;
      _rebuildTabs(session);
      if (before == 0 && tabs.isNotEmpty) current = 0;
    }
    if (currentTab?.session == session) status = session.describe();
    notifyListeners();
  }

  /// Close [session] and its tabs.
  Future<void> closeSession(SourceSession session) async {
    for (var i = tabs.length - 1; i >= 0; i--) {
      if (tabs[i].session == session) {
        final t = tabs.removeAt(i);
        _remember(t);
        t.controller.dispose();
      }
    }
    await _release(session);
    if (_current >= tabs.length) _current = tabs.length - 1;
    if (_current < 0) _current = 0;
    _syncActive();
    notifyListeners();
  }

  Future<void> _release(SourceSession session) async {
    if (!sessions.remove(session)) return;
    _streamKeys.remove(session);
    for (final p in providers) {
      p.sessionClosed(session);
    }
    await session.close();
  }

  // -- tabs -----------------------------------------------------------------

  /// Replace the tabs of [session] with one per stream group.
  void _rebuildTabs(SourceSession session) {
    final streams = session.streams;
    _streamKeys[session] = {for (final s in streams) s.key};
    final groups = buildGroups(
      streams,
      prefs.sources,
      groupable: session.groupable,
      noun: session.memberNoun,
    );
    final old = [
      for (final t in tabs)
        if (t.session == session) t,
    ];
    for (final t in old) {
      _remember(t);
    }
    final at = old.isEmpty ? tabs.length : tabs.indexOf(old.first);
    tabs.removeWhere((t) => t.session == session);
    final wasCurrent = old.contains(currentTab);
    final entries = [
      for (final g in groups) TabEntry(_controller(session, g), session, g),
    ];
    tabs.insertAll(at.clamp(0, tabs.length), entries);
    for (final t in old) {
      t.controller.dispose();
    }
    if (wasCurrent) _current = at;
    _syncActive();
    notifyListeners();
  }

  StreamController _controller(SourceSession session, StreamGroup g) {
    final source = session.sourceFor(g.info);
    final labels = g.info.labels;
    // Settings the tab had earlier in this session win over the defaults
    // from Preferences.
    var settings = (prefs.defaults[g.info.kind] ?? const KindDefaults())
        .toSettings(labels);
    final remembered = _remembered[_rememberKey(session, g)];
    if (remembered != null) {
      final channels = g.info.channels;
      Set<int> map(Set<int> s) => {
        for (final i in s)
          if (i < remembered.channels.length &&
              channels.contains(remembered.channels[i]))
            channels.indexOf(remembered.channels[i]),
      };
      final r = remembered.settings;
      settings = r.copyWith(
        hidden: map(r.hidden),
        bad: map(r.bad),
        refChannels: map(r.refChannels),
        decoded: map(r.decoded),
      );
    } else if ((g.info.kind == Kind.event || g.info.irregular) &&
        session.decodable(g.info)) {
      settings = settings.copyWith(
        decoded: {
          for (var i = 0; i < labels.length; i++)
            if (prefs.manchesterLabels.contains(labels[i])) i,
        },
      );
    }
    return StreamController(source, settings, manchester: prefs.manchester);
  }

  String _rememberKey(SourceSession session, StreamGroup g) =>
      '${session.rememberKey}:${g.info.kind.name}:${g.info.rate}';

  void _remember(TabEntry t) {
    _remembered[_rememberKey(t.session, t.group)] = _Remembered(
      t.controller.settings,
      t.group.info.channels,
    );
  }

  Future<void> closeTab(int i) async {
    if (i < 0 || i >= tabs.length) return;
    final t = tabs.removeAt(i);
    _remember(t);
    t.controller.dispose();
    // Close a session with no tabs left.
    if (!tabs.any((x) => x.session == t.session)) await _release(t.session);
    if (_current >= tabs.length) _current = tabs.length - 1;
    if (_current < 0) _current = 0;
    _syncActive();
    notifyListeners();
  }

  // -- source setup ---------------------------------------------------------

  /// The streams of the open sources, one per key.
  List<StreamInfo> get openStreams => {
    for (final s in sessions)
      for (final i in s.streams) i.key: i,
  }.values.toList();

  /// Whether the streams with [key] are merged by tab name (from a
  /// groupable source).
  bool groupable(String key) =>
      sessions.any((s) => s.groupable && s.streams.any((i) => i.key == key));

  /// Apply a new source setup to every open session. Streams not in [a]
  /// (not open now) keep their setup.
  void setSourceAssignments(Map<String, SourceAssignment> a) {
    prefs.sources = {...prefs.sources, ...a};
    prefs.save();
    for (final s in [...sessions]) {
      _rebuildTabs(s);
    }
  }

  /// Name channel [channel] of [tab] (e.g. its cap position), or give it
  /// its device label back with an empty [name]. Applies to that channel
  /// of the stream in every source, like the rest of the source setup.
  void renameChannel(TabEntry tab, int channel, String name) {
    final stream = tab.group.memberOf(channel);
    final ref = tab.group.info.channels[channel];
    final a = prefs.sources[stream.key] ?? SourceAssignment.defaultFor(stream);
    final names = {...a.names};
    if (name.trim().isEmpty) {
      names.remove(ref.channel);
    } else {
      names[ref.channel] = name.trim();
    }
    setSourceAssignments({stream.key: a.copyWith(names: names)});
  }

  /// Remember the labels decoded as triggers, for new tabs.
  void rememberDecoded(StreamController c) {
    final info = c.info;
    for (var i = 0; i < info.channelCount; i++) {
      if (c.settings.decoded.contains(i)) {
        prefs.manchesterLabels.add(info.labels[i]);
      } else {
        prefs.manchesterLabels.remove(info.labels[i]);
      }
    }
    prefs.save();
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t.controller.dispose();
    }
    for (final p in providers) {
      p.removeListener(notifyListeners);
      p.dispose();
    }
    for (final s in sessions) {
      s.close();
    }
    super.dispose();
  }
}
