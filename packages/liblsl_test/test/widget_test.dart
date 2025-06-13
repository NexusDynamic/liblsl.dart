import 'package:flutter/material.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:liblsl_test/main.dart';
import 'package:liblsl/lsl.dart';

void main() {
  testWidgets('Liblsl native loads version', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LSLTestApp());

    // Verify that our counter starts at 0.
    expect(find.text('Calculating answer...'), findsOneWidget);
    await tester.pumpAndSettle(Duration(seconds: 1));

    // Verify that our counter has incremented.
    expect(find.text('LSL Version 116'), findsOneWidget);
  });

  // add test to press the start streaming button and create inlet
  testWidgets('Start LSL stream and consumer', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LSLTestApp());

    // Verify that our counter starts at 0.
    expect(find.text('Calculating answer...'), findsOneWidget);
    await tester.pumpAndSettle(Duration(seconds: 1));

    // Verify that our counter has incremented.
    expect(find.text('LSL Version 116'), findsOneWidget);

    // Press the start streaming button
    await tester.tap(find.byKey(const Key('start_streaming')));
    await tester.pumpAndSettle();

    // Resolve available streams
    final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 1);
    expect(streams.length, 1);
    expect(streams[0].streamName, 'FlutterApp');
    expect(streams[0].channelCount, 2);
    expect(streams[0].channelFormat, LSLChannelFormat.float32);

    // create inlet
    final inlet = await LSL.createInlet(streamInfo: streams[0]);
    expect(inlet, isNotNull);
    expect(inlet.streamInfo, isNotNull);
    expect(inlet.streamInfo.streamName, 'FlutterApp');

    // pull some samples
    final sample = await inlet.pullSample(timeout: 1.0);
    expect(sample, isNotNull);
    expect(sample.timestamp, isNotNull);
    expect(sample.data, isNotNull);
    expect(sample.data.length, 2);
    expect(sample.data[0], isA<double>());
    expect(sample.data[1], isA<double>());
    expect(sample.errorCode, 0);

    // close inlet
    inlet.destroy();

    // press the stop streaming button
    await tester.tap(find.byKey(const Key('stop_streaming')));
    await tester.pumpAndSettle();
  });
}
