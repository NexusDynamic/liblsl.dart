import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:android_multicast_lock/android_multicast_lock_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelAndroidMulticastLock platform = MethodChannelAndroidMulticastLock();
  const MethodChannel channel = MethodChannel('com.zeyus.android_multicast_lock/manage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'acquireMulticastLock':
            // Verify lockName parameter if provided
            final lockName = methodCall.arguments?['lockName'];
            expect(lockName, anyOf(isNull, isA<String>()));
            return null;
          case 'releaseMulticastLock':
            return null;
          case 'isMulticastLockHeld':
            return true;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('acquireMulticastLock without lockName', () async {
    await platform.acquireMulticastLock();
    // Should complete without error
  });

  test('acquireMulticastLock with lockName', () async {
    await platform.acquireMulticastLock(lockName: 'test_lock');
    // Should complete without error
  });

  test('releaseMulticastLock', () async {
    await platform.releaseMulticastLock();
    // Should complete without error
  });

  test('isMulticastLockHeld', () async {
    expect(await platform.isMulticastLockHeld(), true);
  });
}
