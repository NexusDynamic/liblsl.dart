import 'dart:async';

import 'package:liblsl/liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart' show FreePointerExtension;
import 'package:liblsl/src/types.dart';
import 'package:test/test.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, malloc;

void main() {
  // todo test object destruction, dealloc and free
  group('LSL ffi direct', () {
    test('Check lsl library version', () {
      expect(lsl_library_version(), 116);
    });
  });
  group('LSL', () {
    test('Check lsl library version', () async {
      final lsl = LSL();
      expect(lsl.version, 116);
      lsl.destroy();
    });

    test('Create stream info', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
      lsl.destroy();
    });

    test('Create stream outlet throws exception without streamInfo', () async {
      final lsl = LSL();
      expect(() => lsl.createOutlet(), throwsA(isA<LSLException>()));
      lsl.destroy();
    });

    test('Create stream outlet', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
      await lsl.createOutlet();
      expect(lsl.outlet, isNotNull);
      expect(lsl.outlet?.streamInfo, isNotNull);
      expect(lsl.outlet?.streamInfo.streamName, 'DartLSLStream');
      lsl.destroy();
    });

    test('Wait for consumer timeout exception', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
      await lsl.createOutlet();
      expect(
        () => lsl.outlet?.waitForConsumer(timeout: 1.0),
        throwsA(isA<TimeoutException>()),
      );
      lsl.destroy();
    });
    // TODO: ERROR: This passes but it's probably
    // passing because it's reading contiguous memory
    // for the number of channels, which fails if you do a string
    // with more than 1 channel. This is critical to
    // a) test, and fix
    // b) handle in the api to ensure that either dummy/null
    // values are pushed, or an error is thrown if the number
    // of values is less than the channels.
    test('push a default (float) sample', () async {
      final lsl = LSL();
      await lsl.createStreamInfo(channelCount: 2);
      await lsl.createOutlet();
      await lsl.outlet?.pushSample([5.0, 8.0]);
      lsl.destroy();
    });

    test('push a string sample', () async {
      final lsl = LSL();
      await lsl.createStreamInfo(
        channelFormat: LSLChannelFormat.string,
        channelCount: 5,
      );
      await lsl.createOutlet();
      await lsl.outlet?.pushSample(['Hello', 'World', 'This', 'is', 'a test']);
      lsl.destroy();
    });
    test('Create outlet and resolve available streams', () async {
      final lsl = LSL();
      await lsl.createStreamInfo();
      final outlet = await lsl.createOutlet();
      outlet.waitForConsumer(timeout: 5.0, exception: false);
      final streams = await lsl.resolveStreams(waitTime: 1.0);
      expect(streams.length, greaterThan(0));
      for (final stream in streams) {
        stream.destroy();
      }
      lsl.destroy();
    });

    test(
      'create outlet, resolve stream, create inlet and pull sample',
      () async {
        final lsl = LSL();
        await lsl.createStreamInfo();
        final outlet = await lsl.createOutlet();
        outlet.waitForConsumer(timeout: 5.0, exception: false);
        final streams = await lsl.resolveStreams(waitTime: 1.0);
        expect(streams.length, greaterThan(0));
        final inlet = await lsl.createInlet(streamInfo: streams[0]);
        final sample = await inlet.pullSample();
        expect(sample.data.length, 2);
        expect(sample.data[0], isA<double>());
        expect(sample.data[1], isA<double>());
        for (final stream in streams) {
          stream.destroy();
        }
        lsl.destroy();
      },
    );
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
