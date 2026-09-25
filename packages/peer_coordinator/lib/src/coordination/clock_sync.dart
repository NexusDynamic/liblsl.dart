/// NTP-style clock-offset estimation between peers, modelled on liblsl.
///
/// Two peers in separate processes read monotonic clocks with unrelated epochs
/// ([PeerClock]), so a timestamp from one means nothing to the other until the
/// difference is known. LSL solves this with `lsl_time_correction`; transports
/// that have no native equivalent use this.
///
/// ## Why the estimator lives on the receiving side, one per inlet
///
/// liblsl runs its `time_receiver` on the **inlet**, one instance per inlet,
/// probing the outlet it reads from. The outlet side is a passive, stateless
/// responder folded into the existing UDP server — it estimates nothing. The
/// asymmetry is deliberate: an inlet has exactly one producer, so the estimate
/// has a well-defined subject, whereas an outlet has N consumers whose poll
/// rates it does not know and cannot characterise.
///
/// This mirrors that. A node runs one [PeerClockEstimator] per peer it has an
/// inlet from, and answers other peers' probes without keeping any state.
library;

import 'dart:async';
import 'dart:math';

import 'package:peer_coordinator/src/util/peer_clock.dart';

/// One accepted estimate of a peer's clock relative to ours.
final class ClockOffsetEstimate {
  /// Seconds to *add* to a timestamp in the peer's clock domain to map it into
  /// ours.
  ///
  /// Note the sign. The NTP formula naturally yields `remote - local`; liblsl
  /// negates it before publishing (`timeoffset_ = -best_offset`,
  /// `time_receiver.cpp:205`) so the value is something you add to a remote
  /// timestamp. [MessageTiming.clockOffset] uses the same convention.
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

/// Tuning for [PeerClockEstimator], defaulting to liblsl's `[tuning]` section.
///
/// The defaults are liblsl's verbatim (`api_config.cpp:312-325`). They are
/// exposed because liblsl can afford them in a way this cannot: its probes are
/// UDP datagrams on a dedicated service port, completely off the data path,
/// while these ride the coordination stream alongside heartbeats, joins and
/// user messages. At the defaults that is ~8 messages/second per peer pair, and
/// it scales with participant count on the coordinator.
final class ClockSyncConfig {
  /// Between the *starts* of consecutive probe bursts.
  final Duration timeUpdateInterval;

  /// Probes sent per burst.
  final int timeProbeCount;

  /// Between individual probes within a burst.
  final Duration timeProbeInterval;

  /// Extra grace after the last probe of a burst before aggregating, to let
  /// stragglers arrive.
  ///
  /// Despite the name this is not an RTT rejection threshold — liblsl has no
  /// such filter, only argmin-RTT plus [timeUpdateMinProbes].
  final Duration timeProbeMaxRtt;

  /// Replies a burst must collect before its result is accepted. Below this the
  /// burst is discarded and the previous estimate is retained.
  final int timeUpdateMinProbes;

  const ClockSyncConfig({
    this.timeUpdateInterval = const Duration(seconds: 2),
    this.timeProbeCount = 8,
    this.timeProbeInterval = const Duration(milliseconds: 64),
    this.timeProbeMaxRtt = const Duration(milliseconds: 128),
    this.timeUpdateMinProbes = 6,
  });

  /// How long after a burst starts its results are aggregated.
  ///
  /// `TimeProbeMaxRTT + TimeProbeInterval * TimeProbeCount`
  /// (`time_receiver.cpp:117-119`) — 640 ms at the defaults.
  Duration get aggregateAfter =>
      timeProbeMaxRtt + timeProbeInterval * timeProbeCount;

  bool validate({bool throwOnError = false}) {
    String? problem;
    if (timeProbeCount < 1) {
      problem = 'timeProbeCount must be at least 1';
    } else if (timeUpdateMinProbes < 1) {
      problem = 'timeUpdateMinProbes must be at least 1';
    } else if (timeUpdateMinProbes > timeProbeCount) {
      problem =
          'timeUpdateMinProbes ($timeUpdateMinProbes) cannot exceed '
          'timeProbeCount ($timeProbeCount) — no burst could ever be accepted';
    } else if (aggregateAfter >= timeUpdateInterval) {
      problem =
          'timeUpdateInterval ($timeUpdateInterval) must exceed the time a '
          'burst takes to aggregate ($aggregateAfter), or bursts overlap';
    }
    if (problem == null) return true;
    if (throwOnError) throw ArgumentError(problem);
    return false;
  }
}

/// One probe's four timestamps, in the two clock domains they were read in.
///
/// [t0] and [t3] are ours; [t1] and [t2] are the peer's.
final class ClockProbeSample {
  /// Our clock when the request was put on the wire.
  final double t0;

  /// The peer's clock when the request arrived.
  final double t1;

  /// The peer's clock when the reply was put on the wire.
  final double t2;

  /// Our clock when the reply arrived.
  final double t3;

  const ClockProbeSample({
    required this.t0,
    required this.t1,
    required this.t2,
    required this.t3,
  });

  /// Round-trip time: time passed here minus time passed there.
  ///
  /// `time_receiver.cpp:171-172`.
  double get rtt => (t3 - t0) - (t2 - t1);

  /// Raw clock offset, `remote - local`, with the round-trip bias averaged out.
  ///
  /// `time_receiver.cpp:173-175`. Assumes a symmetric path: if the outbound and
  /// return legs differ, this is biased by half the asymmetry. That is inherent
  /// to the method, not a defect of this implementation.
  double get rawOffset => ((t1 - t0) + (t2 - t3)) / 2;

  /// The peer's clock at the midpoint of its dwell.
  double get remoteTime => (t2 + t1) / 2;
}

/// Collects probe replies for one peer and reduces each burst to one estimate.
///
/// Deliberately holds no timers and does no I/O: bursts are driven from outside
/// via [beginBurst] and [aggregate], and replies arrive through [addSample].
/// That keeps the arithmetic — the part worth getting right — testable with
/// injected timestamps rather than sockets and sleeps.
final class PeerClockEstimator {
  PeerClockEstimator({
    required this.peerUId,
    ClockSyncConfig? config,
    Random? random,
  }) : config = config ?? const ClockSyncConfig(),
       _random = random ?? Random();

  final String peerUId;
  final ClockSyncConfig config;
  final Random _random;

  /// Results of the burst currently in flight. Cleared at each [beginBurst],
  /// exactly as `time_receiver.cpp:111-113` does — there is no cross-burst
  /// history.
  final List<ClockProbeSample> _burst = [];

  int _waveId = 0;

  ClockOffsetEstimate? _estimate;

  /// The most recently accepted estimate, or null if no burst has been accepted
  /// yet. Null is meaningful: it means "offset unknown", never "offset zero".
  ClockOffsetEstimate? get estimate => _estimate;

  /// Identifies the burst in flight. Replies quoting any other wave are stale
  /// and dropped (`time_receiver.cpp:163`).
  int get waveId => _waveId;

  /// Replies collected for the burst in flight. Exposed for tests and logging.
  int get repliesThisBurst => _burst.length;

  /// Starts a new burst and returns its wave id.
  int beginBurst() {
    _burst.clear();
    // A fresh random id rather than a counter, so a reply from a burst two
    // cycles ago cannot be mistaken for a current one after a wrap or restart.
    // Bounded at 2^31-1 rather than 2^32: the WebSocket transport runs in the
    // browser, where Dart ints are doubles and bitwise ops are 32-bit signed.
    _waveId = _random.nextInt(0x7FFFFFFF);
    return _waveId;
  }

  /// Records a reply. Returns false if it was dropped as stale.
  bool addSample(int waveId, ClockProbeSample sample) {
    if (waveId != _waveId) return false;
    _burst.add(sample);
    return true;
  }

  /// Reduces the burst in flight to at most one estimate.
  ///
  /// Takes the sample with the **lowest RTT** — the least-queued, most
  /// symmetric measurement, and therefore the one whose offset is best bounded.
  /// This is argmin over the current burst only: no median, no window across
  /// bursts, no smoothing (`time_receiver.cpp:187-210`). The published estimate
  /// consequently *steps* once per interval; liblsl absorbs those steps in a
  /// downstream RLS dejitterer, which is not reproduced here — [uncertainty]
  /// states the bound instead.
  ///
  /// A burst with fewer than [ClockSyncConfig.timeUpdateMinProbes] replies is
  /// discarded and the previous estimate retained, silently, as liblsl does.
  /// Returns the new estimate, or null if the burst was not accepted.
  ClockOffsetEstimate? aggregate() {
    if (_burst.length < config.timeUpdateMinProbes) return null;

    ClockProbeSample? best;
    for (final sample in _burst) {
      if (best == null || sample.rtt < best.rtt) best = sample;
    }
    if (best == null) return null;

    return _estimate = ClockOffsetEstimate(
      // Negated so the value is added to a remote timestamp.
      offset: -best.rawOffset,
      uncertainty: best.rtt,
      remoteTime: best.remoteTime,
      sampledAt: PeerClock.now(),
    );
  }

  /// Forgets the current estimate — used when a peer reconnects and its clock
  /// domain may have changed, mirroring `reset_timeoffset_on_recovery`.
  void reset() {
    _burst.clear();
    _estimate = null;
  }
}

/// Per-peer clock offsets for one process, shared by every stream on a
/// transport.
///
/// An offset is a property of the peer *process*, not of any one stream, so the
/// coordination path and every data stream read the same table. Keyed on node
/// uId, which is the only identifier stable across role changes and transports
/// (`MessageTiming.sourceId` is transport-specific and is not always a uId).
final class PeerClockOffsets {
  final Map<String, ClockOffsetEstimate> _byPeer = {};

  /// The offset to add to [peerUId]'s timestamps, or null if unknown.
  double? offsetFor(String? peerUId) =>
      peerUId == null ? null : _byPeer[peerUId]?.offset;

  /// The error bound on [offsetFor], or null if unknown.
  double? uncertaintyFor(String? peerUId) =>
      peerUId == null ? null : _byPeer[peerUId]?.uncertainty;

  ClockOffsetEstimate? estimateFor(String? peerUId) =>
      peerUId == null ? null : _byPeer[peerUId];

  /// Peers with an accepted estimate.
  Iterable<String> get peers => _byPeer.keys;

  void set(String peerUId, ClockOffsetEstimate estimate) =>
      _byPeer[peerUId] = estimate;

  void remove(String peerUId) => _byPeer.remove(peerUId);

  void clear() => _byPeer.clear();
}

/// Drives [PeerClockEstimator]s on timers and sends probes through a callback.
///
/// One of these per node. It owns the burst schedule; the actual message
/// send is injected as [sendProbe] so this class stays free of any coordination
/// or transport types.
final class ClockSyncService {
  ClockSyncService({
    required this.sendProbe,
    required this.offsets,
    ClockSyncConfig? config,
    Random? random,
  }) : config = config ?? const ClockSyncConfig(),
       _random = random ?? Random();

  /// Sends one probe request to a peer. Fire-and-forget by design: a probe that
  /// fails to send is simply a reply that never arrives, which the minimum-probe
  /// gate already handles.
  final void Function(String peerUId, int waveId, int probeIndex) sendProbe;

  /// Where accepted estimates are published for readers to pick up.
  final PeerClockOffsets offsets;

  final ClockSyncConfig config;
  final Random _random;

  final Map<String, PeerClockEstimator> _estimators = {};
  final Map<String, List<Timer>> _timers = {};
  bool _disposed = false;

  /// Peers currently being probed.
  Iterable<String> get trackedPeers => _estimators.keys;

  PeerClockEstimator? estimatorFor(String peerUId) => _estimators[peerUId];

  /// Begins probing [peerUId]. Call this when an inlet from that peer is
  /// created; idempotent, so a re-discovered peer does not get two schedules.
  void trackPeer(String peerUId) {
    if (_disposed || _estimators.containsKey(peerUId)) return;
    _estimators[peerUId] = PeerClockEstimator(
      peerUId: peerUId,
      config: config,
      random: _random,
    );
    _timers[peerUId] = [];
    // Probe immediately rather than waiting out a full interval, so a peer has
    // a usable offset within ~640ms of joining instead of ~2.6s.
    _runBurst(peerUId);
    _timers[peerUId]!.add(
      Timer.periodic(config.timeUpdateInterval, (_) => _runBurst(peerUId)),
    );
  }

  /// Stops probing [peerUId] and forgets its offset. Call when the inlet goes
  /// away — a stale offset for a departed peer is worse than none.
  void untrackPeer(String peerUId) {
    for (final timer in _timers.remove(peerUId) ?? const <Timer>[]) {
      timer.cancel();
    }
    _estimators.remove(peerUId);
    offsets.remove(peerUId);
  }

  /// Feeds a reply in. Returns false if it was stale or the peer is untracked.
  bool recordReply(String peerUId, int waveId, ClockProbeSample sample) {
    final estimator = _estimators[peerUId];
    if (estimator == null) return false;
    return estimator.addSample(waveId, sample);
  }

  void _runBurst(String peerUId) {
    final estimator = _estimators[peerUId];
    if (_disposed || estimator == null) return;

    final waveId = estimator.beginBurst();
    final timers = _timers[peerUId];
    if (timers == null) return;

    // Probes are spread across the burst rather than sent back to back so each
    // one samples a different moment of network and scheduler jitter — a single
    // burst of eight simultaneous probes would all queue behind each other and
    // share one bad measurement.
    for (var i = 0; i < config.timeProbeCount; i++) {
      if (i == 0) {
        sendProbe(peerUId, waveId, 0);
        continue;
      }
      timers.add(
        Timer(config.timeProbeInterval * i, () {
          // Guard against a burst that was superseded while its probes were
          // still pending (peer untracked, or service disposed).
          if (_disposed || estimator.waveId != waveId) return;
          sendProbe(peerUId, waveId, i);
        }),
      );
    }

    timers.add(
      Timer(config.aggregateAfter, () {
        if (_disposed || estimator.waveId != waveId) return;
        final estimate = estimator.aggregate();
        if (estimate != null) offsets.set(peerUId, estimate);
      }),
    );

    // Timers fired long ago still sit in the list; drop the dead ones so a long
    // session does not accumulate one entry per probe forever.
    timers.removeWhere((timer) => !timer.isActive);
  }

  void dispose() {
    _disposed = true;
    for (final timers in _timers.values) {
      for (final timer in timers) {
        timer.cancel();
      }
    }
    _timers.clear();
    _estimators.clear();
    offsets.clear();
  }
}
