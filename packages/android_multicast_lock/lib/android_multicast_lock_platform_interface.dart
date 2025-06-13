import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'android_multicast_lock_method_channel.dart';

abstract class AndroidMulticastLockPlatform extends PlatformInterface {
  /// Constructs a AndroidMulticastLockPlatform.
  AndroidMulticastLockPlatform() : super(token: _token);

  static final Object _token = Object();

  static AndroidMulticastLockPlatform _instance = MethodChannelAndroidMulticastLock();

  /// The default instance of [AndroidMulticastLockPlatform] to use.
  ///
  /// Defaults to [MethodChannelAndroidMulticastLock].
  static AndroidMulticastLockPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AndroidMulticastLockPlatform] when
  /// they register themselves.
  static set instance(AndroidMulticastLockPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> acquireMulticastLock({String? lockName}) {
    throw UnimplementedError('acquireMulticastLock() has not been implemented.');
  }

  Future<void> releaseMulticastLock() {
    throw UnimplementedError('releaseMulticastLock() has not been implemented.');
  }

  Future<bool> isMulticastLockHeld() {
    throw UnimplementedError('isMulticastLockHeld() has not been implemented.');
  }
}
