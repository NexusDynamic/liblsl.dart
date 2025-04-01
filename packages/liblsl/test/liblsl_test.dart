import 'dart:async';

import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart' show FreePointerExtension;
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
      expect(LSL.version, 116);
    });

    test('Create stream info', () async {
      final streamInfo = await LSL.createStreamInfo();
      expect(streamInfo, isNotNull);
      expect(streamInfo.streamName, 'DartLSLStream');
      streamInfo.destroy();
    });

    test('Create stream outlet', () async {
      final streamInfo = await LSL.createStreamInfo();
      final streamOutlet = await LSL.createOutlet(streamInfo: streamInfo);
      expect(streamOutlet, isNotNull);
      expect(streamOutlet.streamInfo, isNotNull);
      expect(streamOutlet.streamInfo.streamName, 'DartLSLStream');
      streamOutlet.destroy();
      streamInfo.destroy();
    });

    test('Wait for consumer timeout exception', () async {
      final streamInfo = await LSL.createStreamInfo();
      final outlet = await LSL.createOutlet(streamInfo: streamInfo);
      expect(
        () => outlet.waitForConsumer(timeout: 1.0),
        throwsA(isA<LSLTimeout>()),
      );
      outlet.destroy();
      streamInfo.destroy();
    });
    test('push a default (float) sample', () async {
      final streamInfo = await LSL.createStreamInfo(channelCount: 2);
      final outlet = await LSL.createOutlet(streamInfo: streamInfo);
      final result = await outlet.pushSample([5.0, 8.0]);
      expect(result, 0); // 0 typically means success

      outlet.destroy();
      streamInfo.destroy();
    });

    test('push a string sample', () async {
      final streamInfo = await LSL.createStreamInfo(
        channelFormat: LSLChannelFormat.string,
        channelCount: 1,
      );
      final outlet = await LSL.createOutlet(streamInfo: streamInfo);
      final result = await outlet.pushSample(['Test Sample']);
      expect(result, 0);

      outlet.destroy();
      streamInfo.destroy();
    });
    test('Create outlet and resolve available streams', () async {
      final streamInfo = await LSL.createStreamInfo();
      final outlet = await LSL.createOutlet(streamInfo: streamInfo);
      final streams = await LSL.resolveStreams(waitTime: 1.0);
      expect(streams.length, greaterThan(0));

      // Find the right stream
      LSLStreamInfo? foundStreamInfo;
      for (final stream in streams) {
        if (stream.streamName == 'DartLSLStream') {
          foundStreamInfo = stream;
          break;
        }
      }

      // Validate the found stream
      expect(foundStreamInfo, isNotNull);
      expect(foundStreamInfo?.streamName, 'DartLSLStream');

      outlet.destroy();
      streamInfo.destroy();
    });
    test('outlet, resolve, inlet, pull sample', () async {
      final oStreamInfo = await LSL.createStreamInfo(
        streamName: 'TestStream',
        channelCount: 2,
        channelFormat: LSLChannelFormat.float32,
        sampleRate: LSL_IRREGULAR_RATE,
        streamType: LSLContentType.markers,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: oStreamInfo,
        chunkSize: 1,
        maxBuffer: 360,
      );
      expect(outlet, isNotNull);

      final Completer<void> completer = Completer<void>();
      // Start sending data in the background
      // this works
      // final senderFuture = () async {
      //   // while (!completer.isCompleted) {
      //   await Future.delayed(Duration(milliseconds: 200));
      //   await outlet.pushSample([5.0, 8.0]);
      //   // }
      // }();

      await Future.delayed(Duration(milliseconds: 10));

      final streams = await LSL.resolveStreams(waitTime: 0.1);
      expect(streams.length, greaterThan(0));
      // Find and validate the stream
      final streamInfo = streams.firstWhere(
        (s) => s.streamName == 'TestStream',
      );
      expect(streamInfo, isNotNull);

      // Create inlet and allow time for connection
      final inlet = await LSL.createInlet<double>(
        maxBufferSize: 360,
        maxChunkLength: 1,
        streamInfo: streamInfo,
        recover: false,
      );
      // After creating the inlet
      // Check how many samples are available before pulling
      () async {
        await Future.delayed(Duration(milliseconds: 100));
        await outlet.pushSample([5.0, 8.0]);
      }();

      final s = await inlet.pullSample(timeout: 5.0);
      // Validate the sample
      expect(s.length, 2);
      expect(s[0], 5.0); // Adjust based on expected sample order
      expect(s[1], 8.0);

      inlet.pullSample(timeout: 5.0).then((s) {
        // Validate the sample
        expect(s.length, 2);
        expect(s[0], 5.0); // Adjust based on expected sample order
        expect(s[1], 8.0);
      });
      await Future.delayed(Duration(milliseconds: 50));
      await outlet.pushSample([5.0, 8.0]);

      completer.complete();
      //await senderFuture; // Wait for the sender to finish

      // Clean up
      inlet.destroy();
      outlet.destroy();
      oStreamInfo.destroy();
      streamInfo.destroy();
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
