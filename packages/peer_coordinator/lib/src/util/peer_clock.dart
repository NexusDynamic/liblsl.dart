/// A process-local monotonic clock, mirroring the contract of LSL's
/// `lsl_local_clock()`.
///
/// The epoch is arbitrary — it is whenever this library was first touched in
/// this process — so a reading is only comparable with other readings from the
/// *same* process. Comparing across peers requires a clock-offset estimate, in
/// exactly the same way `lsl_time_correction()` is needed to compare two LSL
/// nodes' `lsl_local_clock()` readings.
///
/// Transports that have no native sender clock (WebSocket, in-memory) use this
/// to stamp outgoing messages. The LSL transport does *not*: an LSL sample
/// already carries the sender's `lsl_local_clock()` reading as its timestamp,
/// and inventing a second one would only add a redundant, less accurate number.
abstract final class PeerClock {
  static final Stopwatch _stopwatch = Stopwatch()..start();

  /// Monotonic seconds since this library was first used in this process.
  ///
  /// Seconds (as a `double`) rather than a `Duration` so the value shares a
  /// unit with LSL's clock and can be compared with [MessageTiming.sourceClock]
  /// without conversion.
  static double now() => _stopwatch.elapsedMicroseconds / 1e6;

  /// Monotonic microseconds since this library was first used in this process.
  ///
  /// For wire formats that carry an integer timestamp.
  static int nowMicros() => _stopwatch.elapsedMicroseconds;
}
