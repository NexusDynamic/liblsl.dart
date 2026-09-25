@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';
import 'package:test/test.dart';
import 'package:xdf/xdf.dart';

Future<XdfFile> _open(Uint8List bytes, {int readBytes = 4096}) async {
  final f = await XdfFile.open(
    ByteSource.bytes(bytes),
    options: XdfFileOptions(readBytes: readBytes),
  );
  await f.indexed;
  return f;
}

/// The largest difference between [file]'s grid times of [stream] and
/// [loaded]'s time stamps (made relative with [origin]), in samples.
double _gridError(XdfStreamIndex stream, XdfStream loaded, double origin) {
  var worst = 0.0;
  for (var i = 0; i < loaded.length; i++) {
    final t = stream.t0 + stream.ordinalOf(i) / stream.samplingRate;
    final e = (t - (loaded.timestamps[i] - origin)).abs();
    worst = math.max(worst, e * stream.samplingRate);
  }
  return worst;
}

double _origin(XdfRecording rec) => rec.streams
    .where((s) => s.length > 0)
    .map((s) => s.timestamps.first)
    .reduce(math.min);

class _Bytes implements Sink<List<int>> {
  final builder = BytesBuilder();
  @override
  void add(List<int> data) => builder.add(data);
  @override
  void close() {}
}

/// A recording with EEG (500 Hz, 4 channels, a 3 s dropout), accelerometer
/// (100 Hz, float64) and markers, written in interleaved chunks of varied
/// size, with clock offsets.
Future<Uint8List> _recording() async {
  final out = _Bytes();
  final w = XdfWriter(out);
  w.addStream(
    7,
    XdfStreamInfo(
      name: 'EEG',
      type: 'EEG',
      channelCount: 4,
      nominalRate: 500,
      channels: [
        for (final l in ['Fz', 'Cz', 'Pz', 'Oz'])
          XdfChannel(label: l, unit: 'microvolts'),
      ],
    ),
  );
  w.addStream(
    9,
    XdfStreamInfo(
      name: 'Acc',
      type: 'Accelerometer',
      channelCount: 3,
      nominalRate: 100,
      format: XdfFormat.double64,
    ),
  );
  w.addStream(
    3,
    XdfStreamInfo(
      name: 'Markers',
      type: 'Markers',
      channelCount: 1,
      format: XdfFormat.string,
    ),
  );
  final rng = math.Random(3);
  var eeg = 0, acc = 0;
  const start = 1000.0;
  for (var block = 0; block < 400; block++) {
    // EEG: 20 s, with samples 4000-5499 (3 s) lost.
    final n = 5 + rng.nextInt(40);
    final ts = <double>[], v = <double>[];
    for (var i = 0; i < n && eeg < 10000; i++, eeg++) {
      if (eeg >= 4000 && eeg < 5500) continue;
      ts.add(start + eeg / 500 + (rng.nextDouble() - 0.5) * 1e-4);
      v.addAll([
        for (var c = 0; c < 4; c++)
          100 * math.sin(2 * math.pi * 10 * eeg / 500) + c * 1000 + eeg / 100,
      ]);
    }
    if (ts.isNotEmpty) w.writeSamples(7, ts, v);
    final m = 1 + rng.nextInt(12);
    final ta = <double>[], va = <double>[];
    for (var i = 0; i < m && acc < 2000; i++, acc++) {
      ta.add(start + 0.5 + acc / 100);
      va.addAll([acc.toDouble(), -acc.toDouble(), 9.81]);
    }
    if (ta.isNotEmpty) w.writeSamples(9, ta, va);
    if (block % 40 == 0) {
      w.writeStrings(3, [start + block * 0.05], ['block $block']);
      w.writeClockOffset(7, start + block * 0.05, -0.002);
      w.writeClockOffset(9, start + block * 0.05, 0.001);
    }
  }
  await w.close();
  return out.builder.takeBytes();
}

void main() {
  for (final name in ['minimal', 'clock_resets', 'empty_streams']) {
    test('$name.xdf: times and values match loadXdf', () async {
      final bytes = File('test/fixtures/$name.xdf').readAsBytesSync();
      final rec = loadXdf(bytes);
      final f = await _open(bytes);
      final origin = _origin(rec);
      expect(f.origin, closeTo(origin, 1e-6));
      expect(f.streams, hasLength(rec.streams.length));
      for (final s in f.streams) {
        final l = rec.streams.firstWhere((x) => x.id == s.id);
        expect(s.sampleCount, l.length, reason: s.info.name);
        if (l.length == 0) continue;
        if (!s.regular) {
          final e = f.events(s.slot);
          for (var i = 0; i < l.length; i++) {
            expect(e.times[i], closeTo(l.timestamps[i] - origin, 1e-6));
            if (e.strings != null) {
              expect([for (final c in e.strings!) c[i]], l.strings[i]);
            }
          }
          continue;
        }
        final err = _gridError(s, l, origin);
        printOnFailure('${s.info.name}: grid error $err samples');
        if (s.segments.length == 1) {
          // One segment: the grid is pyxdf's dejittered line.
          expect(err, lessThan(1e-6));
        } else {
          // Each segment starts in its place; within one, the grid drifts
          // by the difference between its rate and the stream's (0.6% in
          // clock_resets.xdf, across the reset).
          for (final (start, _) in s.segments) {
            final t = s.t0 + s.ordinalOf(start) / s.samplingRate;
            final e = (t - (l.timestamps[start] - origin)).abs();
            expect(e * s.samplingRate, lessThan(1), reason: 'start $start');
          }
          expect(err, lessThan(0.005 * s.sampleCount));
        }
        final all = await f.read(
          ReadRequest(
            channels: [
              for (var c = 0; c < s.channelCount; c++) ChannelRef(s.slot, c),
            ],
            t0: s.t0,
            t1: s.t1,
          ),
        );
        for (var i = 0; i < l.length; i++) {
          final o = s.ordinalOf(i);
          for (var c = 0; c < s.channelCount; c++) {
            expect(
              all.channels[c][o],
              closeTo(l.channels[c][i], 1e-3),
              reason: '${s.info.name} sample $i channel $c',
            );
          }
        }
      }
      await f.close();
    });
  }

  test('a synthetic recording: chunks, dropout, filters, markers', () async {
    final bytes = await _recording();
    final rec = loadXdf(bytes);
    // Small reads, so chunks straddle them.
    final f = await _open(bytes, readBytes: 1000);
    final origin = _origin(rec);
    expect(f.origin, closeTo(origin, 1e-6));
    final eeg = f.streams.firstWhere((s) => s.info.name == 'EEG');
    final l = rec.stream('EEG')!;
    printOnFailure("loadXdf ${l.length}, chunks ${f.indexer.chunks.length}");
    expect(eeg.sampleCount, l.length);
    expect(eeg.segments, hasLength(2));
    expect(eeg.info.label(1), 'Cz');
    // The dropout is a gap on the grid, where pyxdf puts the samples.
    expect(eeg.ordinalOf(4000), closeTo(5500, 1));
    expect(_gridError(eeg, l, origin), lessThan(1));

    final refs = [for (var c = 0; c < 4; c++) ChannelRef(eeg.slot, c)];
    final w = await f.read(ReadRequest(channels: refs, t0: 7, t1: 12));
    expect(w.samplingRate, closeTo(500, 0.01));
    // Samples of the dropout are NaN; around it, data.
    final gapAt = ((9 - w.start) * w.samplingRate).round();
    expect(w.channels[0][gapAt].isNaN, isTrue);
    final before = ((7.5 - w.start) * w.samplingRate).round();
    expect(w.channels[1][before].isNaN, isFalse);

    // The overview comes from the pyramid.
    final env = await f.envelope(
      EnvelopeRequest(channels: refs, t0: 0, t1: f.duration, bins: 200),
    );
    expect(env.samples, isFalse);
    for (var c = 0; c < 4; c++) {
      final x = l.channels[c];
      expect(env.stats[c].min, closeTo(x.reduce(math.min), 1e-3));
      expect(env.stats[c].max, closeTo(x.reduce(math.max), 1e-3));
      expect(env.stats[c].count, l.length);
    }

    // Filtered (high-pass) windows work across chunks and the gap.
    final hp = await f.read(
      ReadRequest(
        channels: refs,
        t0: 2,
        t1: 6,
        derived: const DerivedSpec(highpass: 1),
      ),
    );
    final mid = hp.channels[2][hp.length ~/ 4];
    expect(mid.abs(), lessThan(150)); // the 2000 offset is gone

    final acc = f.streams.firstWhere((s) => s.info.name == 'Acc');
    expect(_gridError(acc, rec.stream('Acc')!, origin), lessThan(1e-6));

    final markers = f.streams.firstWhere((s) => s.info.name == 'Markers');
    final e = f.events(markers.slot);
    expect(e.strings!.single, [for (var b = 0; b < 400; b += 40) 'block $b']);
    final lm = rec.stream('Markers')!;
    for (var i = 0; i < e.length; i++) {
      expect(e.times[i], closeTo(lm.timestamps[i] - origin, 1e-6));
    }
    await f.close();
  });

  test('openInBackground answers like a file on this isolate', () async {
    const path = 'test/fixtures/clock_resets.xdf';
    final local = await _open(File(path).readAsBytesSync());
    final bg = await XdfFile.openInBackground(const ByteSourceSpec.path(path));
    await bg.indexed;
    expect(bg.complete, isTrue);
    expect(bg.duration, closeTo(local.duration, 1e-9));
    expect(bg.origin, closeTo(local.origin, 1e-9));
    expect(bg.streams, hasLength(local.streams.length));
    for (final s in local.streams) {
      final b = bg.streams[s.slot];
      expect(b.info.name, s.info.name);
      expect(b.sampleCount, s.sampleCount);
      expect(b.t0, closeTo(s.t0, 1e-9));
      expect(b.samplingRate, closeTo(s.samplingRate, 1e-9));
      if (s.regular) {
        final r = ReadRequest(
          channels: [ChannelRef(s.slot, 0)],
          t0: s.t0 + 10,
          t1: s.t0 + 20,
        );
        final a = await local.read(r);
        final c = await bg.read(r);
        expect(c.channels[0], a.channels[0]);
        final e = await bg.envelope(
          EnvelopeRequest(
            channels: [ChannelRef(s.slot, 0)],
            t0: 0,
            t1: bg.duration,
            bins: 100,
          ),
        );
        expect(
          e.min[0],
          (await local.envelope(
            EnvelopeRequest(
              channels: [ChannelRef(s.slot, 0)],
              t0: 0,
              t1: local.duration,
              bins: 100,
            ),
          )).min[0],
        );
      } else {
        expect(bg.events(s.slot).times, local.events(s.slot).times);
        expect(bg.events(s.slot).strings, local.events(s.slot).strings);
      }
    }
    await bg.close();
    await local.close();
  });
}
