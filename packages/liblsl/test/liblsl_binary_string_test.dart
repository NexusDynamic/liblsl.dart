import 'dart:async';
import 'dart:typed_data';

import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

/// Tests for the binary-string (`lsl_*_buf`) API: string-stream values sent
/// as raw bytes that may contain NUL, in direct and isolate modes.
void main() {
  setUpAll(() {
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1',
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLBinaryStringTestSession',
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

  Future<(LSLOutlet, LSLInlet<String>, List<LSLStreamInfo>)> createPair({
    int channels = 2,
    bool isolates = false,
  }) async {
    final name = 'BinaryTest_${streamCounter++}';
    final info = await LSL.createStreamInfo(
      streamName: name,
      channelCount: channels,
      channelFormat: LSLChannelFormat.string,
      sampleRate: LSL_IRREGULAR_RATE,
      streamType: LSLContentType.markers,
    );
    final outlet = await LSL.createOutlet(
      streamInfo: info,
      useIsolates: isolates,
    );
    await Future.delayed(Duration(milliseconds: 100));
    final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);
    final resolved = streams.firstWhereOrNull((s) => s.streamName == name);
    expect(resolved, isNotNull, reason: 'stream $name not resolved');
    for (final s in streams) {
      if (!identical(s, resolved)) s.destroy();
    }
    final inlet = await LSL.createInlet<String>(
      streamInfo: resolved!,
      useIsolates: isolates,
    );
    expect(await outlet.waitForConsumer(timeout: 5.0), isTrue);
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

  Future<LSLSample<Uint8List>> pullOneBytes(LSLInlet inlet) async {
    final deadline = DateTime.now().add(Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final sample = await inlet.pullSampleBytes(timeout: 0.5);
      if (sample.isNotEmpty) return sample;
    }
    fail('no sample arrived within 5s');
  }

  Future<LSLChunk<Uint8List>> pullAllBytes(LSLInlet inlet, int expected) async {
    final samples = <List<Uint8List>>[];
    final timestamps = <double>[];
    final deadline = DateTime.now().add(Duration(seconds: 5));
    while (samples.length < expected && DateTime.now().isBefore(deadline)) {
      final chunk = await inlet.pullChunkBytes(maxSamples: 8, timeout: 0.5);
      samples.addAll(chunk.samples);
      timestamps.addAll(chunk.timestamps);
    }
    return LSLChunk<Uint8List>(samples, timestamps, 0);
  }

  /// Bytes including NUL and non-UTF-8 values.
  Uint8List bytes(int seed, int length) =>
      Uint8List.fromList(List.generate(length, (i) => (seed * 31 + i) % 256));

  for (final isolates in [false, true]) {
    final mode = isolates ? 'isolated' : 'direct';

    group('binary strings ($mode)', () {
      test('sample round-trip keeps NUL bytes', () async {
        final (outlet, inlet, infos) = await createPair(isolates: isolates);
        final data = [
          Uint8List.fromList([0x61, 0x00, 0x62, 0x00]),
          bytes(7, 300),
        ];
        expect(await outlet.pushSampleBytes(data), 0);
        final sample = await pullOneBytes(inlet);
        expect(sample.length, 2);
        expect(sample[0], data[0]);
        expect(sample[1], data[1]);
        await cleanupPair(outlet, inlet, infos);
      });

      test('sample timestamp + pushthrough (buft/buftp)', () async {
        final (outlet, inlet, infos) = await createPair(isolates: isolates);
        final ts = LSL.localClock() - 4.0;
        await outlet.pushSampleBytes([bytes(1, 3), bytes(2, 0)], timestamp: ts);
        await outlet.pushSampleBytes(
          [bytes(3, 5), bytes(4, 1)],
          timestamp: ts + 1,
          pushthrough: true,
        );
        final first = await pullOneBytes(inlet);
        final second = await pullOneBytes(inlet);
        expect(first.timestamp, closeTo(ts, 1e-6));
        expect(first[0], bytes(1, 3));
        expect(first[1], isEmpty);
        expect(second.timestamp, closeTo(ts + 1, 1e-6));
        expect(second[0], bytes(3, 5));
        await cleanupPair(outlet, inlet, infos);
      });

      test('chunk round-trip with per-sample timestamps', () async {
        final (outlet, inlet, infos) = await createPair(isolates: isolates);
        final now = LSL.localClock();
        final pushed = List.generate(
          12,
          (s) => [bytes(s, s + 1), bytes(s + 100, 2)],
        );
        final timestamps = List.generate(12, (i) => now - 2.0 + i * 0.01);
        expect(
          await outlet.pushChunkBytes(
            pushed,
            timestamps: timestamps,
            pushthrough: true,
          ),
          0,
        );
        // maxSamples 8 forces more than one pull.
        final chunk = await pullAllBytes(inlet, 12);
        expect(chunk.sampleCount, 12);
        for (int s = 0; s < 12; s++) {
          expect(chunk.samples[s][0], pushed[s][0]);
          expect(chunk.samples[s][1], pushed[s][1]);
          expect(chunk.timestamps[s], closeTo(timestamps[s], 1e-6));
        }
        await cleanupPair(outlet, inlet, infos);
      });

      test('chunk variants: plain, timestamp, timestamp+pushthrough', () async {
        final (outlet, inlet, infos) = await createPair(isolates: isolates);
        final ts = LSL.localClock() - 1.0;
        await outlet.pushChunkBytes([
          [bytes(1, 1), bytes(2, 2)],
        ]);
        await outlet.pushChunkBytes([
          [bytes(3, 3), bytes(4, 4)],
        ], timestamp: ts);
        await outlet.pushChunkBytes(
          [
            [bytes(5, 5), bytes(6, 6)],
          ],
          timestamp: ts,
          pushthrough: true,
        );
        final chunk = await pullAllBytes(inlet, 3);
        expect(chunk.sampleCount, 3);
        expect(chunk.samples[0][1], bytes(2, 2));
        expect(chunk.samples[1][0], bytes(3, 3));
        expect(chunk.samples[2][1], bytes(6, 6));
        expect(chunk.timestamps[1], closeTo(ts, 1e-6));
        expect(chunk.timestamps[2], closeTo(ts, 1e-6));
        await cleanupPair(outlet, inlet, infos);
      });

      test('text pushed normally reads back as UTF-8 bytes', () async {
        final (outlet, inlet, infos) = await createPair(isolates: isolates);
        await outlet.pushSample(['héllo', '']);
        final sample = await pullOneBytes(inlet);
        expect(sample[0], [0x68, 0xc3, 0xa9, 0x6c, 0x6c, 0x6f]);
        expect(sample[1], isEmpty);
        await cleanupPair(outlet, inlet, infos);
      });

      test('pull timeout returns an empty sample/chunk', () async {
        final (outlet, inlet, infos) = await createPair(isolates: isolates);
        final sample = await inlet.pullSampleBytes(timeout: 0.05);
        expect(sample.isEmpty, isTrue);
        expect(sample.timestamp, 0);
        final chunk = await inlet.pullChunkBytes(timeout: 0.05);
        expect(chunk.isEmpty, isTrue);
        await cleanupPair(outlet, inlet, infos);
      });
    });
  }

  group('binary strings validation', () {
    test('non-string streams are rejected', () async {
      final info = await LSL.createStreamInfo(
        streamName: 'BinaryReject',
        channelCount: 1,
        channelFormat: LSLChannelFormat.float32,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        useIsolates: false,
      );
      expect(
        () => outlet.pushSampleBytesSync([Uint8List(1)]),
        throwsA(isA<LSLException>()),
      );
      expect(
        () => outlet.pushChunkBytesSync([
          [Uint8List(1)],
        ]),
        throwsA(isA<LSLException>()),
      );
      await outlet.destroy();
      info.destroy();
    });

    test('channel count mismatch is rejected', () async {
      final (outlet, inlet, infos) = await createPair();
      expect(
        () => outlet.pushSampleBytesSync([Uint8List(1)]),
        throwsA(isA<LSLException>()),
      );
      expect(
        () => outlet.pushChunkBytesSync([
          [Uint8List(1)],
        ]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => inlet.pullChunkBytesSync(maxSamples: 0),
        throwsA(isA<ArgumentError>()),
      );
      await cleanupPair(outlet, inlet, infos);
    });

    test('sync variants are rejected in isolated mode', () async {
      final (outlet, inlet, infos) = await createPair(isolates: true);
      expect(
        () => outlet.pushSampleBytesSync([Uint8List(1), Uint8List(1)]),
        throwsA(isA<LSLException>()),
      );
      expect(() => inlet.pullSampleBytesSync(), throwsA(isA<LSLException>()));
      await cleanupPair(outlet, inlet, infos);
    });
  });
}
