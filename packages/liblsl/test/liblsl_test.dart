import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart' show FreePointerExtension;
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
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
        throwsA(isA<LSLTimeout>()),
      );
      lsl.destroy();
    });
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
      await lsl.createOutlet();
      final streams = await lsl.resolveStreams(waitTime: 1.0);
      expect(streams.length, greaterThan(0));
      //streams.destroy();
      lsl.destroy();
    });

    test(
      'create outlet, resolve stream, create inlet and pull sample',
      () async {
        final lsl = LSL();
        await lsl.createStreamInfo(
          streamName: 'TestStream',
          channelCount: 2,
          channelFormat: LSLChannelFormat.int8,
        );
        final outlet = await lsl.createOutlet();

        final streams = await lsl.resolveStreams(waitTime: 0.1);
        expect(streams.length, greaterThan(0));

        LSLStreamInfo? streamInfo;
        for (final stream in streams) {
          if (stream.streamName == 'TestStream') {
            streamInfo = stream;
            break;
          }
        }
        expect(streamInfo, isNotNull);
        expect(streamInfo?.streamName, 'TestStream');
        final inlet = await lsl.createInlet(
          maxBufferSize: 1,
          streamInfo: streamInfo!,
        );

        await outlet.pushSample([1, 2]);
        inlet.flush();
        expect(inlet.samplesAvailable(), 0);
        await outlet.pushSample([5, 8]);
        await Future.delayed(const Duration(milliseconds: 200));
        await outlet.pushSample([5, 8]);
        await outlet.pushSample([5, 8]);
        await outlet.pushSample([5, 8]);
        await outlet.pushSample([5, 8]);
        await outlet.pushSample([5, 8]);
        await outlet.pushSample([5, 8]);
        await outlet.pushSample([5, 8]);
        outlet.pushSample([5, 8]);
        expect(inlet.samplesAvailable(), 1);
        final sample = inlet.pullSample(timeout: 1.0);
        outlet.pushSample([7, 7]);
        sample.then((s) {
          expect(s, isA<LSLSample<int>>());
          expect(s.errorCode, 0);
          expect(s.length, 2);
          expect(s[0], isA<int>());
          expect(s[1], isA<int>());
          expect(s[0], 5);
          expect(s[1], 8);
        });
        outlet.pushSample([3, 4]);
        sample.whenComplete(() {
          // clean up
          lsl.destroy();
        });
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
