import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';
import 'package:test/test.dart';
import 'package:xdf/xdf.dart';

/// Collects written bytes.
class _Bytes implements Sink<List<int>> {
  final builder = BytesBuilder();
  @override
  void add(List<int> data) => builder.add(data);
  @override
  void close() {}
}

const _big = (1 << 60) + 1;
const _third = 1 / 3;

/// A recording whose values a 32-bit float (or a double) cannot hold:
/// 1: double64 at 100 Hz, 2 channels: `i + 1/3` and `-i / 3e7`
/// 2: int64 at 100 Hz: `2^60 + 1 + i`
/// 3: int16 at 100 Hz: `-32768 + i`
/// 4: 3-channel string markers
/// 5: irregular int64: `2^60 + 1 + i`
Uint8List _recording() {
  final out = _Bytes();
  final w = XdfWriter(out);
  XdfStreamInfo info(String name, LSLChannelFormat f, int ch, double rate) =>
      XdfStreamInfo(name: name, channelCount: ch, nominalRate: rate, format: f);
  w.addStream(1, info('doubles', LSLChannelFormat.double64, 2, 100));
  w.addStream(2, info('longs', LSLChannelFormat.int64, 1, 100));
  w.addStream(3, info('shorts', LSLChannelFormat.int16, 1, 100));
  w.addStream(4, info('words', LSLChannelFormat.string, 3, 0));
  w.addStream(5, info('events', LSLChannelFormat.int64, 1, 0));
  for (var block = 0; block < 4; block++) {
    final ts = [for (var i = 0; i < 50; i++) 10 + (block * 50 + i) / 100];
    final idx = [for (var i = 0; i < 50; i++) block * 50 + i];
    w.writeSamples(1, ts, [
      for (final i in idx) ...[i + _third, -i / 3e7],
    ]);
    w.writeSamples(2, ts, [for (final i in idx) _big + i]);
    w.writeSamples(3, ts, [for (final i in idx) -32768 + i]);
    w.writeStrings(4, [ts.first], ['a$block', 'b$block', 'ç$block']);
    w.writeSamples(5, [ts.first], [_big + block]);
  }
  w.close();
  return out.builder.takeBytes();
}

void main() {
  late Uint8List bytes;
  setUpAll(() => bytes = _recording());

  Future<XdfFile> open([SamplePrecision p = SamplePrecision.exact]) async {
    final f = await XdfFile.open(
      ByteSource.bytes(bytes),
      options: XdfFileOptions(precision: p),
    );
    await f.indexed;
    return f;
  }

  XdfStreamIndex named(XdfFile f, String n) =>
      f.streams.firstWhere((s) => s.info.name == n);

  test('views are exact by default', () async {
    final f = await open();
    final d = named(f, 'doubles');
    final w = await f.read(
      ReadRequest(
        channels: [ChannelRef(d.slot, 0), ChannelRef(d.slot, 1)],
        t0: d.t0,
        t1: d.t1,
      ),
    );
    expect(w.channels.first, isA<Float64List>());
    expect(w.channels[0].take(3), [_third, 1 + _third, 2 + _third]);
    expect(w.channels[1][3], -3 / 3e7);
    final s = named(f, 'shorts');
    final ws = await f.read(
      ReadRequest(channels: [ChannelRef(s.slot, 0)], t0: s.t0, t1: s.t1),
    );
    expect(ws.channels.single.take(2), [-32768, -32767]);
    final e = f.events(named(f, 'words').slot);
    expect(e.strings, [
      ['a0', 'a1', 'a2', 'a3'],
      ['b0', 'b1', 'b2', 'b3'],
      ['ç0', 'ç1', 'ç2', 'ç3'],
    ]);
    await f.close();
  });

  test('int64 beyond 2^53 is flagged in views and exact on request', () async {
    final f = await open();
    final l = named(f, 'longs');
    expect(l.roundedValues, isTrue);
    expect(named(f, 'shorts').roundedValues, isFalse);
    final c = await f.exactSamples(l.slot, l.t0, l.t1);
    expect(c.typed, isA<Int64List>());
    expect(c.length, 200);
    expect((c.typed! as Int64List).take(3), [_big, _big + 1, _big + 2]);
    expect(c.times[1] - c.times[0], closeTo(0.01, 1e-9));
    final events = await f.exactSamples(named(f, 'events').slot, 0, 100);
    expect(events.typed, [_big, _big + 1, _big + 2, _big + 3]);
    await f.close();
  });

  test('exact samples of a time range, in their own format', () async {
    final f = await open();
    final d = named(f, 'doubles');
    final c = await f.exactSamples(d.slot, d.t0 + 0.5, d.t0 + 1);
    expect(c.length, 50);
    expect(c.typed, isA<Float64List>());
    expect(c.typed! as Float64List, hasLength(100));
    expect((c.typed! as Float64List).first, 50 + _third);
    final w = await f.exactSamples(named(f, 'words').slot, 0, 100);
    expect(w.strings!.take(4), ['a0', 'b0', 'ç0', 'a1']);
    final s = await f.exactSamples(named(f, 'shorts').slot, 0, 100);
    expect(s.typed, isA<Int16List>());
    await f.close();
  });

  test('32-bit storage only when asked for', () async {
    final f = await open(SamplePrecision.compact);
    final d = named(f, 'doubles');
    final w = await f.read(
      ReadRequest(channels: [ChannelRef(d.slot, 0)], t0: d.t0, t1: d.t1),
    );
    expect(w.channels.single, isA<Float32List>());
    expect(w.channels.single[0], isNot(_third));
    // Exact samples are exact either way.
    final c = await f.exactSamples(d.slot, d.t0, d.t0 + 0.05);
    expect((c.typed! as Float64List).first, _third);
    await f.close();
  });
}
