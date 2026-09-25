import 'dart:async';
import 'dart:typed_data';

import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

/// Tests for explicit timestamps and pushthrough on sample and chunk pushes
/// (the `lsl_push_sample_*t`/`*tp` and `lsl_push_chunk_*tp`/`*tnp` families)
/// in direct and isolate modes.
void main() {
  setUpAll(() {
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1',
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLPushTimestampTestSession',
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

  int streamCounter = 0;

  /// Creates a connected outlet/inlet pair on loopback.
  Future<(LSLOutlet, LSLInlet<T>, List<LSLStreamInfo>)> createPair<T>({
    required LSLChannelFormat format,
    int channels = 2,
    bool outletIsolates = false,
    bool inletIsolates = false,
  }) async {
    final name = 'PushTsTest_${streamCounter++}_${format.name}';
    final info = await LSL.createStreamInfo(
      streamName: name,
      channelCount: channels,
      channelFormat: format,
      sampleRate: LSL_IRREGULAR_RATE,
      streamType: LSLContentType.markers,
    );
    final outlet = await LSL.createOutlet(
      streamInfo: info,
      useIsolates: outletIsolates,
    );
    await Future.delayed(Duration(milliseconds: 100));
    final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);
    final resolved = streams.firstWhereOrNull((s) => s.streamName == name);
    expect(resolved, isNotNull, reason: 'stream $name not resolved');
    for (final s in streams) {
      if (!identical(s, resolved)) s.destroy();
    }
    final inlet = await LSL.createInlet<T>(
      streamInfo: resolved!,
      useIsolates: inletIsolates,
    );
    final found = await outlet.waitForConsumer(timeout: 5.0);
    expect(found, isTrue);
    return (outlet, inlet, [info, resolved]);
  }

  Future<void> cleanupPair(
    LSLOutlet outlet,
    LSLInlet inlet,
    List<LSLStreamInfo> infos,
  ) async {
    await inlet.destroy();
    await outlet.destroy();
    for (final info in infos) {
      info.destroy();
    }
  }

  /// Pulls one sample, retrying until [timeoutSeconds] elapse.
  Future<LSLSample<T>> pullOne<T>(
    LSLInlet<T> inlet, {
    double timeoutSeconds = 5.0,
  }) async {
    final deadline = DateTime.now().add(
      Duration(milliseconds: (timeoutSeconds * 1000).round()),
    );
    while (DateTime.now().isBefore(deadline)) {
      final sample = await inlet.pullSample(timeout: 0.5);
      if (sample.isNotEmpty) return sample;
    }
    fail('no sample arrived within ${timeoutSeconds}s');
  }

  Future<LSLChunk<T>> pullAll<T>(LSLInlet<T> inlet, int expected) async {
    final samples = <List<T>>[];
    final timestamps = <double>[];
    int errorCode = 0;
    final deadline = DateTime.now().add(Duration(seconds: 5));
    while (samples.length < expected && DateTime.now().isBefore(deadline)) {
      final chunk = await inlet.pullChunk(timeout: 0.5);
      samples.addAll(chunk.samples);
      timestamps.addAll(chunk.timestamps);
      errorCode = chunk.errorCode;
    }
    return LSLChunk<T>(samples, timestamps, errorCode);
  }

  final formats = <LSLChannelFormat, List<dynamic> Function(int)>{
    LSLChannelFormat.float32: (i) => [i + 0.5, i + 1.5],
    LSLChannelFormat.double64: (i) => [i * 1.25, i * 2.5],
    LSLChannelFormat.int8: (i) => [i, -i],
    LSLChannelFormat.int16: (i) => [i * 100, -i * 100],
    LSLChannelFormat.int32: (i) => [i * 100000, -i],
    LSLChannelFormat.int64: (i) => [i * 10000000000, -i],
    LSLChannelFormat.string: (i) => ['marker $i', 'ünïcode $i'],
  };

  /// Runs [body] with an inlet typed for [format].
  Future<void> withTypedPair(
    LSLChannelFormat format,
    bool isolates,
    Future<void> Function(LSLOutlet, LSLInlet) body,
  ) async {
    Future<void> run<T>() async {
      final (outlet, inlet, infos) = await createPair<T>(
        format: format,
        outletIsolates: isolates,
        inletIsolates: isolates,
      );
      try {
        await body(outlet, inlet);
      } finally {
        await cleanupPair(outlet, inlet, infos);
      }
    }

    switch (format) {
      case LSLChannelFormat.float32 || LSLChannelFormat.double64:
        await run<double>();
      case LSLChannelFormat.string:
        await run<String>();
      default:
        await run<int>();
    }
  }

  for (final isolates in [false, true]) {
    final mode = isolates ? 'isolated' : 'direct';

    group('pushSample timestamp/pushthrough ($mode)', () {
      for (final entry in formats.entries) {
        test('explicit timestamp round-trips (${entry.key.name})', () async {
          await withTypedPair(entry.key, isolates, (outlet, inlet) async {
            final backdated = LSL.localClock() - 10.0;
            final data = entry.value(3);
            expect(await outlet.pushSample(data, timestamp: backdated), 0);
            final sample = await pullOne(inlet);
            expect(sample.data.toList(), data);
            expect(sample.timestamp, closeTo(backdated, 1e-6));

            // *tp variant: timestamp + pushthrough.
            final backdated2 = backdated + 1.0;
            final data2 = entry.value(4);
            expect(
              await outlet.pushSample(
                data2,
                timestamp: backdated2,
                pushthrough: true,
              ),
              0,
            );
            final sample2 = await pullOne(inlet);
            expect(sample2.data.toList(), data2);
            expect(sample2.timestamp, closeTo(backdated2, 1e-6));
          });
        });
      }

      test('pushthrough without timestamp stamps "now"', () async {
        await withTypedPair(LSLChannelFormat.string, isolates, (
          outlet,
          inlet,
        ) async {
          final before = LSL.localClock();
          await outlet.pushSample(['a', 'b'], pushthrough: true);
          final sample = await pullOne(inlet);
          expect(sample.data.toList(), ['a', 'b']);
          expect(sample.timestamp, greaterThanOrEqualTo(before));
          expect(sample.timestamp, lessThanOrEqualTo(LSL.localClock()));
        });
      });

      test('pushthrough: false batches until a flushing push', () async {
        await withTypedPair(LSLChannelFormat.float32, isolates, (
          outlet,
          inlet,
        ) async {
          await outlet.pushSample([1.0, 2.0], pushthrough: false);
          await outlet.pushSample([3.0, 4.0], pushthrough: true);
          final first = await pullOne(inlet);
          final second = await pullOne(inlet);
          expect(first.data.toList(), [1.0, 2.0]);
          expect(second.data.toList(), [3.0, 4.0]);
        });
      });
    });

    group('pushChunk pushthrough ($mode)', () {
      test('per-sample timestamps + pushthrough (float32)', () async {
        await withTypedPair(LSLChannelFormat.float32, isolates, (
          outlet,
          inlet,
        ) async {
          final now = LSL.localClock();
          final timestamps = List.generate(4, (i) => now - 5.0 + i * 0.01);
          final pushed = List.generate(4, (s) => [s.toDouble(), -s * 1.0]);
          expect(
            await outlet.pushChunk(
              pushed,
              timestamps: timestamps,
              pushthrough: true,
            ),
            0,
          );
          final chunk = await pullAll(inlet, 4);
          expect(chunk.sampleCount, 4);
          for (int s = 0; s < 4; s++) {
            expect(chunk.samples[s], pushed[s]);
            expect(chunk.timestamps[s], closeTo(timestamps[s], 1e-6));
          }
        });
      });

      test('single timestamp + pushthrough (int32 typed)', () async {
        await withTypedPair(LSLChannelFormat.int32, isolates, (
          outlet,
          inlet,
        ) async {
          final ts = LSL.localClock() - 3.0;
          expect(
            await outlet.pushChunkTyped(
              Int32List.fromList([1, 2, 3, 4]),
              timestamp: ts,
              pushthrough: true,
            ),
            0,
          );
          final chunk = await pullAll(inlet, 2);
          expect(chunk.sampleCount, 2);
          expect(chunk.samples, [
            [1, 2],
            [3, 4],
          ]);
          // Irregular rate: every sample in the chunk gets the same stamp.
          for (final t in chunk.timestamps) {
            expect(t, closeTo(ts, 1e-6));
          }
        });
      });

      test('no timestamp stamps "now"', () async {
        await withTypedPair(LSLChannelFormat.double64, isolates, (
          outlet,
          inlet,
        ) async {
          final before = LSL.localClock();
          await outlet.pushChunk([
            [1.0, 2.0],
            [3.0, 4.0],
          ]);
          final chunk = await pullAll(inlet, 2);
          expect(chunk.sampleCount, 2);
          for (final t in chunk.timestamps) {
            expect(t, greaterThanOrEqualTo(before));
          }
        });
      });
    });
  }

  // Undefined-format streams carry no data (0 bytes per sample). liblsl
  // serves them, but its own receive-side parser rejects the `undefined`
  // channel format ("Invalid channel format undefined"), so no inlet can
  // consume one; this only checks that lsl_push_sample_v/vt/vtp are wired
  // up and accepted.
  for (final isolates in [false, true]) {
    test(
      'undefined-format push variants (${isolates ? 'isolated' : 'direct'})',
      () async {
        final info = await LSL.createStreamInfo(
          streamName: 'PushTsTest_${streamCounter++}_undefined',
          channelCount: 1,
          channelFormat: LSLChannelFormat.undefined,
          sampleRate: LSL_IRREGULAR_RATE,
        );
        expect(info.sampleBytes, 0);
        final outlet = await LSL.createOutlet(
          streamInfo: info,
          useIsolates: isolates,
        );
        final ts = LSL.localClock() - 7.0;
        expect(await outlet.pushSample([null]), 0);
        expect(await outlet.pushSample([null], timestamp: ts), 0);
        expect(
          await outlet.pushSample([null], timestamp: ts, pushthrough: true),
          0,
        );
        expect(await outlet.pushSample([null], pushthrough: false), 0);
        await outlet.destroy();
        info.destroy();
      },
    );
  }

  test('pushSamplePointerSync forwards timestamp', () async {
    final (outlet, inlet, infos) = await createPair<double>(
      format: LSLChannelFormat.double64,
    );
    final ts = LSL.localClock() - 2.0;
    final ptr = outlet.dataToBufferPointer([7.0, 8.0]);
    expect(outlet.pushSamplePointerSync(ptr, timestamp: ts), 0);
    final sample = await pullOne(inlet);
    expect(sample.data.toList(), [7.0, 8.0]);
    expect(sample.timestamp, closeTo(ts, 1e-6));
    await cleanupPair(outlet, inlet, infos);
  });
}
