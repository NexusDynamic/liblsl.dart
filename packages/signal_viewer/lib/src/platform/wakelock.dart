import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../settings/prefs.dart';

/// What the user asked for ([want], from [Preferences.preventSleep]) and
/// whether the wakelock is held ([held]; null when the platform could not
/// tell, e.g. it is unsupported or refused).
typedef SleepState = ({bool want, bool? held});

/// Keeps the screen awake while [Preferences.preventSleep] asks for it.
///
/// Applies the preference when created, when the app comes back (the system
/// may drop the lock meanwhile, e.g. a hidden browser tab) and on [sync].
/// [state] changes only when the wish or the lock does, so a listener
/// rebuilds just what shows it.
class SleepGuard {
  final Preferences prefs;
  final ValueNotifier<SleepState> state;
  late final AppLifecycleListener _lifecycle;

  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  SleepGuard(this.prefs)
    : state = ValueNotifier((want: prefs.preventSleep, held: null)) {
    _lifecycle = AppLifecycleListener(onResume: sync, onShow: sync);
    sync();
  }

  /// Whether the wakelock is known to differ from the preference.
  bool get mismatch {
    final s = state.value;
    return s.held != null && s.held != s.want;
  }

  /// Make the wakelock match the preference, if it does not already. Calls
  /// made while one runs fold into one more run after it.
  Future<void> sync() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _syncLoop().whenComplete(() => _running = null);
  }

  Future<void> _syncLoop() async {
    do {
      _again = false;
      final want = prefs.preventSleep;
      bool? held;
      try {
        if (await WakelockPlus.enabled != want) {
          await WakelockPlus.toggle(enable: want);
        }
        held = await WakelockPlus.enabled;
      } catch (_) {
        held = null; // unsupported here, or refused (web without a gesture)
      }
      if (_disposed) return;
      state.value = (want: want, held: held);
    } while (_again && !_disposed);
  }

  /// Change and save the preference, then apply it. Only [state]'s
  /// listeners hear of it.
  Future<void> set(bool on) async {
    prefs.preventSleep = on;
    // Show the choice at once; held is unknown until sync() reports it, so
    // no mismatch flashes meanwhile.
    state.value = (want: on, held: null);
    await Future.wait([prefs.save(notify: false), sync()]);
  }

  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    state.dispose();
  }
}
