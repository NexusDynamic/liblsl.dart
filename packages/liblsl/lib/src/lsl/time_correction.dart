/// An extended time-correction estimate from `lsl_time_correction_ex`.
///
/// The plain [LSLInlet.getTimeCorrection] returns only [offset]; liblsl computes
/// all three values on the same round trip regardless (see `time_receiver.cpp`),
/// so asking for the extended form costs nothing extra.
final class LSLTimeCorrection {
  /// Seconds to *add* to a remotely generated `lsl_local_clock()` timestamp to
  /// map it into this machine's clock domain.
  ///
  /// Identical to the value returned by [LSLInlet.getTimeCorrection].
  final double offset;

  /// The remote machine's clock at the moment this estimate was taken.
  ///
  /// Fit [offset] against this over successive estimates to model clock drift
  /// and improve the real-time correction beyond a single reading.
  final double remoteTime;

  /// The **full** round-trip time of the probe [offset] came from, in seconds.
  ///
  /// This is the whole RTT, not half of it: the true offset lies within
  /// ±[bound]. Empirically ~0.2 ms on wired networks and ~2 ms on wireless;
  /// much higher on a poor link. It is the measure of whether the network is
  /// well-behaved enough to trust [offset].
  final double uncertainty;

  const LSLTimeCorrection({
    required this.offset,
    required this.remoteTime,
    required this.uncertainty,
  });

  /// Half of [uncertainty] — the ± error bound on [offset].
  double get bound => uncertainty / 2;

  @override
  String toString() =>
      'LSLTimeCorrection{offset: $offset, remoteTime: $remoteTime, '
      'uncertainty: $uncertainty}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LSLTimeCorrection &&
          offset == other.offset &&
          remoteTime == other.remoteTime &&
          uncertainty == other.uncertainty;

  @override
  int get hashCode => Object.hash(offset, remoteTime, uncertainty);
}
