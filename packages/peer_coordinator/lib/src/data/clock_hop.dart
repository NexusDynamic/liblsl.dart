/// The clock corrections a stream picked up on its way here, one per hop.
///
/// A sample that crosses several transports — LSL into a bridge, over WebRTC,
/// into another bridge — keeps the timestamp its origin gave it. What changes
/// from node to node is how that timestamp maps onto the local clock, so each
/// node adds one [ClockHop] to the stream's [ClockChain] and passes the chain
/// on beside the samples, at the cadence clock estimates are made (seconds),
/// never per sample.
///
/// Aligning data needs only the chain's totals ([ClockChain.offsetAt],
/// [ClockChain.uncertainty]), which is what `lsl_time_correction_ex` gives for
/// a single hop. The individual hops are for finding out *which* node is slow
/// or noisy when the totals look wrong.
library;

/// One hop: how the previous clock in the chain maps onto [node]'s.
final class ClockHop {
  /// The node whose clock this hop maps onto, and where [latency] was
  /// measured: a host name, a node uId.
  final String node;

  /// The transport the hop crossed: `lsl`, `bridge`, `webrtc`, `websocket`.
  final String via;

  /// Seconds to *add* to a time on the previous clock, at [at], to get
  /// [node]'s clock. Same sign convention as `MessageTiming.clockOffset`.
  final double offset;

  /// How fast [offset] changes, in seconds per second of the previous clock
  /// (so `1e-5` is 10 ppm). Zero when not estimated.
  final double drift;

  /// The time on the previous clock that [offset] is exact for.
  final double at;

  /// Error bound on [offset]: the **full** round-trip time of the probe behind
  /// it, so the true offset lies within ±[uncertainty]/2. Same convention as
  /// `MessageTiming.uncertainty`.
  final double uncertainty;

  /// Mean time from a sample's timestamp to its arrival at [node], in seconds,
  /// or null if [node] has not measured it.
  ///
  /// Cumulative from the origin, so what this hop added is the difference from
  /// the hop before.
  final double? latency;

  /// Standard deviation of [latency], or null.
  final double? jitter;

  const ClockHop({
    required this.node,
    required this.via,
    required this.offset,
    this.drift = 0,
    this.at = 0,
    this.uncertainty = 0,
    this.latency,
    this.jitter,
  });

  /// [t] on the previous clock, mapped onto [node]'s.
  double map(double t) => t + offset + drift * (t - at);

  /// The same hop walked backwards: [node]'s clock onto the previous one.
  ///
  /// For the end that measured an offset to describe the hop *to* the other
  /// end, named [node]. Latency does not carry over: only that end can measure
  /// arrivals there.
  ClockHop inverse({required String node}) => ClockHop(
    node: node,
    via: via,
    offset: -offset,
    drift: -drift / (1 + drift),
    at: at + offset,
    uncertainty: uncertainty,
  );

  ClockHop withLatency(double? latency, double? jitter) => ClockHop(
    node: node,
    via: via,
    offset: offset,
    drift: drift,
    at: at,
    uncertainty: uncertainty,
    latency: latency,
    jitter: jitter,
  );

  Map<String, Object?> toJson() => {
    'node': node,
    'via': via,
    'offset': offset,
    'drift': drift,
    'at': at,
    'uncertainty': uncertainty,
    'latency': latency,
    'jitter': jitter,
  };

  factory ClockHop.fromJson(Map<String, Object?> j) => ClockHop(
    node: '${j['node'] ?? ''}',
    via: '${j['via'] ?? ''}',
    offset: _finite(j['offset']) ?? 0,
    drift: _finite(j['drift']) ?? 0,
    at: _finite(j['at']) ?? 0,
    uncertainty: _finite(j['uncertainty']) ?? 0,
    latency: _finite(j['latency']),
    jitter: _finite(j['jitter']),
  );

  /// A number from the wire, or null: a peer's NaN or infinity must not reach
  /// every timestamp mapped through the chain.
  static double? _finite(Object? v) =>
      v is num && v.isFinite ? v.toDouble() : null;

  @override
  String toString() {
    final l = latency;
    return '$via@$node: ${(offset * 1e3).toStringAsFixed(3)}ms '
        '±${(uncertainty * 5e2).toStringAsFixed(3)}ms'
        '${l == null ? '' : ', latency ${(l * 1e3).toStringAsFixed(1)}ms'}';
  }
}

/// The hops a stream has crossed, origin first.
final class ClockChain {
  final List<ClockHop> hops;

  const ClockChain(this.hops);

  /// No hops: timestamps are already on the local clock.
  static const empty = ClockChain([]);

  /// More hops than any real route, so a hostile peer cannot make every
  /// sample cost an unbounded walk.
  static const maxHops = 32;

  /// [t] on the origin's clock, mapped through every hop.
  double map(double t) {
    for (final h in hops) {
      t = h.map(t);
    }
    return t;
  }

  /// Seconds to add to [t] on the origin's clock to get the last hop's: the
  /// chain's equivalent of `lsl_time_correction`.
  double offsetAt(double t) => map(t) - t;

  /// [offsetAt] where the first hop was measured: one figure for the whole
  /// chain, for display. Zero for an empty chain.
  double get offset => hops.isEmpty ? 0 : offsetAt(hops.first.at);

  /// Error bound on [offsetAt]: the hops' round-trip times added up, so the
  /// true offset lies within ±[uncertainty]/2.
  double get uncertainty => hops.fold(0, (sum, h) => sum + h.uncertainty);

  /// How fast [offsetAt] changes, in seconds per second.
  double get drift => hops.fold<double>(1, (r, h) => r * (1 + h.drift)) - 1;

  /// Mean time from timestamp to arrival at the last hop that measured it.
  double? get latency {
    for (final h in hops.reversed) {
      if (h.latency != null) return h.latency;
    }
    return null;
  }

  /// This chain with [hop] added at the end.
  ClockChain then(ClockHop hop) =>
      ClockChain(List.unmodifiable([...hops, hop]));

  List<Object?> toJson() => [for (final h in hops) h.toJson()];

  /// A chain from the wire; anything malformed or beyond [maxHops] is dropped.
  factory ClockChain.fromJson(Object? json) {
    if (json is! List) return empty;
    return ClockChain(
      List.unmodifiable([
        for (final h in json.take(maxHops))
          if (h is Map) ClockHop.fromJson(h.cast<String, Object?>()),
      ]),
    );
  }

  @override
  String toString() => hops.isEmpty ? 'local' : hops.join(' → ');
}
