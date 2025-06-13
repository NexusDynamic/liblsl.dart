
import 'android_multicast_lock_platform_interface.dart';

class AndroidMulticastLock {
  Future<void> acquireMulticastLock({String? lockName}) {
    return AndroidMulticastLockPlatform.instance.acquireMulticastLock(lockName: lockName);
  }

  Future<void> releaseMulticastLock() {
    return AndroidMulticastLockPlatform.instance.releaseMulticastLock();
  }

  Future<bool> isMulticastLockHeld() {
    return AndroidMulticastLockPlatform.instance.isMulticastLockHeld();
  }
}
