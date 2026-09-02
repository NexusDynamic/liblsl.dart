/// Tracks the joins a coordinator has offered but not yet completed.
///
/// Exists as its own object, rather than the bare `Set<String>` it replaces,
/// because the interesting behaviour is what happens when a handshake *never*
/// finishes — and that is a time-dependent question a set cannot answer.
///
/// The failure it fixes: the coordinator adds a node's id before creating its
/// inlet and sending a join offer, and removes it again only on
/// `NodeJoinedEvent`, `NodeJoinRejectedEvent`, or the inlet creation throwing.
/// A join offer is fire-and-forget — no ack, no retry — so if the offer or the
/// reply is simply lost, none of those three ever happens and the id stays in
/// the set for the lifetime of the process. Discovery re-emits its whole
/// resolved set every cycle, so from then on the coordinator logs
/// `Join already in progress for node ... skipping` forever and that node can
/// never rejoin.
///
/// It is not self-healing, because a rejoining node keeps its node id: the
/// participant reuses its `NodeConfig`, so the id presented on rejoin is the
/// same one already stuck. A node that restarted with a fresh id would be
/// admitted immediately — which is why the fault looked so arbitrary in the
/// field. It cost a participant the remainder of the session on 2026-08-31 and
/// every participant on 2026-09-02.
///
/// So: a deadline. An in-flight join is only in flight for as long as a join
/// could plausibly still be completing; after that the slot is released and
/// discovery offers again. Retrying an offer is cheap and idempotent — the
/// coordinator ignores a duplicate join request from a node it already has —
/// whereas never retrying is unrecoverable.
///
/// Expiry is lazy rather than timer-driven: the only thing that consults this
/// is the discovery cycle, so there is nothing for a timer to be more prompt
/// than, and a timer would be one more thing to cancel on teardown.
class PendingJoins {
  PendingJoins({required this.ttl})
    : assert(ttl > Duration.zero, 'A join needs time to complete');

  /// How long a join may be in flight before its slot is released.
  final Duration ttl;

  final Map<String, DateTime> _startedAt = {};

  /// Records that a join has been started for [nodeUId].
  void start(String nodeUId, {DateTime? now}) {
    _startedAt[nodeUId] = now ?? DateTime.now();
  }

  /// Whether a join for [nodeUId] is in flight and has not yet timed out.
  ///
  /// Expires the entry as a side effect when its deadline has passed, so the
  /// caller sees a clean slot on the same cycle it would otherwise have
  /// skipped.
  bool isInProgress(String nodeUId, {DateTime? now}) {
    final startedAt = _startedAt[nodeUId];
    if (startedAt == null) return false;
    final at = now ?? DateTime.now();
    if (at.difference(startedAt) >= ttl) {
      _startedAt.remove(nodeUId);
      return false;
    }
    return true;
  }

  /// How long [nodeUId]'s join has been in flight, or null if none is.
  ///
  /// For logging: a join that keeps being retried is worth seeing as a
  /// duration rather than as a repeated line.
  Duration? inFlightFor(String nodeUId, {DateTime? now}) {
    final startedAt = _startedAt[nodeUId];
    if (startedAt == null) return null;
    return (now ?? DateTime.now()).difference(startedAt);
  }

  /// Releases [nodeUId]'s slot — it joined, was rejected, or failed outright.
  void complete(String nodeUId) => _startedAt.remove(nodeUId);

  /// Releases every slot. Used when the session or the role is torn down.
  void clear() => _startedAt.clear();

  /// Node ids currently considered in flight, without expiring any.
  Iterable<String> get inFlight => _startedAt.keys;

  /// How many joins are in flight, without expiring any.
  int get length => _startedAt.length;
}
