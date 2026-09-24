@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';
import 'package:test/test.dart';

/// Reference values from SciPy, generated with the filters of the Python
/// viewer (`hyperscanner_viewer/filters.py`).
final _fixture =
    jsonDecode(File('test/fixtures/scipy_filters.json').readAsStringSync())
        as Map<String, Object?>;

List<double> _doubles(Object? o) => [
  for (final v in o! as List) (v as num).toDouble(),
];

void _expectClose(List<double> actual, List<double> expected, double tol) {
  expect(actual.length, expected.length);
  var worst = 0.0;
  for (var i = 0; i < actual.length; i++) {
    final d = (actual[i] - expected[i]).abs();
    if (d > worst) worst = d;
  }
  expect(worst, lessThan(tol));
}

void main() {
  final fs = (_fixture['fs']! as num).toDouble();
  final x = _doubles(_fixture['x']);

  for (final c in _fixture['cases']! as List) {
    final m = c as Map<String, Object?>;
    final hp = (m['highpass']! as num).toDouble();
    final notch = (m['notch']! as num).toDouble();
    group('high-pass $hp Hz, notch $notch Hz', () {
      final sos = Sos.display(fs, highpass: hp, notch: notch);

      test('coefficients', () {
        _expectClose(sos.coefficients, _doubles(m['sos']), 1e-12);
      });

      test('steady state', () {
        _expectClose(sos.steadyState(), _doubles(m['zi']), 1e-9);
      });

      test('filtfilt', () {
        final y = Float64List.fromList(x);
        sos.filtfilt(y, padLength: m['padlen']! as int);
        _expectClose(y, _doubles(m['filtfilt']), 1e-7);
      });

      test('causal stream filter, split across calls', () {
        final f = SosStreamFilter(sos, 1);
        final y = Float64List.fromList(x);
        f.process(0, y, to: 777);
        f.process(0, y, from: 777);
        _expectClose(y, _doubles(m['causal']), 1e-7);
      });
    });
  }

  test('averageReference leaves out excluded channels', () {
    final cols = [
      [1.0, 2.0],
      [3.0, 4.0],
      [100.0, double.nan],
    ];
    averageReference(cols, exclude: {2});
    expect(cols[0], [-1.0, -1.0]);
    expect(cols[1], [1.0, 1.0]);
    expect(cols[2][0], 98.0);
  });

  test('referenceTo one channel and a subset', () {
    final cols = [
      [1.0, 2.0],
      [3.0, 5.0],
      [5.0, double.nan],
    ];
    referenceTo(cols, [1]);
    expect(cols[0], [-2.0, -3.0]);
    expect(cols[1], [0.0, 0.0]);
    final linked = [
      [1.0, 2.0],
      [3.0, 4.0],
      [5.0, double.nan],
    ];
    referenceTo(linked, [0, 2]);
    expect(linked[1], [0.0, 2.0]); // mean of 1 and 5; then only 2
  });

  test('derived spec key and identity include referenceOf', () {
    const a = DerivedSpec(referenceOf: [0]);
    const b = DerivedSpec(referenceOf: [1]);
    expect(a == b, isFalse);
    expect(a.isIdentity, isFalse);
    expect(const DerivedSpec(referenceOf: []).isIdentity, isTrue);
  });
}
