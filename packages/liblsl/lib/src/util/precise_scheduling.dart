import 'dart:async';
import 'dart:io';

import 'package:liblsl/native_liblsl.dart' show lsl_local_clock;

class LSLStopwatch implements Stopwatch {
  const LSLStopwatch();

  @pragma("vm:shared")
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
final Stopwatch dartStopwatch = Stopwatch();

/// Run a callback at precise intervals.
///
/// The [callback] is called at the specified [interval] duration.
/// This function uses a busy-wait loop to ensure that the callback is executed
/// at the specified interval. In order to reduce CPU usage, it sleeps for a
/// short duration before checking the elapsed time again.
/// A [Completer] is used to signal when the loop should stop.
/// The [state] parameter can be used to pass any additional data to the
/// callback function, this keeps the state in the scope of the wrapping
/// function and allows the callback to access it without needing to pass it
/// as a parameter every time. @note that it is your job to ensure that the
/// state will not perform operations that will cause memory leaks or
/// unexpected behavior, such as accessing a closed stream or a disposed widget.
/// The [startBusyAt] parameter specifies how long before the interval the
/// function should start busy-waiting, this is the way that this function can
/// achieve a precise interval. For example if you want a callback to be called
/// with a 1Hz frequency, you can set the [interval] to 1 second and the
/// [startBusyAt] to 1 millisecond. This means that the function will use low
/// CPU usage for 999 milliseconds and then start busy-waiting for
/// 1 millisecond.
@pragma('vm:unsafe:no-bounds-checks')
void runPreciseInterval<T>(
  Duration interval,
  T Function(T state) callback, {
  required Completer<void> completer,
  dynamic state,
  Duration startBusyAt = const Duration(milliseconds: 1),
  Stopwatch? sw,
}) {
  sw ??= dartStopwatch;
  sw.start();
  int nextAwake = sw.elapsedMicroseconds;
  final bool canSleep = startBusyAt.inMicroseconds > 1000;

  for (int i = 1; true; i++) {
    nextAwake += interval.inMicroseconds;
    if (canSleep) {
      final toSleep =
          (nextAwake - sw.elapsedMicroseconds) - startBusyAt.inMicroseconds;
      // Only sleep if more than 1ms to avoid oversleeping
      // Sleep resolution is 1ms in dart.
      if (toSleep > 1000) {
        sleep(Duration(microseconds: toSleep));
      }
    }

    while (sw.elapsedMicroseconds < nextAwake) {}

    state = callback(state);
    if (completer.isCompleted) {
      break;
    }
  }
}

/// Run a callback at precise intervals asynchronously.
/// This is a less precise version of [runPreciseInterval]
/// that uses [Future.delayed] instead of [sleep] to reduce
/// the impact on the main thread.
/// The tradeoff is that the callback may be called
/// slightly later than the specified interval.
@pragma('vm:unsafe:no-bounds-checks')
Future<void> runPreciseIntervalAsync<T>(
  Duration interval,
  FutureOr<T> Function(T state) callback, {
  required Completer<void> completer,
  dynamic state,
  Duration startBusyAt = const Duration(milliseconds: 1),
  Stopwatch? sw,
}) async {
  sw ??= dartStopwatch;
  sw.start();

  for (int i = 1; true; i++) {
    final nextAwake = interval * i;
    final toSleep = (nextAwake - sw.elapsed) - startBusyAt;
    if (toSleep > Duration.zero) {
      await Future.delayed(toSleep);
    }

    while (sw.elapsed < nextAwake) {}
    // Await to allow the implementer to pause the loop if needed
    state = await callback(state);
    if (completer.isCompleted) {
      return;
    }
  }
}
