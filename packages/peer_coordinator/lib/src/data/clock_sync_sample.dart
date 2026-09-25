/// One clock-offset estimate for one peer, as the transport measured it.
///
/// Distinct from [MessageTiming], and deliberately a separate channel rather
/// than extra fields on it. An offset estimate is refreshed on the order of
/// once every few seconds, while data samples arrive hundreds of times a
/// second; carrying the estimate's own metadata on every sample would repeat
/// one value hundreds of times across the isolate port and tell a reader
/// nothing new. [MessageTiming] answers "when did *this* message arrive";
/// this answers "how well do the two clocks agree right now".
///
/// It also carries what a per-message view structurally cannot: the estimates
/// themselves, at their own cadence, whether or not any traffic happened to
/// arrive. Without them, clock drift over a session is only observable where
/// an event occurred, so a quiet stream leaves an unbridgeable gap.
final class ClockSyncSample {
  const ClockSyncSample({
    required this.receivedClock,
    this.sourceId,
    this.offset,
    this.remoteTime,
    this.uncertainty,
    this.clockReset = false,
  });

  /// How the transport identifies the peer this estimate is for: LSL's
  /// `source_id`, a peer's node uId, and so on.
  final String? sourceId;

  /// Seconds to *add* to a reading of the peer's clock to map it into the
  /// local domain — the same quantity as [MessageTiming.clockOffset].
  ///
  /// Null when the probe failed or no estimate has completed yet, which is
  /// distinct from a known offset of zero.
  final double? offset;

  /// The peer's own clock at the moment the estimate was taken.
  ///
  /// LSL reports this from `lsl_time_correction_ex` and it is otherwise
  /// discarded. It is what makes a sequence of estimates fittable: an offset
  /// alone says how far apart the clocks are, while (remoteTime, offset) pairs
  /// say how that gap is *changing*, which is the drift term.
  final double? remoteTime;

  /// Error bound on [offset]: the **full** round-trip time of the probe, so
  /// the true offset lies within ±[uncertainty]/2. Same convention as
  /// [MessageTiming.uncertainty].
  final double? uncertainty;

  /// The local clock when this estimate was taken, in the local domain.
  final double receivedClock;

  /// Whether the peer's clock may have been reset since the previous estimate.
  ///
  /// A reset invalidates any offset fitted across several estimates — the
  /// series must be restarted from here rather than continued through it.
  /// Reading this flag from the underlying transport clears it, so it is
  /// reported exactly once, on the first estimate that observes it.
  final bool clockReset;

  /// Half of [uncertainty] — the ± bound on [offset] — or null.
  double? get bound {
    final u = uncertainty;
    return u == null ? null : u / 2;
  }

  Map<String, dynamic> toMap() => {
    'sourceId': sourceId,
    'offset': offset,
    'remoteTime': remoteTime,
    'uncertainty': uncertainty,
    'receivedClock': receivedClock,
    'clockReset': clockReset,
  };

  @override
  String toString() {
    final o = offset;
    final b = bound;
    final offsetText = o == null
        ? 'offset: unknown'
        : b == null
        ? 'offset: ${o}s'
        : 'offset: ${o}s ±${(b * 1e6).toStringAsFixed(0)}us';
    return 'ClockSyncSample(sourceId: $sourceId, $offsetText, '
        'remoteTime: $remoteTime, receivedClock: $receivedClock, '
        'clockReset: $clockReset)';
  }
}
