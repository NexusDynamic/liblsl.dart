// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing


import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:android_multicast_lock/android_multicast_lock.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('multicast lock operations test', (WidgetTester tester) async {
    final AndroidMulticastLock plugin = AndroidMulticastLock();
    
    // Test that methods can be called without throwing exceptions
    // On non-Android platforms, these will be no-ops
    await plugin.acquireMulticastLock();
    
    final bool isHeld = await plugin.isMulticastLockHeld();
    expect(isHeld, isA<bool>());
    
    await plugin.releaseMulticastLock();
  });

  testWidgets('multicast lock operations with custom lockName test', (WidgetTester tester) async {
    final AndroidMulticastLock plugin = AndroidMulticastLock();
    
    // Test that methods can be called with custom lockName without throwing exceptions
    // On non-Android platforms, these will be no-ops
    await plugin.acquireMulticastLock(lockName: 'integration_test_lock');
    
    final bool isHeld = await plugin.isMulticastLockHeld();
    expect(isHeld, isA<bool>());
    
    await plugin.releaseMulticastLock();
  });

  testWidgets('multicast lock operations with empty lockName test', (WidgetTester tester) async {
    final AndroidMulticastLock plugin = AndroidMulticastLock();
    
    // Test that methods can be called with empty lockName (should use default)
    // On non-Android platforms, these will be no-ops
    await plugin.acquireMulticastLock(lockName: '');
    
    final bool isHeld = await plugin.isMulticastLockHeld();
    expect(isHeld, isA<bool>());
    
    await plugin.releaseMulticastLock();
  });
}
