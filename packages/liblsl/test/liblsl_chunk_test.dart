import 'dart:async';
import 'dart:typed_data';

import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

/// Tests for the chunk push/pull API (list + TypedData forms) in direct and
/// isolate modes.
void main() {
  setUpAll(() {
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1',
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLChunkTestSession',
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
    Set<LSLTransportOptions> outletTransport = const {},
  }) async {
    final name = 'ChunkTest_${streamCounter++}_${format.name}';
    final info = await LSL.createStreamInfo(
      streamName: name,
      channelCount: channels,
      channelFormat: format,
      sampleRate: format == LSLChannelFormat.string
          ? LSL_IRREGULAR_RATE
          : 250.0,
      streamType: LSLContentType.eeg,
    );
    final outlet = await LSL.createOutlet(
      streamInfo: info,
      transportOptions: outletTransport,
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

  /// Pulls until [expected] samples arrive or the deadline passes.
  Future<LSLChunk<T>> pullAll<T>(
    LSLInlet<T> inlet,
    int expected, {
    bool sync = true,
  }) async {
    final samples = <List<T>>[];
    final timestamps = <double>[];
    int errorCode = 0;
    final deadline = DateTime.now().add(Duration(seconds: 5));
    while (samples.length < expected && DateTime.now().isBefore(deadline)) {
      final chunk = sync
          ? inlet.pullChunkSync(timeout: 0.5)
          : await inlet.pullChunk(timeout: 0.5);
      samples.addAll(chunk.samples);
      timestamps.addAll(chunk.timestamps);
      errorCode = chunk.errorCode;
    }
    return LSLChunk<T>(samples, timestamps, errorCode);
  }

  group('direct mode round-trips', () {
    final numericFormats = {
      LSLChannelFormat.float32: (int s, int c) => (s * 10 + c).toDouble(),
      LSLChannelFormat.double64: (int s, int c) => (s * 10 + c) * 1.5,
      LSLChannelFormat.int8: (int s, int c) => (s * 10 + c) % 128,
      LSLChannelFormat.int16: (int s, int c) => s * 100 + c,
      LSLChannelFormat.int32: (int s, int c) => s * 1000 + c,
      LSLChannelFormat.int64: (int s, int c) => s * 100000 + c,
    };

    for (final entry in numericFormats.entries) {
      test('pushChunk/pullChunk round-trip (${entry.key.name})', () async {
        final isFloat =
            entry.key == LSLChannelFormat.float32 ||
            entry.key == LSLChannelFormat.double64;
        const sampleCount = 12;
        const channels = 2;

        Future<void> run<T>() async {
          final (outlet, inlet, infos) = await createPair<T>(
            format: entry.key,
            channels: channels,
          );
          final pushed = List.generate(
            sampleCount,
            (s) => List.generate(channels, (c) => entry.value(s, c)),
          );
          final result = outlet.pushChunkSync(pushed);
          expect(result, 0);

          final chunk = await pullAll<T>(inlet, sampleCount);
          expect(chunk.sampleCount, sampleCount);
          for (int s = 0; s < sampleCount; s++) {
            for (int c = 0; c < channels; c++) {
              expect(chunk.samples[s][c], pushed[s][c]);
            }
          }
          // Timestamps must be non-decreasing.
          for (int s = 1; s < chunk.timestamps.length; s++) {
            expect(
              chunk.timestamps[s],
              greaterThanOrEqualTo(chunk.timestamps[s - 1]),
            );
          }
          await cleanupPair(outlet, inlet, infos);
        }

        if (isFloat) {
          await run<double>();
        } else {
          await run<int>();
        }
      });
    }

    test('string pullChunk works with pushSample producer', () async {
      final (outlet, inlet, infos) = await createPair<String>(
        format: LSLChannelFormat.string,
        channels: 2,
      );
      for (int i = 0; i < 5; i++) {
        outlet.pushSampleSync(['a$i', 'b$i']);
      }
      final chunk = await pullAll<String>(inlet, 5);
      expect(chunk.sampleCount, 5);
      for (int s = 0; s < 5; s++) {
        expect(chunk.samples[s], ['a$s', 'b$s']);
      }
      await cleanupPair(outlet, inlet, infos);
    });

    test('string pushChunk throws LSLException', () async {
      final (outlet, inlet, infos) = await createPair<String>(
        format: LSLChannelFormat.string,
        channels: 1,
      );
      expect(
        () => outlet.pushChunkSync([
          ['x'],
        ]),
        throwsA(isA<LSLException>()),
      );
      await cleanupPair(outlet, inlet, infos);
    });

    test('per-sample timestamps round-trip', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
      );
      final now = LSL.localClock();
      final timestamps = List.generate(4, (i) => now - 1.0 + i * 0.004);
      final pushed = List.generate(4, (s) => [s.toDouble(), s * 2.0]);
      outlet.pushChunkSync(pushed, timestamps: timestamps);

      final chunk = await pullAll<double>(inlet, 4);
      expect(chunk.sampleCount, 4);
      // Loopback without postprocessing passes timestamps through verbatim.
      for (int s = 0; s < 4; s++) {
        expect(chunk.timestamps[s], closeTo(timestamps[s], 1e-6));
      }
      await cleanupPair(outlet, inlet, infos);
    });

    test('typed push equals list push, typed pull equals list pull', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
      );
      const sampleCount = 8;
      final flat = Float32List.fromList(
        List.generate(sampleCount * 2, (i) => i.toDouble()),
      );
      expect(outlet.pushChunkTypedSync(flat), 0);

      // Collect via typed pull.
      final collected = <double>[];
      final deadline = DateTime.now().add(Duration(seconds: 5));
      while (collected.length < sampleCount * 2 &&
          DateTime.now().isBefore(deadline)) {
        final chunk = inlet.pullChunkTypedSync(timeout: 0.5);
        if (chunk.isNotEmpty) {
          expect(chunk.data, isA<Float32List>());
          collected.addAll(chunk.data as Float32List);
          expect(chunk.timestamps.length, chunk.sampleCount);
        }
      }
      expect(collected, flat);
      await cleanupPair(outlet, inlet, infos);
    });

    test('partial pulls: 10 pushed, maxSamples 4 yields 4+4+2', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
      );
      final pushed = List.generate(10, (s) => [s.toDouble(), 0.0]);
      outlet.pushChunkSync(pushed);
      // Wait until everything is buffered on the inlet side.
      final deadline = DateTime.now().add(Duration(seconds: 5));
      while (inlet.samplesAvailableSync() < 1 &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(Duration(milliseconds: 50));
      }
      await Future.delayed(Duration(milliseconds: 250));

      final sizes = <int>[];
      int total = 0;
      while (total < 10) {
        final chunk = inlet.pullChunkSync(maxSamples: 4, timeout: 1.0);
        if (chunk.isEmpty) break;
        sizes.add(chunk.sampleCount);
        total += chunk.sampleCount;
      }
      expect(total, 10);
      expect(sizes, [4, 4, 2]);
      await cleanupPair(outlet, inlet, infos);
    });

    test('chunk buffer grows on demand', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
      );
      // Small pull first (allocates small), then large push + large pull.
      expect(inlet.pullChunkSync(maxSamples: 2).isEmpty, isTrue);
      final big = List.generate(600, (s) => [s.toDouble(), s + 0.5]);
      outlet.pushChunkSync(big);
      final chunk = await pullAll<double>(inlet, 600);
      expect(chunk.sampleCount, 600);
      expect(chunk.samples.first, [0.0, 0.5]);
      expect(chunk.samples.last, [599.0, 599.5]);
      await cleanupPair(outlet, inlet, infos);
    });

    test('pullChunkPointerSync returns valid zero-copy view', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
      );
      outlet.pushChunkSync([
        [1.5, 2.5],
        [3.5, 4.5],
      ]);
      LSLChunkPointer ptr = const LSLChunkPointer(0, 0, 0, 0, 0);
      final deadline = DateTime.now().add(Duration(seconds: 5));
      while (ptr.isEmpty && DateTime.now().isBefore(deadline)) {
        ptr = inlet.pullChunkPointerSync(timeout: 0.5);
      }
      expect(ptr.sampleCount, 2);
      expect(ptr.channelCount, 2);
      expect(ptr.dataPointerAddress, isNonZero);
      expect(ptr.timestampPointerAddress, isNonZero);
      await cleanupPair(outlet, inlet, infos);
    });
  });

  group('validation', () {
    test('invalid chunk arguments throw ArgumentError', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
      );
      // Empty chunk.
      expect(() => outlet.pushChunkSync([]), throwsA(isA<ArgumentError>()));
      // Ragged inner list.
      expect(
        () => outlet.pushChunkSync([
          [1.0, 2.0],
          [3.0],
        ]),
        throwsA(isA<ArgumentError>()),
      );
      // timestamp + timestamps together.
      expect(
        () => outlet.pushChunkSync(
          [
            [1.0, 2.0],
          ],
          timestamp: 1.0,
          timestamps: [1.0],
        ),
        throwsA(isA<ArgumentError>()),
      );
      // timestamps length mismatch.
      expect(
        () => outlet.pushChunkSync(
          [
            [1.0, 2.0],
          ],
          timestamps: [1.0, 2.0],
        ),
        throwsA(isA<ArgumentError>()),
      );
      // Wrong TypedData type.
      expect(
        () => outlet.pushChunkTypedSync(Float64List.fromList([1.0, 2.0])),
        throwsA(isA<ArgumentError>()),
      );
      // Length not a multiple of channel count.
      expect(
        () => outlet.pushChunkTypedSync(Float32List.fromList([1.0, 2.0, 3.0])),
        throwsA(isA<ArgumentError>()),
      );
      await cleanupPair(outlet, inlet, infos);
    });

    test('typed pull on string stream throws UnsupportedError', () async {
      final (outlet, inlet, infos) = await createPair<String>(
        format: LSLChannelFormat.string,
        channels: 1,
      );
      outlet.pushSampleSync(['hello']);
      final deadline = DateTime.now().add(Duration(seconds: 5));
      while (inlet.samplesAvailableSync() == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(Duration(milliseconds: 50));
      }
      expect(
        () => inlet.pullChunkTypedSync(timeout: 0.5),
        throwsA(isA<UnsupportedError>()),
      );
      await cleanupPair(outlet, inlet, infos);
    });
  });

  group('isolate mode', () {
    test('pushChunk/pullChunk round-trip (float32, both isolated)', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
        outletIsolates: true,
        inletIsolates: true,
      );
      const sampleCount = 12;
      final pushed = List.generate(sampleCount, (s) => [s.toDouble(), s * 3.0]);
      expect(await outlet.pushChunk(pushed), 0);

      final chunk = await pullAll<double>(inlet, sampleCount, sync: false);
      expect(chunk.sampleCount, sampleCount);
      for (int s = 0; s < sampleCount; s++) {
        expect(chunk.samples[s], pushed[s]);
      }
      await cleanupPair(outlet, inlet, infos);
    });

    test('pushChunk/pullChunk round-trip (int32, both isolated)', () async {
      final (outlet, inlet, infos) = await createPair<int>(
        format: LSLChannelFormat.int32,
        outletIsolates: true,
        inletIsolates: true,
      );
      final pushed = List.generate(6, (s) => [s, s * 7]);
      expect(await outlet.pushChunk(pushed), 0);
      final chunk = await pullAll<int>(inlet, 6, sync: false);
      expect(chunk.sampleCount, 6);
      for (int s = 0; s < 6; s++) {
        expect(chunk.samples[s], pushed[s]);
      }
      await cleanupPair(outlet, inlet, infos);
    });

    test('string pullChunk (isolated inlet, direct outlet)', () async {
      final (outlet, inlet, infos) = await createPair<String>(
        format: LSLChannelFormat.string,
        channels: 1,
        inletIsolates: true,
      );
      for (int i = 0; i < 3; i++) {
        outlet.pushSampleSync(['msg$i']);
      }
      final chunk = await pullAll<String>(inlet, 3, sync: false);
      expect(chunk.sampleCount, 3);
      expect(chunk.samples.map((s) => s[0]), ['msg0', 'msg1', 'msg2']);
      await cleanupPair(outlet, inlet, infos);
    });

    test('cross-mode: isolated outlet typed push to direct inlet', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
        outletIsolates: true,
      );
      final flat = Float32List.fromList([1.0, 2.0, 3.0, 4.0]);
      expect(await outlet.pushChunkTyped(flat), 0);
      final chunk = await pullAll<double>(inlet, 2);
      expect(chunk.sampleCount, 2);
      expect(chunk.samples[0], [1.0, 2.0]);
      expect(chunk.samples[1], [3.0, 4.0]);
      await cleanupPair(outlet, inlet, infos);
    });

    test('per-sample timestamps round-trip (isolated)', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
        outletIsolates: true,
        inletIsolates: true,
      );
      final now = LSL.localClock();
      final timestamps = List.generate(3, (i) => now - 0.5 + i * 0.004);
      await outlet.pushChunk(
        List.generate(3, (s) => [s.toDouble(), 0.0]),
        timestamps: timestamps,
      );
      final chunk = await pullAll<double>(inlet, 3, sync: false);
      expect(chunk.sampleCount, 3);
      for (int s = 0; s < 3; s++) {
        expect(chunk.timestamps[s], closeTo(timestamps[s], 1e-6));
      }
      await cleanupPair(outlet, inlet, infos);
    });

    test('chunk push works over syncBlocking transport (isolated)', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
        outletIsolates: true,
        inletIsolates: true,
        outletTransport: {LSLTransportOptions.syncBlocking},
      );
      final pushed = List.generate(8, (s) => [s.toDouble(), s + 0.25]);
      expect(await outlet.pushChunk(pushed), 0);
      final chunk = await pullAll<double>(inlet, 8, sync: false);
      expect(chunk.sampleCount, 8);
      for (int s = 0; s < 8; s++) {
        expect(chunk.samples[s], pushed[s]);
      }
      await cleanupPair(outlet, inlet, infos);
    });

    test('concurrent isolated chunk pulls throw', () async {
      final (outlet, inlet, infos) = await createPair<double>(
        format: LSLChannelFormat.float32,
        inletIsolates: true,
      );
      // Two overlapping pulls with a blocking timeout: the second must be
      // rejected while the first is in flight.
      final first = inlet.pullChunk(timeout: 1.0);
      expect(() => inlet.pullChunk(timeout: 1.0), throwsA(isA<LSLException>()));
      await first;
      await cleanupPair(outlet, inlet, infos);
    });
  });
}
