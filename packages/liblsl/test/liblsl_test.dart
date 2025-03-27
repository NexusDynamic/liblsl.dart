import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart' show FreePointerExtension;
import 'package:test/test.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, malloc;

void main() {
  test('detailed hybrid test', () async {
    // 1. Create stream info
    print('Creating stream info');
    final streamInfo = LSLStreamInfo(
      streamName: 'DetailTest',
      sourceId: 'DetailSource',
      channelCount: 2,
      channelFormat: LSLChannelFormat.float32,
    );
    streamInfo.create();
    print('Stream info created: ${streamInfo.toString()}');

    // 2. Create outlet directly
    print('Creating outlet directly');
    final outlet = LSLStreamOutlet(
      streamInfo: streamInfo,
      chunkSize: 0,
      maxBuffer: 1,
    );
    outlet.create();
    print('Outlet created');

    // 3. Push a sample
    print('Pushing initial sample [99.0, 88.0]');
    final pushResult = await outlet.pushSample([99.0, 88.0]);
    print('Push result: $pushResult');

    // 4. Wait for consumers
    print('Checking if outlet has consumers');
    final hasConsumers = lsl_have_consumers(outlet.streamOutlet!);
    print('Has consumers: $hasConsumers (0=no, 1=yes)');

    // 5. Create LSL instance for inlet
    final lsl = LSL();

    // 6. Resolve streams
    print('Resolving streams');
    final resolvedStreams = await lsl.resolveStreams(waitTime: 1.0);
    print('Found ${resolvedStreams.length} streams');

    // 7. Print more details
    for (final s in resolvedStreams) {
      print(
        'Stream: ${s.streamName}, type: ${s.streamType.value}, ' +
            'source: ${s.sourceId}, host: ${s.hostname}, uid: ${s.uid}',
      );
    }

    // 8. Find target stream
    print('Finding target stream');
    final targetStream = resolvedStreams.firstWhere(
      (s) => s.streamName == 'DetailTest' && s.sourceId == 'DetailSource',
    );
    print('Target stream found: ${targetStream.toString()}');

    // 9. Create inlet in isolate
    print('Creating inlet in isolate');
    final inlet = await lsl.createInlet(
      streamInfo: targetStream,
      recover: false,
    );
    print('Inlet created');
    // Then in your test:
    print('Explicitly opening the stream');
    await inlet.openStream(timeout: 2.0);
    print('Stream opened');
    // 10. Check if samples are available
    print('Checking if samples are available before push');
    final samplesAvailableBefore = await inlet.samplesAvailable();
    print('Samples available before push: $samplesAvailableBefore');

    // 11. Push more samples
    print('Pushing more samples [77.0, 66.0]');
    await outlet.pushSample([77.0, 66.0]);

    // 12. Wait a moment
    print('Waiting for sample propagation');
    await Future.delayed(Duration(milliseconds: 500));

    // 13. Check samples available again
    print('Checking if samples are available after push');
    final samplesAvailableAfter = await inlet.samplesAvailable();
    print('Samples available after push: $samplesAvailableAfter');

    // 14. Try to pull with longer timeout
    print('Pulling sample with 3 second timeout');
    final sample = await inlet.pullSample(timeout: 3.0);
    print(
      'Pulled sample: ${sample.data}, timestamp: ${sample.timestamp}, errorCode: ${sample.errorCode}',
    );

    // 15. Clean up
    print('Cleaning up');
    inlet.destroy();
    outlet.destroy();
    lsl.destroy();
    print('Test completed');
  });

  test('hybrid approach test', () async {
    final lsl = LSL();

    // Create stream info
    final streamInfo = LSLStreamInfo(
      streamName: 'HybridTest',
      sourceId: 'HybridSource',
      channelCount: 2,
      channelFormat: LSLChannelFormat.float32,
    );
    streamInfo.create();

    // Create outlet directly
    final outlet = LSLStreamOutlet(
      streamInfo: streamInfo,
      chunkSize: 0,
      maxBuffer: 1,
    );
    outlet.create();

    // Push sample directly
    await outlet.pushSample([99.0, 88.0]);

    // Now create inlet in isolate via your LSL class
    final resolvedStreams = await lsl.resolveStreams(waitTime: 1.0);

    // Find by exact name and source ID
    final targetStream = resolvedStreams.firstWhere(
      (s) => s.streamName == 'HybridTest' && s.sourceId == 'HybridSource',
    );

    // Create inlet in isolate
    final inlet = await lsl.createInlet(
      streamInfo: targetStream,
      recover: false,
    );

    // Push more directly
    await outlet.pushSample([77.0, 66.0]);

    // Try to pull via isolate
    final sample = await inlet.pullSample(timeout: 2.0);
    print('Hybrid test sample: ${sample.data}');

    // Clean up
    inlet.destroy();
    outlet.destroy();
    lsl.destroy();
  });
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

    test('investigate duplicate streams', () async {
      // Create a unique LSL instance for this test
      final lsl = LSL();

      // First, check what streams exist BEFORE creating anything
      print('Checking existing streams...');
      final existingStreams = await lsl.resolveStreams(waitTime: 1.0);
      print('Found ${existingStreams.length} existing streams:');
      for (final s in existingStreams) {
        print(
          '  ${s.streamName}, ${s.streamType.value}, sourceId: ${s.sourceId}, uid: ${s.uid}',
        );
      }

      // Create a uniquely named stream
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      final streamName = 'TestStream_$testId';
      final sourceId = 'TestSource_$testId';

      print('\nCreating new stream: $streamName, sourceId: $sourceId');
      final streamInfo = await lsl.createStreamInfo(
        streamName: streamName,
        sourceId: sourceId,
        channelCount: 1,
        channelFormat: LSLChannelFormat.float32,
      );

      final outlet = await lsl.createOutlet(streamInfo: streamInfo);

      // Wait for the outlet to be fully established
      await Future.delayed(Duration(seconds: 1));

      // Now check what streams exist AFTER creating our outlet
      print('\nChecking streams after creating outlet...');
      final newStreams = await lsl.resolveStreams(waitTime: 1.0);
      print('Found ${newStreams.length} streams after creating outlet:');
      for (final s in newStreams) {
        print(
          '  ${s.streamName}, ${s.streamType.value}, sourceId: ${s.sourceId}, uid: ${s.uid}',
        );
      }

      // Try to find how many streams match our unique identifiers
      final matchingStreams =
          newStreams
              .where(
                (s) => s.streamName == streamName && s.sourceId == sourceId,
              )
              .toList();

      print(
        '\nFound ${matchingStreams.length} streams matching our new stream:',
      );
      for (final s in matchingStreams) {
        print('  uid: ${s.uid}, host: ${s.hostname}');
      }

      // Now let's see what happens in the LSL implementation
      print('\nLooking at the structure of the LSL implementation:');
      print('LSL class outlet proxies: ${lsl.sendPorts.length}');
      print('LSL class isolates: ${lsl.isolates.length}');

      // Clean up
      print('\nCleaning up...');
      outlet.destroy();
      await Future.delayed(Duration(seconds: 1));

      // Check one more time after cleanup
      print('\nChecking streams after cleanup...');
      final cleanupStreams = await lsl.resolveStreams(waitTime: 1.0);
      print('Found ${cleanupStreams.length} streams after cleanup:');
      for (final s in cleanupStreams) {
        print(
          '  ${s.streamName}, ${s.streamType.value}, sourceId: ${s.sourceId}, uid: ${s.uid}',
        );
      }

      // Final cleanup
      lsl.destroy();
    });
    test('debug pullSample issue', () async {
      final lsl = LSL();

      // Create stream info with unique name and source ID
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      final oStreamInfo = await lsl.createStreamInfo(
        streamName: 'DebugTestStream_$testId',
        sourceId: 'DartLSL_$testId', // Add unique source ID
        channelCount: 2,
        channelFormat: LSLChannelFormat.float32,
        sampleRate: 0.5,
      );

      // Create outlet
      print('Creating outlet...');
      final outlet = await lsl.createOutlet(
        streamInfo: oStreamInfo,
        chunkSize: 0,
        maxBuffer: 1,
      );

      // Push a distinctive sample
      print('Pushing sample [99.0, 88.0]...');
      final pushResult = await outlet.pushSample([99.0, 88.0]);
      print('Push result: $pushResult');

      // Wait longer to ensure the sample is processed
      print('Waiting for sample to be processed...');
      await Future.delayed(Duration(milliseconds: 200));

      // Resolve streams
      print('Resolving streams...');
      final streams = await lsl.resolveStreams(waitTime: 0.5);
      print('Found ${streams.length} streams');

      for (final s in streams) {
        print(
          'Found stream: ${s.streamName}, ${s.streamType.value}, channels: ${s.channelCount}',
        );
      }

      // Find our specific stream
      final streamInfo = streams.firstWhere(
        (s) => s.streamName == 'DebugTestStream_$testId',
        orElse: () => throw Exception('Test stream not found'),
      );

      // Create inlet
      print('Creating inlet...');
      final inlet = await lsl.createInlet(
        streamInfo: streamInfo,
        maxBufferSize: 360,
        recover: true,
      );

      // Check if samples are available
      print('Checking if samples are available...');
      final available = await inlet.samplesAvailable();
      print('Samples available: $available');

      // Push another sample in case the first one is lost
      print('Pushing another sample [77.0, 66.0]...');
      await outlet.pushSample([77.0, 66.0]);

      // Wait longer
      print('Waiting for connection and sample delivery...');
      await Future.delayed(Duration(milliseconds: 500));

      // Check again if samples are available
      final availableAfterWait = await inlet.samplesAvailable();
      print('Samples available after wait: $availableAfterWait');

      // Pull with longer timeout
      print('Pulling sample with 2 second timeout...');
      final sample = await inlet.pullSample(timeout: 2.0);
      print('Pulled sample: ${sample.data}');

      // Clean up
      outlet.destroy();
      inlet.destroy();
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
    test('fixed pullSample test', () async {
      final lsl = LSL();

      // Create stream with unique identifiers
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      final streamName = 'TestStream_$testId';
      final sourceId = 'TestSource_$testId';

      // Create stream info and outlet
      final streamInfo = await lsl.createStreamInfo(
        streamName: streamName,
        sourceId: sourceId,
        channelCount: 2,
        channelFormat: LSLChannelFormat.float32,
      );

      final outlet = await lsl.createOutlet(
        streamInfo: streamInfo,
        chunkSize: 0,
        maxBuffer: 1,
      );

      // Push a sample
      await outlet.pushSample([99.0, 88.0]);

      // Allow time for the network to register
      await Future.delayed(Duration(seconds: 1));

      // Resolve all streams
      final streams = await lsl.resolveStreams(waitTime: 1.0, maxStreams: 10);

      // Find our specific stream - use only the first matching one
      final matchingStreams =
          streams
              .where(
                (s) => s.streamName == streamName && s.sourceId == sourceId,
              )
              .toList();

      print('Found ${matchingStreams.length} matching streams');
      expect(
        matchingStreams.isNotEmpty,
        isTrue,
        reason: 'No matching streams found',
      );

      // Create inlet with the first matching stream
      final inlet = await lsl.createInlet(
        streamInfo: matchingStreams.first,
        maxBufferSize: 360,
        recover: false, // Important! Don't try to auto-recover
      );

      // Push more samples to ensure something is available
      for (int i = 0; i < 5; i++) {
        await outlet.pushSample([77.0 + i, 66.0 + i]);
        await Future.delayed(Duration(milliseconds: 100));
      }

      // Pull sample with timeout
      final sample = await inlet.pullSample(timeout: 3.0);
      print('Pulled sample: ${sample.data}');

      // Verify we got data
      expect(sample.data.isNotEmpty, isTrue, reason: 'No sample data received');

      // Clean up
      outlet.destroy();
      inlet.destroy();
      lsl.destroy();
    });
    test('direct LSL test - no isolates', () async {
      // Create stream info directly
      final streamInfo = LSLStreamInfo(
        streamName: 'DirectTestStream',
        sourceId: 'DirectTestSource',
        channelCount: 2,
        channelFormat: LSLChannelFormat.float32,
      );
      streamInfo.create();

      // Create outlet directly
      final outlet = LSLStreamOutlet(
        streamInfo: streamInfo,
        chunkSize: 0,
        maxBuffer: 1,
      );
      outlet.create();

      // Push a sample
      await outlet.pushSample([99.0, 88.0]);

      // Create inlet directly
      final inlet = LSLStreamInlet<double>(
        streamInfo,
        maxBufferSize: 360,
        maxChunkLength: 0,
        recover: false,
      );
      inlet.create();

      // Push more samples
      await outlet.pushSample([77.0, 66.0]);

      // Pull a sample
      final sample = await inlet.pullSample(timeout: 2.0);
      print('Direct test pulled sample: ${sample.data}');

      // Clean up
      inlet.destroy();
      outlet.destroy();
    });
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
