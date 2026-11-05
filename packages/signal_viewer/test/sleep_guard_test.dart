import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/src/platform/wakelock.dart';
import 'package:signal_viewer/src/settings/prefs.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _FakeWakelock extends WakelockPlusPlatformInterface {
  bool on = false;
  bool allow = true;
  int toggles = 0;

  @override
  Future<void> toggle({required bool enable}) async {
    toggles++;
    if (allow || !enable) on = enable;
  }

  @override
  Future<bool> get enabled async => on;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeWakelock fake;
  late WakelockPlusPlatformInterface original;

  setUp(() {
    original = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = fake = _FakeWakelock();
  });
  tearDown(() => wakelockPlusPlatformInstance = original);

  test('applies the saved preference when created', () async {
    final guard = SleepGuard(Preferences()..preventSleep = true);
    await guard.sync();
    expect(fake.on, isTrue);
    expect(guard.state.value, (want: true, held: true));
    expect(guard.mismatch, isFalse);
    guard.dispose();
  });

  test('does not toggle when already matching', () async {
    final guard = SleepGuard(Preferences());
    await guard.sync();
    expect(fake.toggles, 0);
    guard.dispose();
  });

  test(
    'set changes the lock and the preference, not prefs listeners',
    () async {
      final prefs = Preferences();
      var notified = 0;
      prefs.addListener(() => notified++);
      final guard = SleepGuard(prefs);
      await guard.set(true);
      expect(prefs.preventSleep, isTrue);
      expect(fake.on, isTrue);
      expect(guard.state.value, (want: true, held: true));
      await guard.set(false);
      expect(fake.on, isFalse);
      expect(notified, 0);
      guard.dispose();
    },
  );

  test('reports a lock the system refuses', () async {
    fake.allow = false;
    final guard = SleepGuard(Preferences()..preventSleep = true);
    await guard.sync();
    expect(guard.state.value, (want: true, held: false));
    expect(guard.mismatch, isTrue);
    guard.dispose();
  });

  test('sync restores a lock the system dropped', () async {
    final guard = SleepGuard(Preferences()..preventSleep = true);
    await guard.sync();
    fake.on = false; // e.g. a hidden browser tab
    await guard.sync();
    expect(fake.on, isTrue);
    guard.dispose();
  });

  test('a failing platform gives an unknown state', () async {
    wakelockPlusPlatformInstance = _Broken();
    final guard = SleepGuard(Preferences()..preventSleep = true);
    await guard.sync();
    expect(guard.state.value, (want: true, held: null));
    expect(guard.mismatch, isFalse);
    guard.dispose();
  });
}

class _Broken extends WakelockPlusPlatformInterface {}
