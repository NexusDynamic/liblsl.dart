import 'dart:math' as math;

import 'types.dart';

/// How many samples one pull should ask for to take [span] of a stream at
/// [rate] Hz (an irregular stream counts as 1 Hz), and at least [min].
int pullCapacity(double rate, Duration span, {int min = 64}) =>
    math.max(min, (math.max(rate, 1) * span.inMicroseconds / 1e6).ceil());

/// How often to poll a stream at [rate] Hz: its sample period, but never
/// slower than 10 ms (the poll interval bounds receive latency) and never
/// faster than the waiting can keep up with: a busy-wait manages 100 µs, a
/// timer 1 ms.
Duration pollIntervalFor(double rate, {bool busyWait = false}) {
  final period = rate > 0 ? (1e6 / rate).round() : 10000;
  return Duration(microseconds: period.clamp(busyWait ? 100 : 1000, 10000));
}

/// Pull everything [inlet] has buffered, [max] samples at a time, handing
/// each chunk to [onChunk]: until a pull comes back with fewer than [max]
/// (nothing more waiting) or [stop] says so. Returns the samples pulled.
/// A failed pull throws.
Future<int> drainInlet(
  LslInlet inlet,
  int max,
  void Function(LslChunk chunk) onChunk, {
  bool Function()? stop,
}) async {
  var n = 0;
  while (stop?.call() != true) {
    final c = await inlet.pull(max);
    if (c.length == 0 || stop?.call() == true) break;
    onChunk(c);
    n += c.length;
    if (c.length < max) break;
  }
  return n;
}
