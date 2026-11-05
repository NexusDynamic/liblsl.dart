import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:signal_viewer/src/settings/prefs.dart';

/// Remembers the keys written.
class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore() : super.empty();
  final List<String> written = [];

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    written.add(key);
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save writes only the values that changed', () async {
    final store = _CountingStore();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = Preferences();
    await prefs.load();
    // The first save stores the encoded kind defaults (stored as '' until
    // then); after it, stored and in-memory values match.
    await prefs.save();
    store.written.clear();

    await prefs.save();
    expect(store.written, isEmpty, reason: 'nothing changed');

    var notified = 0;
    prefs.addListener(() => notified++);
    prefs.preventSleep = true;
    await prefs.save(notify: false);
    expect(store.written, ['flutter.preferences.prevent_sleep']);
    expect(notified, 0);

    store.written.clear();
    prefs
      ..themeMode = ThemeMode.dark
      ..recentFiles = ['/a.xdf'];
    await prefs.save();
    expect(
      store.written,
      unorderedEquals(['flutter.preferences.theme', 'flutter.files.recent']),
    );
    expect(notified, 1);

    // A fresh load sees what was saved.
    final again = Preferences();
    await again.load();
    expect(again.preventSleep, isTrue);
    expect(again.themeMode, ThemeMode.dark);
    expect(again.recentFiles, ['/a.xdf']);
  });
}
