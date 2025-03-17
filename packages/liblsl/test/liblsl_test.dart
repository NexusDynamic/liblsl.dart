import 'dart:async';

import 'package:liblsl/liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart' show FreePointerExtension;
import 'package:liblsl/src/types.dart';
import 'package:test/test.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, malloc;

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
    test('Direct FFI test for string sample', () {
      // Create a simple stream info
      final streamNamePtr = "TestStream".toNativeUtf8().cast<Char>();
      final streamTypePtr = "EEG".toNativeUtf8().cast<Char>();
      final sourceIdPtr = "TestSource".toNativeUtf8().cast<Char>();

      final streamInfo = lsl_create_streaminfo(
        streamNamePtr,
        streamTypePtr,
        1, // One channel
        100.0, // 100Hz sample rate
        lsl_channel_format_t.cft_string, // String format
        sourceIdPtr,
      );

      // Create outlet
      final outlet = lsl_create_outlet(streamInfo, 0, 1);

      // Create a string sample (as an array of strings)
      final sampleStr = "Test Sample".toNativeUtf8().cast<Char>();
      final stringArray = malloc<Pointer<Char>>(1);
      stringArray[0] = sampleStr;

      // Push the sample
      final result = lsl_push_sample_str(outlet, stringArray);

      // Assert the result
      expect(result, 0); // 0 typically means success

      // Clean up
      lsl_destroy_outlet(outlet);
      lsl_destroy_streaminfo(streamInfo);
      streamNamePtr.free();
      streamTypePtr.free();
      sourceIdPtr.free();
      sampleStr.free();
      stringArray.free();
    });
  });
}
