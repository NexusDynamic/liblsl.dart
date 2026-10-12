import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_timing/src/pointer_clock.dart';

void main() {
  test('the offset to the clock behind touch time stamps is measured', () {
    final watch = Stopwatch()..start();
    double clock() => watch.elapsedMicroseconds / 1e6;
    final first = PointerClock.measure(clock);
    if (Platform.isWindows) {
      expect(first, isNull);
      return;
    }
    final second = PointerClock.measure(clock)!;
    expect(first!.uncertainty, inInclusiveRange(0, 1e-3));
    // Two clocks that run at the same rate: the same offset both times.
    expect(second.offset, closeTo(first.offset, 1e-3));
    // A stamp taken now reads as now.
    final stamp = Duration(
      microseconds: ((clock() - second.offset) * 1e6).round(),
    );
    expect(second.map(stamp), closeTo(clock(), 1e-3));
    expect(second.toJson().keys, ['clock', 'offset', 'uncertainty']);
  });
}
