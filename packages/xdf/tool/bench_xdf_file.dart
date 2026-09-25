// Writes a large synthetic recording (if missing) and times indexing it
// with XdfFile, here and in a background isolate.
//
//   dart run tool/bench_xdf_file.dart /tmp/big.xdf
import 'dart:io';
import 'dart:math' as math;

import 'package:signal_core/signal_core.dart';
import 'package:xdf/xdf.dart';

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? 'big.xdf' : args.first;
  if (!File(path).existsSync()) {
    final sw = Stopwatch()..start();
    final w = XdfWriter(File(path).openWrite());
    const ch = 32, rate = 500, seconds = 3600, block = 32;
    w.addStream(
      1,
      XdfStreamInfo(name: 'EEG', type: 'EEG', channelCount: ch, nominalRate: 500),
    );
    w.addStream(
      2,
      XdfStreamInfo(name: 'Markers', channelCount: 1, format: XdfFormat.string),
    );
    for (var i = 0; i < rate * seconds; i += block) {
      final ts = [for (var k = 0; k < block; k++) 100 + (i + k) / rate];
      final v = <double>[
        for (var k = 0; k < block; k++)
          for (var c = 0; c < ch; c++)
            50 * math.sin(2 * math.pi * 10 * (i + k) / rate) + c,
      ];
      w.writeSamples(1, ts, v);
      if (i % (rate * 10) < block) {
        w.writeStrings(2, [ts.first], ['t=${i ~/ rate}']);
        w.writeClockOffset(1, ts.first, 0.001);
      }
    }
    await w.close();
    print('wrote ${File(path).lengthSync() >> 20} MB in ${sw.elapsed}');
  }
  final mb = File(path).lengthSync() / (1 << 20);
  var sw = Stopwatch()..start();
  final f = await XdfFile.open(ByteSource.path(path));
  await f.indexed;
  print(
    'this isolate: ${sw.elapsed} '
    '(${(mb / sw.elapsed.inMilliseconds * 1000).toStringAsFixed(0)} MB/s)',
  );
  sw = Stopwatch()..start();
  final env = await f.envelope(
    EnvelopeRequest(
      channels: [for (var c = 0; c < 32; c++) ChannelRef(0, c)],
      t0: 0,
      t1: f.duration,
      bins: 2000,
    ),
  );
  print('overview of 32 ch: ${sw.elapsed} (${env.length} bins)');
  sw = Stopwatch()..start();
  await f.read(
    ReadRequest(
      channels: [for (var c = 0; c < 32; c++) ChannelRef(0, c)],
      t0: 1800,
      t1: 1810,
      derived: const DerivedSpec(highpass: 0.5, notch: 50),
    ),
  );
  print('filtered 10 s window: ${sw.elapsed}');
  await f.close();
  sw = Stopwatch()..start();
  final b = await XdfFile.openInBackground(ByteSourceSpec.path(path));
  await b.indexed;
  print('background isolate: ${sw.elapsed}');
  await b.close();
}
