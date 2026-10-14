export 'package:lsl_core/lsl_core.dart'
    show runPreciseInterval, runPreciseIntervalAsync, dartStopwatch;

import 'package:liblsl/native_liblsl.dart' show lsl_local_clock;

class LSLStopwatch implements Stopwatch {
  const LSLStopwatch();

  static final int _frequency = 1000000; // Microseconds

  @override
  int get frequency => _frequency;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void reset() {}

  @override
  int get elapsedTicks => _lslClockMicros;

  // Convert lsl_local_clock (double in seconds) to microseconds (int)
  int get _lslClockMicros => (lsl_local_clock() * 1e6).round();

  @override
  bool get isRunning => true;

  @override
  Duration get elapsed => Duration(microseconds: _lslClockMicros);

  @override
  int get elapsedMilliseconds => _lslClockMicros ~/ 1000;

  @override
  int get elapsedMicroseconds => _lslClockMicros;
}

const LSLStopwatch lslStopwatch = LSLStopwatch();
