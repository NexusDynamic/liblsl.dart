import 'dart:convert';

import 'package:easy_shared_preferences/easy_shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../display/manchester.dart';
import '../model/groups.dart';
import '../model/stream_info.dart';
import '../model/view_settings.dart';

const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

bool get _isMobile =>
    !_isWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// App-wide preferences, saved between sessions with
/// `easy_shared_preferences` (groups mirror the Python viewer's QSettings
/// keys).
///
/// Providers keep their own settings as strings under [extraKeys] (e.g.
/// `lsl.options`), in [extra].
class Preferences extends ChangeNotifier {
  EasySettings? _settings;

  /// Keys (`group.name`) of settings that providers keep in [extra].
  final List<String> extraKeys;

  /// Settings of providers, by key; empty when not set.
  final Map<String, String> extra = {};

  Preferences({this.extraKeys = const []});

  ThemeMode themeMode = ThemeMode.system;

  /// Trace line width in px.
  double lineWidth = 1;
  bool antialias = true;

  /// Memory for decoded chunks of open recordings, in MB.
  int cacheMb = defaultCacheMb;

  bool panelVisible = true;
  Map<Kind, KindDefaults> defaults = Map.of(KindDefaults.factory);

  /// Source setup, by [StreamInfo.key].
  Map<String, SourceAssignment> sources = {};
  ManchesterSettings manchester = const ManchesterSettings();

  /// Channel labels decoded as Manchester triggers in new tabs.
  Set<String> manchesterLabels = {};

  List<String> recentFiles = [];
  String? lastDir;
  String? recordDir;

  static int get defaultCacheMb => _isWeb ? 256 : (_isMobile ? 128 : 512);

  List<SettingsGroup> _groups(SettingsStore store) {
    final extras = <String, List<String>>{};
    for (final k in extraKeys) {
      final dot = k.indexOf('.');
      (extras[k.substring(0, dot)] ??= []).add(k.substring(dot + 1));
    }
    List<StringSetting> items(List<String>? names) => [
      for (final n in names ?? const <String>[])
        StringSetting(key: n, defaultValue: ''),
    ];
    return [
      for (final (key, builtIn) in _builtIn)
        SettingsGroup(
          key: key,
          store: store,
          items: [...builtIn, ...items(extras.remove(key))],
        ),
      for (final e in extras.entries)
        SettingsGroup(key: e.key, store: store, items: items(e.value)),
    ];
  }

  static List<(String, List<Setting<dynamic>>)> get _builtIn => [
    (
      'preferences',
      [
        StringSetting(
          key: 'theme',
          defaultValue: ThemeMode.system.name,
          validator: EnumValidator<String>([
            for (final m in ThemeMode.values) m.name,
          ]).validate,
        ),
        DoubleSetting(
          key: 'line_width',
          defaultValue: 1,
          validator: (v) => v > 0 && v <= 5,
        ),
        BoolSetting(key: 'antialias', defaultValue: true),
        IntSetting(
          key: 'cache_mb',
          defaultValue: defaultCacheMb,
          validator: (v) => v >= 16 && v <= 65536,
        ),
      ],
    ),
    ('view', [BoolSetting(key: 'panel', defaultValue: true)]),
    (
      'defaults',
      [
        for (final kind in Kind.values)
          StringSetting(key: kind.name, defaultValue: ''),
      ],
    ),
    (
      'manchester',
      [
        DoubleSetting(
          key: 'clock_hz',
          defaultValue: 18,
          validator: (v) => v >= 0.5 && v <= 1000,
        ),
        StringSetting(
          key: 'order',
          defaultValue: BitOrder.lsb.name,
          validator: EnumValidator<String>([
            for (final o in BitOrder.values) o.name,
          ]).validate,
        ),
        BoolSetting(key: 'preamble', defaultValue: true),
        StringListSetting(key: 'labels', defaultValue: const []),
      ],
    ),
    (
      'files',
      [
        StringListSetting(key: 'recent', defaultValue: const []),
        StringSetting(key: 'last_dir', defaultValue: ''),
        StringSetting(key: 'record_dir', defaultValue: ''),
        // Source setup: {"<stream key>": {"group": ..., "kind": ...,
        // "names": {"<channel>": ...}}}
        StringSetting(key: 'sources', defaultValue: '{}'),
      ],
    ),
  ];

  Future<void> load() async {
    try {
      final store = SettingsStore();
      final settings = EasySettings(store: store);
      for (final g in _groups(store)) {
        settings.register(g);
      }
      await settings.init();
      _settings = settings;
    } catch (_) {
      return; // no storage available: keep defaults
    }
    final s = _settings!;
    // Each value on its own: one that cannot be read keeps its default
    // without losing the others.
    void read(void Function() f) {
      try {
        f();
      } catch (_) {}
    }

    read(
      () =>
          themeMode = ThemeMode.values.byName(s.getString('preferences.theme')),
    );
    read(() => lineWidth = s.getDouble('preferences.line_width'));
    read(() => antialias = s.getBool('preferences.antialias'));
    read(() => cacheMb = s.getInt('preferences.cache_mb'));
    read(() => panelVisible = s.getBool('view.panel'));
    for (final kind in Kind.values) {
      read(() {
        final raw = s.getString('defaults.${kind.name}');
        if (raw.isEmpty) return;
        defaults[kind] = KindDefaults.fromJson(
          jsonDecode(raw) as Map<String, Object?>,
          KindDefaults.factory[kind]!,
        );
      });
    }
    read(() {
      final m = jsonDecode(s.getString('files.sources')) as Map;
      sources = {
        for (final e in m.entries)
          e.key as String: SourceAssignment.fromJson(e.value! as Map),
      };
    });
    read(
      () => manchester = ManchesterSettings(
        clockHz: s.getDouble('manchester.clock_hz'),
        order: BitOrder.values.byName(s.getString('manchester.order')),
        preamble: s.getBool('manchester.preamble'),
      ),
    );
    read(() => manchesterLabels = s.getStringList('manchester.labels').toSet());
    for (final k in extraKeys) {
      read(() => extra[k] = s.getString(k));
    }
    read(() => recentFiles = List.of(s.getStringList('files.recent')));
    read(() => lastDir = _nonEmpty(s.getString('files.last_dir')));
    read(() => recordDir = _nonEmpty(s.getString('files.record_dir')));
    notifyListeners();
  }

  static String? _nonEmpty(String s) => s.isEmpty ? null : s;

  Future<void> save() async {
    notifyListeners();
    final s = _settings;
    if (s == null) return;
    await s.setMultiple({
      'preferences.theme': themeMode.name,
      'preferences.line_width': lineWidth,
      'preferences.antialias': antialias,
      'preferences.cache_mb': cacheMb,
      'view.panel': panelVisible,
      for (final e in defaults.entries)
        'defaults.${e.key.name}': jsonEncode(e.value.toJson()),
      'manchester.clock_hz': manchester.clockHz,
      'manchester.order': manchester.order.name,
      'manchester.preamble': manchester.preamble,
      'manchester.labels': manchesterLabels.toList(),
      for (final k in extraKeys) k: extra[k] ?? '',
      'files.recent': recentFiles,
      'files.last_dir': lastDir ?? '',
      'files.record_dir': recordDir ?? '',
      'files.sources': jsonEncode({
        for (final e in sources.entries) e.key: e.value.toJson(),
      }),
    });
  }

  void addRecent(String path) {
    recentFiles.remove(path);
    recentFiles.insert(0, path);
    if (recentFiles.length > 8) recentFiles.removeRange(8, recentFiles.length);
    save();
  }

  void restoreDefaults() {
    themeMode = ThemeMode.system;
    lineWidth = 1;
    antialias = true;
    cacheMb = defaultCacheMb;
    defaults = Map.of(KindDefaults.factory);
  }
}
