import 'dart:math' as math;

import 'package:signal_core/signal_core.dart';
import 'package:test/test.dart';

void main() {
  const fs = 500.0;
  final rng = math.Random(2);
  List<double> noise(double amp, {double line = 0, double dc = 0}) => [
    for (var i = 0; i < 500; i++)
      dc +
          amp * (rng.nextDouble() - 0.5) +
          line * math.sin(2 * math.pi * 50 * i / fs),
  ];

  test('flags line noise, high amplitude and flat channels', () {
    final t = QualityTracker(smoothing: 1);
    final q = t.update([
      noise(10, dc: 5000), // fine despite the offset
      noise(10),
      noise(10),
      noise(10, line: 40), // line noise
      noise(200), // too large
      noise(0, dc: 3), // flat
      noise(10),
    ], fs);
    expect(q[0].flag, ChannelFlag.ok);
    expect(q[1].flag, ChannelFlag.ok);
    expect(q[3].flag, ChannelFlag.bad);
    expect(q[3].lineNoise, greaterThan(0.5));
    expect(q[4].flag, ChannelFlag.bad);
    expect(q[5].flat, isTrue);
    expect(q[5].flag, ChannelFlag.bad);
    expect(q[3].reason, contains('line noise'));
  });

  test('excluded channels do not count towards the median', () {
    final t = QualityTracker(smoothing: 1);
    // Half the channels are noisy: with them in the median nothing stands
    // out; left out, they are flagged.
    final chans = [
      noise(10),
      noise(10),
      noise(10),
      noise(100),
      noise(100),
      noise(100),
    ];
    expect(t.update(chans, fs).where((x) => x.flag != ChannelFlag.ok), isEmpty);
    final q = t.update(chans, fs, exclude: {4, 5});
    expect(q[3].flag, ChannelFlag.bad);
  });
}
