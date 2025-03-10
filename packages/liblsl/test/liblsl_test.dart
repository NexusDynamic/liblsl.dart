import 'dart:async';

import 'package:liblsl/liblsl.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    final lsl = LSL();
    setUp(() async {
      // Additional setup goes here.
      await lsl.createStreamInfo();
      await lsl.createOutlet();
    });

    test('Check lsl library version', () {
      expect(lsl.version, 116);
    });
    test('Wait for consumer times out with exception', () {
      expect(lsl.waitForConsumer(timeout: 1),
          throwsA(const TypeMatcher<TimeoutException>()));
    });
  });
}
