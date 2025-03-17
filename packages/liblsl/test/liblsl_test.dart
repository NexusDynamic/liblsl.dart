import 'dart:async';

import 'package:liblsl/liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('LSL ffi direct', () {
    test('Check lsl library version', () {
      expect(lsl_library_version(), 116);
    });
  });
  group('LSL', () {
    test('Check lsl library version', () async {
      final lsl = LSL();
      expect(lsl.version, 116);
    });

    test('Create stream info', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
    });

    test('Create stream outlet throws exception without streamInfo', () async {
      final lsl = LSL();
      expect(() => lsl.createOutlet(), throwsA(isA<LSLException>()));
    });

    test('Create stream outlet', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
      await lsl.createOutlet();
    });

    test('Wait for consumer timeout exception', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
      await lsl.createOutlet();
      expect(
        () => lsl.outlet?.waitForConsumer(timeout: 1.0),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('push a default (float) sample', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
      await lsl.createOutlet();
      await lsl.outlet?.pushSample(5.0);
    });

    test('push a string sample', () async {
      final lsl = LSL();
      await lsl.createStreamInfo(channelFormat: LSLChannelFormat.string);
      await lsl.createOutlet();
      await lsl.outlet?.pushSample('Hello, World!');
    });
  });
}
