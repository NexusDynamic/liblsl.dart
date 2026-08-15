/// Receive-side timing for a single message, as the transport observed it.
///
/// Every inbound message carries one of these when the transport can supply it,
/// whether it is a 500 Hz data sample or a once-per-session coordination
/// message — characterising the network means measuring both.
///
/// The clock domains follow LSL's model, because it is the strictest of the
/// transports: [sourceClock] is a reading of the *sender's* clock, whose epoch
/// is unrelated to ours, and [clockOffset] is what maps it into our own domain.
/// [receivedClock] is a reading of the local clock in that same domain.
///
/// All three are seconds. Nullability is meaningful: a null [sourceClock] or
/// [clockOffset] means the value is genuinely unknown, and [transitSeconds]
/// then returns null rather than a plausible-looking fabrication.
final class MessageTiming {
  /// The sender's clock at capture, in the sender's own domain.
  ///
  /// LSL: the sample's timestamp, i.e. `lsl_local_clock()` on the sending
  /// machine. Other transports: `PeerClock.now()` on the sender, carried on
  /// the wire.
  final double? sourceClock;

  /// Seconds to *add* to [sourceClock] to map it into the local clock domain.
  ///
  /// LSL: `lsl_time_correction()`, refreshed periodically per inlet. In-memory:
  /// zero, since both ends share a process and therefore a clock. WebSocket:
  /// null — the two ends have unrelated monotonic epochs and nothing estimates
  /// the offset yet.
  ///
  /// Null means "not known", which is distinct from a known offset of zero.
  final double? clockOffset;

  /// The local clock when this message was received, in the local domain.
  ///
  /// Captured as close to the transport as possible — for LSL, inside the inlet
  /// isolate at pull time, so it excludes the isolate-port hop that follows.
  final double receivedClock;

  /// How the transport identifies the sender: LSL's `source_id`, a WebSocket
  /// slot id, and so on. Null if the transport does not distinguish senders.
  final String? sourceId;

  const MessageTiming({
    required this.receivedClock,
    this.sourceClock,
    this.clockOffset,
    this.sourceId,
  });

  /// [sourceClock] mapped into the local clock domain, or null if either the
  /// sender's reading or the offset needed to translate it is unknown.
  double? get sourceClockLocal {
    final source = sourceClock;
    final offset = clockOffset;
    if (source == null || offset == null) return null;
    return source + offset;
  }

  /// One-way transit time in seconds, or null when it cannot be computed
  /// honestly (see [sourceClockLocal]).
  ///
  /// May be slightly negative on a fast link: the clock offset is an estimate
  /// with its own uncertainty (empirically well under a millisecond on wired
  /// networks, a few milliseconds on wireless). Callers characterising a link
  /// should keep those samples rather than clamping them, since their spread is
  /// itself the measurement.
  double? get transitSeconds {
    final source = sourceClockLocal;
    if (source == null) return null;
    return receivedClock - source;
  }

  /// [transitSeconds] in microseconds, rounded, or null.
  int? get transitMicros {
    final seconds = transitSeconds;
    return seconds == null ? null : (seconds * 1e6).round();
  }

  Map<String, dynamic> toMap() => {
    'sourceClock': sourceClock,
    'clockOffset': clockOffset,
    'receivedClock': receivedClock,
    'sourceId': sourceId,
  };

  @override
  String toString() =>
      'MessageTiming(sourceClock: $sourceClock, clockOffset: $clockOffset, '
      'receivedClock: $receivedClock, sourceId: $sourceId, '
      'transit: ${transitMicros}us)';
}
