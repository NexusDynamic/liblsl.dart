import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' show calloc;

final class _Timespec extends Struct {
  @Long()
  external int seconds;

  @Long()
  external int nanoseconds;
}

/// How the clock the system stamps touches with relates to the clock a run
/// is logged on, so that a touch's own time stamp
/// (`PointerData.timeStamp`) can be placed among the run's other times.
///
/// The system stamps a touch before the application hears of it. Mapped
/// onto the run's clock, the stamp is the earliest time there is for the
/// touch short of a sensor on the screen.
final class PointerClock {
  const PointerClock(this.name, this.offset, this.uncertainty);

  /// The POSIX clock taken to be behind the stamps on this platform.
  final String name;

  /// Seconds to add to a touch's time stamp to read it on the run's clock.
  final double offset;

  /// The offset is within this many seconds of the truth, if [name] is the
  /// right clock.
  final double uncertainty;

  /// [timeStamp] on the run's clock.
  double map(Duration timeStamp) => timeStamp.inMicroseconds / 1e6 + offset;

  Map<String, dynamic> toJson() => {
    'clock': name,
    'offset': offset,
    'uncertainty': uncertainty,
  };

  /// Measures the offset to [clock], the run's clock: the tightest of
  /// [trials] readings of it taken between two of the system's.
  ///
  /// Null where there is no `clock_gettime` to read (Windows, the web).
  /// Which system clock stamps touches is a matter of platform: Android
  /// uses `CLOCK_MONOTONIC` (`SystemClock.uptimeMillis`), and iOS and macOS
  /// the clock behind `mach_absolute_time`. Nothing here can check that,
  /// so a stamp that maps to after the touch was heard, or long before it,
  /// should not be believed.
  static PointerClock? measure(double Function() clock, {int trials = 101}) {
    final darwin = Platform.isIOS || Platform.isMacOS;
    if (!darwin && !Platform.isAndroid && !Platform.isLinux) return null;
    // CLOCK_UPTIME_RAW on Darwin, CLOCK_MONOTONIC elsewhere.
    final id = darwin ? 8 : 1;
    final int Function(int, Pointer<_Timespec>) clockGetTime;
    try {
      clockGetTime = DynamicLibrary.process()
          .lookupFunction<
            Int32 Function(Int32, Pointer<_Timespec>),
            int Function(int, Pointer<_Timespec>)
          >('clock_gettime', isLeaf: true);
    } on ArgumentError {
      return null;
    }
    final time = calloc<_Timespec>();
    try {
      double read() => clockGetTime(id, time) != 0
          ? double.nan
          : time.ref.seconds + time.ref.nanoseconds * 1e-9;
      var halfWidth = double.infinity, offset = 0.0;
      for (var i = 0; i < trials; i++) {
        final before = read();
        final now = clock();
        final after = read();
        if (before.isNaN || after.isNaN) return null;
        if ((after - before) / 2 < halfWidth) {
          halfWidth = (after - before) / 2;
          offset = now - (before + after) / 2;
        }
      }
      return PointerClock(
        darwin ? 'CLOCK_UPTIME_RAW' : 'CLOCK_MONOTONIC',
        offset,
        halfWidth,
      );
    } finally {
      calloc.free(time);
    }
  }
}
