import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_multicast_lock_platform_interface.dart';

/// An implementation of [AndroidMulticastLockPlatform] that uses method channels.
class MethodChannelAndroidMulticastLock extends AndroidMulticastLockPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.zeyus.android_multicast_lock/manage');

  void _checkPlatform() {
    if (!Platform.isAndroid) {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'Android multicast lock is only supported on Android platforms',
        details: 'Current platform: ${Platform.operatingSystem}',
      );
    }
  }

  @override
  Future<void> acquireMulticastLock({String? lockName}) async {
    _checkPlatform();
    await methodChannel.invokeMethod<void>('acquireMulticastLock', {
      if (lockName != null) 'lockName': lockName,
    });
  }

  @override
  Future<void> releaseMulticastLock() async {
    _checkPlatform();
    await methodChannel.invokeMethod<void>('releaseMulticastLock');
  }

  @override
  Future<bool> isMulticastLockHeld() async {
    _checkPlatform();
    final result = await methodChannel.invokeMethod<bool>('isMulticastLockHeld');
    return result ?? false;
  }
}
