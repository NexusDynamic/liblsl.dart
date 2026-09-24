// Runs on the VM and in browsers (no dart:io): 64-bit values and lengths
// work differently on the web.
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';
import 'package:test/test.dart';
import 'package:xdf/xdf.dart';

class _Bytes implements Sink<List<int>> {
  final builder = BytesBuilder();
  @override
  void add(List<int> data) => builder.add(data);
  @override
  void close() {}
}

void main() {
  test('write, load and index on this platform', () async {
    final out = _Bytes();
    final w = XdfWriter(out);
    w.addStream(
      1,
      XdfStreamInfo(
        name: 'Big',
        channelCount: 2,
        nominalRate: 1000,
        format: XdfFormat.int64,
      ),
    );
    w.addStream(
      2,
      XdfStreamInfo(name: 'M', channelCount: 1, format: XdfFormat.string),
    );
    // Values beyond 32 bits, and negative ones.
    const big = 5000000000.0;
    for (var b = 0; b < 20; b++) {
      final ts = [for (var i = 0; i < 100; i++) 10 + (b * 100 + i) / 1000];
      w.writeSamples(1, ts, [
        for (var i = 0; i < 100; i++) ...[big + b * 100 + i, -big - i],
      ]);
    }
    w.writeStrings(2, [10.5], ['half']);
    await w.close();
    final bytes = out.builder.takeBytes();

    final rec = loadXdf(bytes);
    final s = rec.stream('Big')!;
    expect(s.length, 2000);
    expect(s.channels[0][1999], big + 1999);
    expect(s.channels[1][5], -big - 5);
    expect(rec.stream('M')!.strings.single.single, 'half');

    final f = await XdfFile.open(
      ByteSource.bytes(bytes),
      options: const XdfFileOptions(readBytes: 700),
    );
    await f.indexed;
    final st = f.streams.first;
    expect(st.sampleCount, 2000);
    final win = await f.read(
      ReadRequest(channels: [ChannelRef(st.slot, 0)], t0: 0, t1: 2),
    );
    // Float32 columns: large values round, so compare loosely.
    expect(win.channels[0].last, closeTo(big + 1999, 1024));
    expect(f.events(1).strings!.single.single, 'half');
    expect(f.events(1).times.single, closeTo(0.5, 1e-9));
    await f.close();
  });
}
