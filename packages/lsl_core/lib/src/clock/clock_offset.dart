/// One accepted estimate of a peer's clock relative to ours.
final class ClockOffsetEstimate {
  /// Seconds to *add* to a timestamp in the peer's clock domain to map it into
  /// ours.
  ///
  /// Note the sign. The NTP formula naturally yields `remote - local`; liblsl
  /// negates it before publishing (`timeoffset_ = -best_offset`,
  /// `time_receiver.cpp:205`) so the value is something you add to a remote
  /// timestamp. `MessageTiming.clockOffset` (peer_coordinator) uses the same convention.
  final double offset;

  /// Error bound on [offset], as the **full** round-trip time of the probe this
  /// estimate came from.
  ///
  /// The true offset lies within ±[uncertainty]/2; liblsl reports the whole RTT
  /// rather than half of it, and `lsl_time_correction_ex` exposes it under this
  /// same name. Reporting the conservative bound is the point — a transit time
  /// quoted without one implies a precision the method does not have.
  final double uncertainty;

  /// The peer's clock at the midpoint of its dwell, `(t1 + t2) / 2`.
  ///
  /// liblsl exposes this so callers can fit [offset] against it and extrapolate
  /// drift themselves; neither liblsl nor this class does any such fit.
  final double remoteTime;

  /// Local clock when this estimate was accepted.
  final double sampledAt;

  const ClockOffsetEstimate({
    required this.offset,
    required this.uncertainty,
    required this.remoteTime,
    required this.sampledAt,
  });

  @override
  String toString() =>
      'ClockOffsetEstimate(offset: ${(offset * 1e6).toStringAsFixed(1)}us, '
      '±${(uncertainty * 1e6 / 2).toStringAsFixed(1)}us)';
}
