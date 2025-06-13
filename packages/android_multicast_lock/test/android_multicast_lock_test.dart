import 'package:flutter_test/flutter_test.dart';
import 'package:android_multicast_lock/android_multicast_lock.dart';
import 'package:android_multicast_lock/android_multicast_lock_platform_interface.dart';
import 'package:android_multicast_lock/android_multicast_lock_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAndroidMulticastLockPlatform
    with MockPlatformInterfaceMixin
    implements AndroidMulticastLockPlatform {

  bool _isLockHeld = false;

  @override
  Future<void> acquireMulticastLock({String? lockName}) async {
    _isLockHeld = true;
  }

  @override
  Future<void> releaseMulticastLock() async {
    _isLockHeld = false;
  }

  @override
  Future<bool> isMulticastLockHeld() async {
    return _isLockHeld;
  }
}

void main() {
  final AndroidMulticastLockPlatform initialPlatform = AndroidMulticastLockPlatform.instance;

  test('$MethodChannelAndroidMulticastLock is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAndroidMulticastLock>());
  });

  test('multicast lock operations', () async {
    AndroidMulticastLock androidMulticastLockPlugin = AndroidMulticastLock();
    MockAndroidMulticastLockPlatform fakePlatform = MockAndroidMulticastLockPlatform();
    AndroidMulticastLockPlatform.instance = fakePlatform;

    // Initially not held
    expect(await androidMulticastLockPlugin.isMulticastLockHeld(), false);

    // Acquire lock without lockName
    await androidMulticastLockPlugin.acquireMulticastLock();
    expect(await androidMulticastLockPlugin.isMulticastLockHeld(), true);

    // Release lock
    await androidMulticastLockPlugin.releaseMulticastLock();
    expect(await androidMulticastLockPlugin.isMulticastLockHeld(), false);
  });

  test('multicast lock operations with custom lockName', () async {
    AndroidMulticastLock androidMulticastLockPlugin = AndroidMulticastLock();
    MockAndroidMulticastLockPlatform fakePlatform = MockAndroidMulticastLockPlatform();
    AndroidMulticastLockPlatform.instance = fakePlatform;

    // Initially not held
    expect(await androidMulticastLockPlugin.isMulticastLockHeld(), false);

    // Acquire lock with custom lockName
    await androidMulticastLockPlugin.acquireMulticastLock(lockName: 'custom_lock_name');
    expect(await androidMulticastLockPlugin.isMulticastLockHeld(), true);

    // Release lock
    await androidMulticastLockPlugin.releaseMulticastLock();
    expect(await androidMulticastLockPlugin.isMulticastLockHeld(), false);
  });
}
