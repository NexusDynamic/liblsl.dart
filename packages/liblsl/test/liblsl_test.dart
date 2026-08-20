import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart' show FreePointerExtension;
import 'package:test/test.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, malloc;

void main() {
  setUpAll(() {
    // set up basic API config
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1', // Use loopback for testing
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLTestSession',
      unicastMinRTT: 0.1,
      multicastMinRTT: 0.1,
      portRange: 128, // bump up for concurrency
      // don't bother checking during the test
      watchdogCheckInterval: 600.0,
      sendSocketBufferSize: 1024,
      receiveSocketBufferSize: 1024,
      outletBufferReserveMs: 2000,
      inletBufferReserveMs: 2000,
    );
    LSL.setConfigContent(apiConfig);
  });
  group('LSL ffi direct', () {
    test('Check lsl library version', () {
      expect(lsl_library_version(), 117);
    });
  });
  group('LSL', () {
    test('Check lsl library version', () async {
      expect(LSL.version, 117);
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
      await outlet.destroy();
      streamInfo.destroy();
    });
    test('push a default (float) sample', () async {
      final streamInfo = await LSL.createStreamInfo(channelCount: 2);
      final outlet = await LSL.createOutlet(streamInfo: streamInfo);
      final result = await outlet.pushSample(IList([5.0, 8.0]));
      expect(result, 0); // 0 typically means success

      await outlet.destroy();
      streamInfo.destroy();
    });

    test('push a string sample', () async {
      final streamInfo = await LSL.createStreamInfo(
        channelFormat: LSLChannelFormat.string,
        channelCount: 1,
      );
      final outlet = await LSL.createOutlet(streamInfo: streamInfo);
      final result = await outlet.pushSample(IList(['Test Sample']));
      expect(result, 0);

      await outlet.destroy();
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

      await outlet.destroy();
      streamInfo.destroy();
    });
    test('outlet, resolve, inlet, pull sample', () async {
      final int testSuffix = DateTime.now().millisecondsSinceEpoch;
      final String streamName = 'TestStream_$testSuffix';
      final oStreamInfo = await LSL.createStreamInfo(
        streamName: streamName,
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

      await Future.delayed(Duration(milliseconds: 50));
      // Increased maxstreams for concurrent tests in case
      // multiple streams are found but do not match.
      final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);
      expect(streams.length, greaterThan(0));
      // Find and validate the stream
      final streamInfo = streams.firstWhereOrNull(
        (s) => s.streamName == streamName,
      );
      expect(streamInfo, isNotNull);

      // Create inlet and allow time for connection
      final inlet = await LSL.createInlet<double>(
        maxBuffer: 360,
        chunkSize: 1,
        streamInfo: streamInfo!,
        recover: false,
      );
      // After creating the inlet
      // Check how many samples are available before pulling
      () async {
        await Future.delayed(Duration(milliseconds: 100));
        await outlet.pushSample(IList([5.0, 8.0]));
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
      await outlet.pushSample(IList([5.0, 8.0]));

      completer.complete();
      //await senderFuture; // Wait for the sender to finish

      // Clean up
      await inlet.destroy();
      await outlet.destroy();
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

  group('LSL time correction', () {
    /// Brings up a loopback outlet + inlet pair and hands them to [body].
    Future<void> withPair(
      Future<void> Function(LSLOutlet outlet, LSLInlet<double> inlet) body, {
      bool useIsolates = true,
    }) async {
      final streamName = 'TCStream_${DateTime.now().microsecondsSinceEpoch}';
      final oStreamInfo = await LSL.createStreamInfo(
        streamName: streamName,
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
      await Future.delayed(const Duration(milliseconds: 50));
      final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);
      final streamInfo = streams.firstWhereOrNull(
        (s) => s.streamName == streamName,
      );
      expect(streamInfo, isNotNull);
      final inlet = await LSL.createInlet<double>(
        maxBuffer: 360,
        chunkSize: 1,
        streamInfo: streamInfo!,
        recover: false,
        useIsolates: useIsolates,
      );
      try {
        await body(outlet, inlet);
      } finally {
        await inlet.destroy();
        await outlet.destroy();
        oStreamInfo.destroy();
        for (final s in streams) {
          s.destroy();
        }
      }
    }

    for (final useIsolates in [true, false]) {
      final mode = useIsolates ? 'isolated' : 'direct';

      test('getTimeCorrectionEx agrees with getTimeCorrection ($mode)', () {
        return withPair(useIsolates: useIsolates, (outlet, inlet) async {
          final ex = await inlet.getTimeCorrectionEx(timeout: 5.0);
          final plain = await inlet.getTimeCorrection(timeout: 5.0);

          // Same underlying estimate, refreshed in the background between the
          // two calls, so this is "close" rather than "identical".
          expect(ex.offset, closeTo(plain, 0.01));
          expect(ex.offset.isFinite, isTrue);

          // Full round-trip time of the probe. Loopback, so small but not
          // zero; the bound is deliberately loose because CI machines stall.
          expect(ex.uncertainty.isFinite, isTrue);
          expect(ex.uncertainty, greaterThanOrEqualTo(0.0));
          expect(ex.uncertainty, lessThan(1.0));
          expect(ex.bound, closeTo(ex.uncertainty / 2, 1e-12));

          // The remote clock is this machine's clock on loopback, so it should
          // land near our own reading rather than at some unrelated epoch.
          expect(ex.remoteTime, closeTo(LSL.localClock(), 60.0));
        });
      });

      test('post-processing and smoothing round trip ($mode)', () {
        return withPair(useIsolates: useIsolates, (outlet, inlet) async {
          await inlet.setPostProcessing({
            LSLProcessingOptions.dejitter,
            LSLProcessingOptions.monotonize,
          });
          await inlet.setSmoothingHalftime(30.0);
          // Back to the default; the coordinator relies on ground-truth stamps.
          await inlet.setPostProcessing({LSLProcessingOptions.none});
        });
      });

      test('wasClockReset is false on a fresh inlet ($mode)', () {
        return withPair(useIsolates: useIsolates, (outlet, inlet) async {
          expect(await inlet.wasClockReset(), isFalse);
        });
      });
    }

    test('sync variants work in direct mode', () {
      return withPair(useIsolates: false, (outlet, inlet) async {
        final ex = inlet.getTimeCorrectionExSync(timeout: 5.0);
        expect(ex.offset, closeTo(inlet.getTimeCorrectionSync(), 0.01));
        expect(ex.uncertainty, greaterThanOrEqualTo(0.0));
        inlet.setPostProcessingSync({LSLProcessingOptions.none});
        inlet.setSmoothingHalftimeSync(90.0);
        expect(inlet.wasClockResetSync(), isFalse);
      });
    });

    test('sync variants are rejected in isolated mode', () {
      return withPair(useIsolates: true, (outlet, inlet) async {
        expect(
          () => inlet.getTimeCorrectionExSync(),
          throwsA(isA<LSLException>()),
        );
      });
    });
  });

  group('LSLProcessingOptions', () {
    test('flags combine bitwise', () {
      expect(<LSLProcessingOptions>{}.nativeFlags, 0);
      expect({LSLProcessingOptions.none}.nativeFlags, 0);
      expect({LSLProcessingOptions.clockSync}.nativeFlags, 1);
      expect(
        {
          LSLProcessingOptions.clockSync,
          LSLProcessingOptions.dejitter,
          LSLProcessingOptions.monotonize,
          LSLProcessingOptions.threadSafe,
        }.nativeFlags,
        15,
      );
    });

    test('round trips through fromValue', () {
      for (final option in LSLProcessingOptions.values) {
        expect(LSLProcessingOptions.fromValue(option.value), option);
        expect(LSLProcessingOptions.fromNative(option.nativeType), option);
      }
    });
  });

  group('LSLTimeCorrection', () {
    test('bound is half the uncertainty and identity is by value', () {
      const a = LSLTimeCorrection(
        offset: 1.5,
        remoteTime: 100.0,
        uncertainty: 0.004,
      );
      const b = LSLTimeCorrection(
        offset: 1.5,
        remoteTime: 100.0,
        uncertainty: 0.004,
      );
      expect(a.bound, closeTo(0.002, 1e-12));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
