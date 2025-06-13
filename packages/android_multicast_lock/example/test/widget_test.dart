// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_multicast_lock_example/main.dart';

void main() {
  testWidgets('App starts with correct initial state', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    // Verify initial lock status shows "NOT HELD"
    expect(find.text('Multicast Lock Status: NOT HELD'), findsOneWidget);
    
    // Verify all buttons are present
    expect(find.text('Acquire Multicast Lock'), findsOneWidget);
    expect(find.text('Release Multicast Lock'), findsOneWidget);
    expect(find.text('Check Lock Status'), findsOneWidget);
    
    // Verify text field is present
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Text field accepts input', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'test-lock-name');
    
    expect(find.text('test-lock-name'), findsOneWidget);
  });

  testWidgets('Buttons are tappable and trigger status updates on non-Android', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    // On non-Android platforms, operations should fail gracefully with PlatformException
    await tester.tap(find.text('Acquire Multicast Lock'));
    await tester.pumpAndSettle();
    
    // Should show error message for unsupported platform
    expect(find.text('Status: Failed to acquire lock: Android multicast lock is only supported on Android platforms'), findsOneWidget);
    
    await tester.tap(find.text('Check Lock Status'));
    await tester.pumpAndSettle();
    
    // Status should update again with the same error
    expect(find.text('Status: Failed to check lock status: Android multicast lock is only supported on Android platforms'), findsOneWidget);
  });

}
