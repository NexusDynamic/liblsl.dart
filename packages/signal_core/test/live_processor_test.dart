import 'dart:math' as math;
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';
import 'package:test/test.dart';

/// The whole stream processed in one go, as a reference.
List<Float64List> _batch(List<Float64List> raw, DerivedSpec spec, double fs) {
  final cols = [for (final c in raw) Float64List.fromList(c)];
  applyReference(cols, spec);
  final f = SosStreamFilter(
    Sos.display(fs, highpass: spec.highpass, notch: spec.notch),
    cols.length,
  );
  for (var c = 0; c < cols.length; c++) {
    f.process(c, cols[c]);
  }
  return cols;
}

void main() {
  const fs = 500.0;
  const n = 5000;
  final rng = math.Random(1);
  final raw = [
    for (var c = 0; c < 4; c++)
      Float64List.fromList([
        for (var i = 0; i < n; i++)
          100 * c +
              20 * math.sin(2 * math.pi * 50 * i / fs) +
              rng.nextDouble() * 10,
      ]),
  ];

  for (final spec in const [
    DerivedSpec(highpass: 0.5, notch: 50),
    DerivedSpec(highpass: 0.1, averageReference: true, exclude: {3}),
    DerivedSpec(referenceOf: [0, 1], notch: 50, meanOf: [1, 2]),
  ]) {
    test('blocks give the same result as one pass: $spec', () {
      final expected = _batch(raw, spec, fs);
      final p = LiveProcessor(spec, 4, fs, 3000);
      var t = 0;
      while (t < n) {
        final len = math.min(n - t, 1 + rng.nextInt(40));
        p.append([for (final c in raw) c.sublist(t, t + len)], t);
        t += len;
      }
      expect(p.end, n);
      expect(p.begin, n - 3000);
      final got = p.read(n - 2000, n);
      for (var c = 0; c < 4; c++) {
        for (var i = 0; i < 2000; i++) {
          // Kept as float32.
          expect(got[c][i], closeTo(expected[c][n - 2000 + i], 1e-3));
        }
      }
      if (spec.meanOf != null) {
        final m = got[4][100];
        final want = (expected[1][n - 1900] + expected[2][n - 1900]) / 2;
        expect(m, closeTo(want, 1e-3));
      }
      // Outside the buffer: NaN.
      expect(p.read(0, 10).first.every((v) => v.isNaN), isTrue);
    });
  }

  test('overlapping blocks are trimmed, gaps become NaN', () {
    final p = LiveProcessor(DerivedSpec.none, 1, fs, 100);
    p.append([
      [1.0, 2.0, 3.0],
    ], 0);
    p.append([
      [2.0, 3.0, 4.0],
    ], 1);
    expect(p.end, 4);
    p.append([
      [9.0],
    ], 6);
    final r = p.read(0, 7).first;
    expect(r.sublist(0, 4), [1.0, 2.0, 3.0, 4.0]);
    expect(r[4].isNaN && r[5].isNaN, isTrue);
    expect(r[6], 9.0);
  });
}
