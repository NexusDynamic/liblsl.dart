import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

/// Memory-safety and lifecycle regression tests.
///
/// The string push/pull paths used to leak one native allocation per channel
/// per sample (push: UTF-8 copies never freed; pull: liblsl-allocated strings
/// never released via lsl_destroy_string). The RSS-bounded loop below leaked
/// tens of MB before the fix, so a generous threshold still catches a
/// regression without being flaky.
void main() {
  setUpAll(() {
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1',
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLLeakTestSession',
      unicastMinRTT: 0.1,
      multicastMinRTT: 0.1,
      portRange: 64,
      watchdogCheckInterval: 600.0,
      sendSocketBufferSize: 1024,
      receiveSocketBufferSize: 1024,
      outletBufferReserveMs: 2000,
      inletBufferReserveMs: 2000,
    );
    LSL.setConfigContent(apiConfig);
  });

  group('lifecycle safety', () {
    test('repeated outlet create/destroy (direct) does not crash', () async {
      for (int i = 0; i < 50; i++) {
        final info = await LSL.createStreamInfo(
          streamName: 'LeakLifecycleDirect_$i',
          channelCount: 4,
        );
        final outlet = await LSL.createOutlet(
          streamInfo: info,
          useIsolates: false,
        );
        outlet.pushSampleSync([1.0, 2.0, 3.0, 4.0]);
        await outlet.destroy();
        info.destroy();
      }
    });

    test('repeated outlet create/destroy (isolated) does not crash', () async {
      for (int i = 0; i < 10; i++) {
        final info = await LSL.createStreamInfo(
          streamName: 'LeakLifecycleIsolated_$i',
          channelCount: 4,
        );
        final outlet = await LSL.createOutlet(streamInfo: info);
        await outlet.pushSample([1.0, 2.0, 3.0, 4.0]);
        await outlet.destroy();
        info.destroy();
      }
    });

    test('double destroy is idempotent for outlets and inlets', () async {
      final info = await LSL.createStreamInfo(
        streamName: 'LeakDoubleDestroy',
        channelCount: 2,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        useIsolates: false,
      );
      await outlet.destroy();
      await outlet.destroy();

      final producerInfo = await LSL.createStreamInfo(
        streamName: 'LeakDoubleDestroyInlet',
        channelCount: 2,
      );
      final producer = await LSL.createOutlet(
        streamInfo: producerInfo,
        useIsolates: false,
      );
      final streams = await LSL.resolveStreamsByProperty(
        property: LSLStreamProperty.name,
        value: 'LeakDoubleDestroyInlet',
        waitTime: 5.0,
        maxStreams: 1,
      );
      final resolved = streams.firstWhereOrNull(
        (s) => s.streamName == 'LeakDoubleDestroyInlet',
      );
      expect(resolved, isNotNull);
      final inlet = await LSL.createInlet<double>(
        streamInfo: resolved!,
        useIsolates: false,
      );
      await inlet.destroy();
      await inlet.destroy();

      await producer.destroy();
      producerInfo.destroy();
      resolved.destroy();
      info.destroy();
    });

    test('destroy after failed inlet create does not throw', () async {
      // An inlet on a locally fabricated (never resolved, no producer) stream
      // fails at lsl_open_stream with a timeout error.
      final info = await LSL.createStreamInfo(
        streamName: 'LeakNoSuchStream',
        channelCount: 2,
      );
      final inlet = LSLInlet<double>(
        info,
        createTimeout: 0.1,
        useIsolates: false,
      );
      try {
        await inlet.create();
      } on LSLException {
        // expected: no producer to connect to
      }
      await inlet.destroy();
      await inlet.destroy();
      info.destroy();
    });

    test('destroy before create returns without error', () async {
      final info = await LSL.createStreamInfo(
        streamName: 'LeakNeverCreated',
        channelCount: 2,
      );
      final outlet = LSLOutlet(info, useIsolates: false);
      await outlet.destroy();
      final inlet = LSLInlet<double>(info, useIsolates: false);
      await inlet.destroy();
      info.destroy();
    });

    test('repeated empty pulls (timeout 0) do not crash', () async {
      final info = await LSL.createStreamInfo(
        streamName: 'LeakEmptyPulls',
        channelCount: 2,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        useIsolates: false,
      );
      await Future.delayed(Duration(milliseconds: 100));
      final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);
      final resolved = streams.firstWhereOrNull(
        (s) => s.streamName == 'LeakEmptyPulls',
      );
      expect(resolved, isNotNull);
      final inlet = await LSL.createInlet<double>(
        streamInfo: resolved!,
        useIsolates: false,
      );
      for (int i = 0; i < 1000; i++) {
        final sample = inlet.pullSampleSync(timeout: 0.0);
        expect(sample.timestamp, 0);
      }
      await inlet.destroy();
      await outlet.destroy();
      resolved.destroy();
      info.destroy();
    });
  });

  group('string stream memory', () {
    test('string push/pull round-trip has bounded RSS growth', () async {
      const int iterations = 10000;
      const int channels = 2;
      // ~1 KiB per channel; before the leak fix this loop leaked
      // ~2 * iterations * channels * 1 KiB ≈ 40 MiB (push + pull sides).
      final String payload = 'x' * 1024;

      final info = await LSL.createStreamInfo(
        streamName: 'LeakStringStream',
        channelCount: channels,
        channelFormat: LSLChannelFormat.string,
        sampleRate: LSL_IRREGULAR_RATE,
        streamType: LSLContentType.markers,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        useIsolates: false,
      );
      await Future.delayed(Duration(milliseconds: 100));
      final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);
      final resolved = streams.firstWhereOrNull(
        (s) => s.streamName == 'LeakStringStream',
      );
      expect(resolved, isNotNull);
      final inlet = await LSL.createInlet<String>(
        streamInfo: resolved!,
        useIsolates: false,
      );

      // Warm up buffers/allocator before measuring.
      for (int i = 0; i < 100; i++) {
        outlet.pushSampleSync([payload, payload]);
      }
      int drained = 0;
      while (inlet.pullSampleSync(timeout: 0.5).isNotEmpty) {
        drained++;
      }
      expect(drained, greaterThan(0));

      final int rssBefore = ProcessInfo.currentRss;
      int received = 0;
      for (int i = 0; i < iterations; i++) {
        outlet.pushSampleSync([payload, payload]);
        final sample = inlet.pullSampleSync(timeout: 0.5);
        if (sample.isNotEmpty) {
          received++;
          expect(sample[0].length, payload.length);
        }
      }
      // Drain anything still buffered so pull-side allocations are exercised.
      while (inlet.pullSampleSync(timeout: 0.2).isNotEmpty) {
        received++;
      }
      final int rssAfter = ProcessInfo.currentRss;
      final int growthMiB = (rssAfter - rssBefore) ~/ (1024 * 1024);

      expect(received, greaterThan(iterations ~/ 2));
      // Generous bound: the pre-fix leak was ~40 MiB deterministic growth.
      expect(
        growthMiB,
        lessThan(25),
        reason:
            'RSS grew ${growthMiB}MiB over $iterations string samples — '
            'possible native memory leak in string push/pull',
      );

      await inlet.destroy();
      await outlet.destroy();
      resolved.destroy();
      info.destroy();
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
