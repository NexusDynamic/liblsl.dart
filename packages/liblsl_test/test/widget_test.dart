import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Key, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:liblsl_test/main.dart';

void main() {
  testWidgets('Liblsl native loads version', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LSLTestApp());

    // Verify that our counter starts at 0.
    //expect(find.text('Calculating answer...'), findsOneWidget);
    await tester.pumpAndSettle(Duration(seconds: 1));

    // Verify that our counter has incremented.
    expect(find.text('LSL Version 116'), findsOneWidget);
  });

  // Test streaming and UI verification
  testWidgets('Start LSL stream and verify UI updates',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LSLTestApp());

    await tester.pumpAndSettle(Duration(seconds: 1));

    // Verify that our counter has incremented.
    expect(find.text('LSL Version 116'), findsOneWidget);

    // Verify initial stream status
    expect(find.byKey(const Key('stream_status')), findsOneWidget);
    expect(find.text('Stream status: Not checked'), findsOneWidget);

    // Press the start streaming button
    debugPrint('Pressing start streaming button');
    await tester.tap(find.byKey(const Key('start_streaming')));
    debugPrint('Tapped start streaming button');
    await tester.pumpAndSettle(Duration(seconds: 6));
    debugPrint('Streaming should be finished');

    // Verify stop button appeared and start button is disabled
    expect(find.byKey(const Key('stop_streaming')), findsOneWidget);

    // Now test the stream checking functionality
    debugPrint('Pressing check streams button');
    await tester.tap(find.byKey(const Key('check_streams')));
    debugPrint('Tapped check streams button');
    await tester.pumpAndSettle(Duration(seconds: 8));
    debugPrint('Check streams should be finished');

    // Verify that stream status was updated
    expect(find.byKey(const Key('stream_status')), findsOneWidget);

    // Check if we found streams (should show success or no streams found)
    final streamStatusFinder = find.byKey(const Key('stream_status'));
    if (streamStatusFinder.evaluate().isNotEmpty) {
      final Text streamStatusWidget = tester.widget(streamStatusFinder) as Text;
      final statusText = streamStatusWidget.data!;
      debugPrint('Stream status: $statusText');

      // If streams were found, verify sample data is shown
      if (statusText.contains('Sample received successfully')) {
        expect(find.byKey(const Key('sample_data')), findsOneWidget);
        expect(find.byKey(const Key('resolved_streams')), findsOneWidget);

        // Verify sample data format
        final sampleDataFinder = find.byKey(const Key('sample_data'));
        final Text sampleWidget = tester.widget(sampleDataFinder) as Text;
        final sampleText = sampleWidget.data!;
        expect(sampleText, contains('Sample: ['));
        expect(sampleText, contains(', '));
        expect(sampleText, contains(']'));
        debugPrint('Sample data: $sampleText');

        // Verify resolved stream info
        final resolvedStreamsFinder = find.byKey(const Key('resolved_streams'));
        final Text streamWidget = tester.widget(resolvedStreamsFinder) as Text;
        final streamText = streamWidget.data!;
        expect(streamText, contains('Stream: FlutterApp'));
        expect(streamText, contains('Channels: 2'));
        expect(streamText, contains('Format: LSLChannelFormat.float32'));
        debugPrint('Resolved stream: $streamText');
      } else {
        debugPrint('No streams found or stream check failed: $statusText');
      }
    }

    // press the stop streaming button if it's still there
    if (find.byKey(const Key('stop_streaming')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('stop_streaming')));
      await tester.pumpAndSettle();
    }
  });
}
