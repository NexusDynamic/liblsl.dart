import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' show StringUtf8Pointer, malloc;
import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

/// Tests for the transport options (lsl_create_outlet_ex / lsl_create_inlet_ex)
/// wiring, including the sync/blocking transport mode.
void main() {
  setUpAll(() {
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1',
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLTransportTestSession',
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

  Future<LSLStreamInfo> resolveByName(String name) async {
    final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);
    final resolved = streams.firstWhereOrNull((s) => s.streamName == name);
    expect(resolved, isNotNull, reason: 'stream $name not resolved');
    // Free the other resolved infos we don't use.
    for (final s in streams) {
      if (!identical(s, resolved)) s.destroy();
    }
    return resolved!;
  }

  group('flag combination', () {
    test('nativeFlags ORs set members', () {
      expect(<LSLTransportOptions>{}.nativeFlags, 0);
      expect({LSLTransportOptions.bufsizeInSamples}.nativeFlags, 1);
      expect(
        {
          LSLTransportOptions.bufsizeInSamples,
          LSLTransportOptions.syncBlocking,
        }.nativeFlags,
        5,
      );
    });
  });

  group('outlet creation with transport options', () {
    for (final mode in [false, true]) {
      final modeName = mode ? 'isolated' : 'direct';
      test('single flags and combined set ($modeName)', () async {
        final optionSets = <Set<LSLTransportOptions>>[
          {LSLTransportOptions.bufsizeInSamples},
          {LSLTransportOptions.bufsizeInThousandths},
          {LSLTransportOptions.syncBlocking},
          {
            LSLTransportOptions.bufsizeInSamples,
            LSLTransportOptions.syncBlocking,
          },
        ];
        for (final options in optionSets) {
          final info = await LSL.createStreamInfo(
            streamName: 'TransportCreate_${modeName}_${options.nativeFlags}',
            channelCount: 2,
            sampleRate: 100.0,
          );
          // With bufsize-in-samples semantics keep a sane sample count.
          final outlet = await LSL.createOutlet(
            streamInfo: info,
            maxBuffer: options.contains(LSLTransportOptions.bufsizeInSamples)
                ? 1000
                : 360,
            transportOptions: options,
            useIsolates: mode,
          );
          expect(outlet.transportOptions, options);
          await outlet.destroy();
          info.destroy();
        }
      });
    }

    test(
      'syncBlocking push with no consumers returns without blocking',
      () async {
        final info = await LSL.createStreamInfo(
          streamName: 'TransportNoConsumer',
          channelCount: 2,
          sampleRate: 100.0,
        );
        final outlet = await LSL.createOutlet(
          streamInfo: info,
          transportOptions: {LSLTransportOptions.syncBlocking},
          useIsolates: false,
        );
        final sw = Stopwatch()..start();
        final result = outlet.pushSampleSync([1.0, 2.0]);
        sw.stop();
        expect(result, 0);
        // No consumers: the sync path has nobody to write to and must not hang.
        expect(sw.elapsedMilliseconds, lessThan(1000));
        await outlet.destroy();
        info.destroy();
      },
    );
  });

  group('validation', () {
    test(
      'syncBlocking + string stream throws ArgumentError (direct)',
      () async {
        final info = await LSL.createStreamInfo(
          streamName: 'TransportStringSync',
          channelCount: 1,
          channelFormat: LSLChannelFormat.string,
          sampleRate: LSL_IRREGULAR_RATE,
          streamType: LSLContentType.markers,
        );
        expect(
          () => LSL.createOutlet(
            streamInfo: info,
            transportOptions: {LSLTransportOptions.syncBlocking},
            useIsolates: false,
          ),
          throwsA(isA<ArgumentError>()),
        );
        info.destroy();
      },
    );

    test(
      'syncBlocking + string stream throws ArgumentError before isolate spawn',
      () async {
        final info = await LSL.createStreamInfo(
          streamName: 'TransportStringSyncIso',
          channelCount: 1,
          channelFormat: LSLChannelFormat.string,
          sampleRate: LSL_IRREGULAR_RATE,
          streamType: LSLContentType.markers,
        );
        final outlet = LSLOutlet(
          info,
          transportOptions: {LSLTransportOptions.syncBlocking},
          useIsolates: true,
        );
        await expectLater(outlet.create(), throwsA(isA<ArgumentError>()));
        // Validation fired before any native/isolate resource was created,
        // so destroy must be a no-op.
        await outlet.destroy();
        info.destroy();
      },
    );

    test('both bufsize flags together throw ArgumentError', () async {
      final info = await LSL.createStreamInfo(
        streamName: 'TransportBothBufsize',
        channelCount: 1,
      );
      expect(
        () => LSL.createOutlet(
          streamInfo: info,
          transportOptions: {
            LSLTransportOptions.bufsizeInSamples,
            LSLTransportOptions.bufsizeInThousandths,
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => LSL.createInlet<double>(
          streamInfo: info,
          transportOptions: {
            LSLTransportOptions.bufsizeInSamples,
            LSLTransportOptions.bufsizeInThousandths,
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
      info.destroy();
    });
  });

  group('syncBlocking round-trip', () {
    for (final mode in [false, true]) {
      final modeName = mode ? 'isolated' : 'direct';
      test(
        'float32 samples arrive over syncBlocking outlet ($modeName)',
        () async {
          final name = 'TransportSyncRT_$modeName';
          final info = await LSL.createStreamInfo(
            streamName: name,
            channelCount: 2,
            sampleRate: 100.0,
          );
          final outlet = await LSL.createOutlet(
            streamInfo: info,
            transportOptions: {LSLTransportOptions.syncBlocking},
            useIsolates: mode,
          );
          await Future.delayed(Duration(milliseconds: 100));

          final resolved = await resolveByName(name);
          final inlet = await LSL.createInlet<double>(
            streamInfo: resolved,
            transportOptions: {
              LSLTransportOptions.bufsizeInSamples,
              LSLTransportOptions.syncBlocking,
            },
            maxBuffer: 1000,
            useIsolates: mode,
          );
          final consumerFound = await outlet.waitForConsumer(timeout: 5.0);
          expect(consumerFound, isTrue);

          for (int i = 0; i < 10; i++) {
            await outlet.pushSample([i.toDouble(), (i * 2).toDouble()]);
          }
          int received = 0;
          final deadline = DateTime.now().add(Duration(seconds: 5));
          while (received < 10 && DateTime.now().isBefore(deadline)) {
            final sample = await inlet.pullSample(timeout: 0.5);
            if (sample.isNotEmpty) {
              expect(sample[1], sample[0] * 2);
              received++;
            }
          }
          expect(received, 10);

          await inlet.destroy();
          await outlet.destroy();
          resolved.destroy();
          info.destroy();
        },
      );
    }
  });

  group('numeric locale', () {
    // glibc and bionic use 1 for LC_NUMERIC, the BSDs (macOS, iOS) use 4.
    final lcNumeric = Platform.isLinux || Platform.isAndroid ? 1 : 4;
    Pointer<Char> Function(int, Pointer<Char>)? setlocale;
    double Function(Pointer<Char>, Pointer<Pointer<Char>>)? strtod;

    /// Switches LC_NUMERIC to a locale with a decimal comma, as a GUI toolkit
    /// calling `setlocale(LC_ALL, "")` does on such a system. False when none
    /// is installed.
    bool useCommaLocale() {
      if (Platform.isWindows) return false;
      final libc = DynamicLibrary.process();
      setlocale = libc
          .lookupFunction<
            Pointer<Char> Function(Int, Pointer<Char>),
            Pointer<Char> Function(int, Pointer<Char>)
          >('setlocale');
      strtod = libc
          .lookupFunction<
            Double Function(Pointer<Char>, Pointer<Pointer<Char>>),
            double Function(Pointer<Char>, Pointer<Pointer<Char>>)
          >('strtod');
      final probe = '1.5'.toNativeUtf8().cast<Char>();
      try {
        for (final name in ['de_DE.UTF-8', 'da_DK.UTF-8', 'fr_FR.UTF-8']) {
          final locale = name.toNativeUtf8().cast<Char>();
          final set = setlocale!(lcNumeric, locale);
          malloc.free(locale);
          if (set != nullptr && strtod!(probe, nullptr) == 1.0) return true;
        }
        return false;
      } finally {
        malloc.free(probe);
      }
    }

    tearDown(() {
      final reset = setlocale;
      if (reset == null) return;
      final c = 'C'.toNativeUtf8().cast<Char>();
      reset(lcNumeric, c);
      malloc.free(c);
    });

    test('syncBlocking round-trip under a decimal-comma locale', () async {
      if (!useCommaLocale()) {
        markTestSkipped('no decimal-comma locale installed');
        return;
      }
      // liblsl read "1.1" as protocol 1 under such a locale, so the inlet
      // asked for the legacy feed, which a syncBlocking outlet cannot serve.
      const name = 'TransportSyncLocale';
      final info = await LSL.createStreamInfo(
        streamName: name,
        channelCount: 2,
        sampleRate: 0.5,
        channelFormat: LSLChannelFormat.double64,
      );
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        transportOptions: {LSLTransportOptions.syncBlocking},
        useIsolates: false,
      );
      await Future.delayed(Duration(milliseconds: 100));

      final resolved = await resolveByName(name);
      expect(resolved.protocolVersion, info.protocolVersion);
      expect(resolved.sampleRate, 0.5);

      final inlet = await LSL.createInlet<double>(
        streamInfo: resolved,
        useIsolates: false,
      );
      expect(await outlet.waitForConsumer(timeout: 5.0), isTrue);

      for (int i = 0; i < 10; i++) {
        outlet.pushSampleSync([i.toDouble(), i + 0.5]);
      }
      int received = 0;
      final deadline = DateTime.now().add(Duration(seconds: 5));
      while (received < 10 && DateTime.now().isBefore(deadline)) {
        final sample = inlet.pullSampleSync(timeout: 0.5);
        if (sample.isNotEmpty) {
          expect(sample[1], sample[0] + 0.5);
          received++;
        }
      }
      expect(received, 10);

      await inlet.destroy();
      await outlet.destroy();
      resolved.destroy();
      info.destroy();
    });
  });
}
