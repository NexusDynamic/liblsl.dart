import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';

void main() {
  group('sweepOriginOf', () {
    test('is the start of the window the time falls in', () {
      expect(sweepOriginOf(0, 10), 0);
      expect(sweepOriginOf(9.999, 10), 0);
      expect(sweepOriginOf(10, 10), 10);
      expect(sweepOriginOf(23.4, 10), 20);
      expect(sweepOriginOf(7.3, 2.5), 5);
    });
  });

  group('sweepFetchRange', () {
    test('covers the newest window on a fixed bin grid', () {
      const w = 10.0, bins = 1000;
      const step = w / bins;
      final (a, b, n) = sweepFetchRange(123.4567, w, bins);
      expect(n, bins + 1);
      expect(a, lessThanOrEqualTo(123.4567 - w));
      expect(a, greaterThan(123.4567 - w - step));
      expect(b, greaterThanOrEqualTo(123.4567));
      expect((b - a) / n, closeTo(step, 1e-9));
      // On the grid: a whole number of steps from zero.
      expect((a / step) - (a / step).round(), closeTo(0, 1e-6));
    });

    test('keeps the same bins for ends within one bin', () {
      const w = 4.0, bins = 400;
      final first = sweepFetchRange(50.0012, w, bins);
      final second = sweepFetchRange(50.0087, w, bins);
      expect(second.$1, closeTo(first.$1, 1e-9));
    });
  });

  test('ViewSettings sweep by default and copy the live display', () {
    const s = ViewSettings();
    expect(s.liveDisplay, LiveDisplay.sweep);
    expect(
      s.copyWith(liveDisplay: LiveDisplay.scroll).liveDisplay,
      LiveDisplay.scroll,
    );
    expect(s.copyWith(windowS: 5).liveDisplay, LiveDisplay.sweep);
  });
}
