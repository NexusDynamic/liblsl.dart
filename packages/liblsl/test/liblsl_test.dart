import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart' show FreePointerExtension;
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
    test('Create stream info with custom parameters', () async {
      final lsl = LSL();
      final streamInfo = await lsl.createStreamInfo(
        streamName: 'TestStream',
        channelCount: 2,
        channelFormat: LSLChannelFormat.float32,
        sampleRate: 100.0,
      );
      expect(streamInfo, isNotNull);
      expect(streamInfo.streamName, 'TestStream');
      expect(streamInfo.channelCount, 2);
      expect(streamInfo.channelFormat, LSLChannelFormat.float32);
      expect(streamInfo.sampleRate, 100.0);
      lsl.destroy();
    });

    test('Create stream outlet', () async {
      final lsl = LSL();
      final streamInfo = await lsl.createStreamInfo();
      final outlet = await lsl.createOutlet(streamInfo: streamInfo);
      expect(outlet, isNotNull);
      expect(outlet.streamInfo, isNotNull);
      expect(outlet.streamInfo.streamName, 'DartLSLStream');
      outlet.destroy();
      lsl.destroy();
    });

    test('Wait for consumer timeout exception', () async {
      final lsl = LSL();
      final streamInfo = await lsl.createStreamInfo();
      final outlet = await lsl.createOutlet(streamInfo: streamInfo);
      expect(
        () => outlet.waitForConsumer(timeout: 1.0),
        throwsA(isA<LSLTimeout>()),
      );
      outlet.destroy();
      lsl.destroy();
    });
    test('push a default (float) sample', () async {
      final lsl = LSL();
      final streamInfo = await lsl.createStreamInfo(channelCount: 2);
      final outlet = await lsl.createOutlet(streamInfo: streamInfo);
      await outlet.pushSample([5.0, 8.0]);
      outlet.destroy();
      lsl.destroy();
    });

    test('push a string sample', () async {
      final lsl = LSL();
      final streamInfo = await lsl.createStreamInfo(
        channelFormat: LSLChannelFormat.string,
        channelCount: 5,
      );
      final outlet = await lsl.createOutlet(streamInfo: streamInfo);
      await outlet.pushSample(['Hello', 'World', 'This', 'is', 'a test']);
      outlet.destroy();
      lsl.destroy();
    });
    test('Create outlet and resolve available streams', () async {
      final lsl = LSL();
      final streamInfo = await lsl.createStreamInfo();
      final outlet = await lsl.createOutlet(streamInfo: streamInfo);
      final streams = await lsl.resolveStreams(waitTime: 1.0);
      expect(streams.length, greaterThan(0));
      //streams.destroy();
      outlet.destroy();
      lsl.destroy();
    });

    // /// this will be skipped normally unless e.g. the pylsl script is running
    // /// this works from pylsl...
    // /// prints out e.g.:
    // /// Sample: LSLSample{data: [0.19785338640213013, 0.9229772090911865, 0.7834794521331787, 0.10717403888702393, 0.8670063614845276, 0.5186590552330017, 0.15880778431892395, 0.790692150592804], timestamp: 75012.221855291, errorCode: 0}
    // /// Sample: LSLSample{data: [0.9281628131866455, 0.2588001787662506, 0.32235756516456604, 0.04881776124238968, 0.9249580502510071, 0.19534574449062347, 0.2730277478694916, 0.36848941445350647], timestamp: 75012.232806958, errorCode: 0}
    // test('create inlet and pull samples from external source', () async {
    //   final lsl = LSL();
    //   final streams = await lsl.resolveStreams(waitTime: 1.0);
    //   expect(streams.length, greaterThan(0));
    //   // find the right stream
    //   LSLStreamInfo? streamInfo;
    //   for (final stream in streams) {
    //     print(stream.toString());
    //     if (stream.streamName == 'BioSemi') {
    //       streamInfo = stream;
    //       break;
    //     }
    //   }
    //   // found?
    //   expect(streamInfo, isNotNull);
    //   expect(streamInfo?.streamName, 'BioSemi');
    //   // create inlet from found stream info
    //   final inlet = await lsl.createInlet(
    //     maxBufferSize: 360,
    //     maxChunkLength: 0,
    //     streamInfo: streamInfo!,
    //     recover: true,
    //   );
    //   while (true) {
    //     // get the sample
    //     final s = await inlet.pullSample(timeout: 0.1);
    //     // validate received sample
    //     expect(s, isA<LSLSample<double>>());
    //     expect(s.length, 8);
    //     expect(s.timestamp, isA<double>());
    //     expect(s.errorCode, 0);

    //     print('Sample: ${s.toString()}');

    //     await Future.delayed(Duration(milliseconds: 50));
    //   }
    // });

    // test(
    //   'create outlet, resolve stream, create inlet and pull sample',
    //   () async {
    //     final lsl = LSL();

    //     // create stream info
    //     await lsl.createStreamInfo(
    //       streamName: 'TestStream',
    //       channelCount: 2,
    //       channelFormat: LSLChannelFormat.float32,
    //       sampleRate: 0.5,
    //     );

    //     // print(info.toString());

    //     // create outlet
    //     final outlet = await lsl.createOutlet(chunkSize: 0, maxBuffer: 1);

    //     // push some samples
    //     final int result = await outlet.pushSample([1.0, 2.0]);
    //     expect(result, 0);

    //     // resolve streams
    //     final streams = await lsl.resolveStreams(
    //       waitTime: 0.5,
    //       maxStreams: 2,
    //       forgetAfter: 1.0,
    //     );
    //     expect(streams.length, greaterThan(0));

    //     // find the right stream
    //     LSLStreamInfo? streamInfo;
    //     for (final stream in streams) {
    //       print(stream.toString());
    //       if (stream.streamName == 'TestStream') {
    //         streamInfo = stream;
    //         // break;
    //       }
    //     }

    //     // found?
    //     expect(streamInfo, isNotNull);
    //     expect(streamInfo?.streamName, 'TestStream');

    //     // create inlet from found stream info
    //     final inlet = await lsl.createInlet(
    //       maxBufferSize: 360,
    //       maxChunkLength: 0,
    //       streamInfo: streamInfo!,
    //       recover: true,
    //     );
    //     // inlet.flush();
    //     await outlet.pushSample([5.0, 8.0]);
    //     await Future.delayed(Duration(milliseconds: 10));

    //     // make sure there is at least one queued sample

    //     outlet.pushSample([9.0, 7.0]);
    //     await Future.delayed(Duration(milliseconds: 10));
    //     //expect(inlet.samplesAvailable(), greaterThan(0));
    //     outlet.pushSample([9.0, 7.0]);
    //     outlet.pushSample([9.0, 7.0]);
    //     outlet.pushSample([9.0, 7.0]);
    //     outlet.pushSample([9.0, 7.0]);
    //     outlet.pushSample([9.0, 7.0]);
    //     outlet.pushSample([9.0, 7.0]);
    //     // get the sample
    //     final s = await inlet.pullSample(timeout: 0.5);
    //     outlet.pushSample([3.0, 5.0]);
    //     // validate received sample

    //     // general
    //     print(s.toString());
    //     expect(s, isA<LSLSample<double>>());
    //     expect(s.length, 2);
    //     expect(s[0], 5.0);
    //     expect(s[1], 8.0);
    //     expect(s.timestamp, isA<double>());
    //     expect(s.errorCode, 0);

    //     lsl.destroy();
    //   },
    // );
    test(
      'create outlet, resolve stream, create inlet and pull sample',
      () async {
        final lsl = LSL();
        // Create stream info and outlet
        final oStreamInfo = await lsl.createStreamInfo(
          streamName: 'TestStream',
          channelCount: 2,
          channelFormat: LSLChannelFormat.float32,
          sampleRate: 0.5,
        );
        final outlet = await lsl.createOutlet(
          streamInfo: oStreamInfo,
          chunkSize: 0,
          maxBuffer: 1,
        );

        await outlet.pushSample([5.0, 8.0]);

        await Future.delayed(Duration(milliseconds: 10));

        final streams = await lsl.resolveStreams(waitTime: 0.1);
        expect(streams.length, greaterThan(0));

        // Find and validate the stream
        final streamInfo = streams.firstWhere(
          (s) => s.streamName == 'TestStream',
        );
        expect(streamInfo, isNotNull);

        // Create inlet and allow time for connection
        final inlet = await lsl.createInlet(
          maxBufferSize: 360,
          streamInfo: streamInfo,
          recover: false,
        );
        await outlet.pushSample([5.0, 8.0]);
        await Future.delayed(
          Duration(milliseconds: 100),
        ); // Allow connection time

        // Pull sample with timeout
        final s = await inlet.pullSample(timeout: 1.0);
        print(s.toString());

        // Validate the sample
        expect(s.length, 2);
        expect(s[0], 5.0); // Adjust based on expected sample order
        expect(s[1], 8.0);

        outlet.destroy();
        inlet.destroy();
        lsl.destroy(); // Ensure this is after all operations
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
