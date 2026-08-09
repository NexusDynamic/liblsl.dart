import 'package:liblsl_coordinator/framework.dart';

/// Builders for the queries the coordination layer actually issues.
///
/// These replace `LSLStreamInfoHelper.generatePredicate` and
/// `generateElectionPredicate`, and take the same arguments so migration is
/// mechanical — with one deliberate exception, documented on [election].
abstract final class PeerQueries {
  /// A general peer filter. Every argument is optional and omitted arguments
  /// contribute no clause.
  ///
  /// Clause order is fixed (and matches the original builder's) so that
  /// transports which compile the query to a string produce stable output.
  static DiscoveryQuery peers({
    String? streamNamePrefix,
    String? streamNameSuffix,
    String? sessionName,
    String? nodeId,
    String? nodeUId,
    String? nodeRole,
    String? capabilities,
    String? excludeNodeUId,
    double? randomRollLessThan,
    double? randomRollGreaterThan,
    String? startedBefore,
    String? startedAfter,
  }) {
    final terms = <DiscoveryQuery>[
      if (streamNamePrefix != null)
        FieldMatch(PeerField.streamName, MatchOp.startsWith, streamNamePrefix),
      if (streamNameSuffix != null)
        FieldMatch(PeerField.streamName, MatchOp.endsWith, streamNameSuffix),
      if (excludeNodeUId != null)
        NotQuery(FieldMatch.equals(PeerField.nodeUId, excludeNodeUId)),
      if (sessionName != null)
        FieldMatch.equals(PeerField.sessionName, sessionName),
      if (nodeId != null) FieldMatch.equals(PeerField.nodeId, nodeId),
      if (nodeUId != null) FieldMatch.equals(PeerField.nodeUId, nodeUId),
      if (nodeRole != null) FieldMatch.equals(PeerField.nodeRole, nodeRole),
      if (capabilities != null)
        FieldMatch.equals(PeerField.capabilities, capabilities),
      if (randomRollLessThan != null)
        FieldMatch(PeerField.randomRoll, MatchOp.lessThan, randomRollLessThan),
      if (randomRollGreaterThan != null)
        FieldMatch(
          PeerField.randomRoll,
          MatchOp.greaterThan,
          randomRollGreaterThan,
        ),
      if (startedBefore != null)
        FieldMatch(PeerField.startedAt, MatchOp.lessThan, startedBefore),
      if (startedAfter != null)
        FieldMatch(PeerField.startedAt, MatchOp.greaterThan, startedAfter),
    ];
    return terms.isEmpty ? const AlwaysMatch() : AndQuery(terms);
  }

  /// The election query: "is there anyone I should defer to?"
  ///
  /// A node runs this and becomes a participant if it matches anything —
  /// either an established coordinator, or a peer that outranks it under the
  /// promotion strategy. Matching nothing means it is the best candidate and
  /// becomes the coordinator.
  ///
  /// [excludeNodeUId] must be this node's own uId. The original builder took
  /// an `excludeSourceIdPrefix` and emitted
  /// `not(starts-with(source_id, '<nodeId>'))`, but `source_id` begins with the
  /// *stream* name, so a node id was never a prefix of it and the clause was
  /// always true — the self-exclusion never excluded anything. It was inert
  /// rather than harmful (a node's own role is `none` at election time, and its
  /// roll is not strictly less than itself), but relying on that was luck.
  /// Excluding by uId makes the intent real.
  static DiscoveryQuery election({
    required String streamName,
    required String sessionName,
    required String excludeNodeUId,
    required bool isRandomStrategy,
    double? myRandomRoll,
    String? myStartTime,
  }) {
    final betterCandidate = <DiscoveryQuery>[
      // An existing coordinator always wins, whatever the strategy.
      FieldMatch.equals(
        PeerField.nodeRole,
        NodeCapability.coordinator.shortString,
      ),
      if (isRandomStrategy && myRandomRoll != null)
        FieldMatch(PeerField.randomRoll, MatchOp.lessThan, myRandomRoll),
      if (!isRandomStrategy && myStartTime != null)
        FieldMatch(PeerField.startedAt, MatchOp.lessThan, myStartTime),
    ];

    return AndQuery([
      FieldMatch(PeerField.streamName, MatchOp.startsWith, streamName),
      FieldMatch.equals(PeerField.sessionName, sessionName),
      NotQuery(FieldMatch.equals(PeerField.nodeUId, excludeNodeUId)),
      OrQuery(betterCandidate),
    ]);
  }

  /// Finds the session's coordinator. With [coordinatorUId] null this matches
  /// whichever node currently holds the role.
  static DiscoveryQuery coordinator({
    required String streamName,
    required String sessionName,
    String? coordinatorUId,
  }) => peers(
    streamNamePrefix: streamName,
    sessionName: sessionName,
    nodeUId: coordinatorUId,
    nodeRole: NodeCapability.coordinator.shortString,
  );

  /// Finds the session's participants.
  static DiscoveryQuery participants({
    required String streamName,
    required String sessionName,
  }) => peers(
    streamNamePrefix: streamName,
    sessionName: sessionName,
    nodeRole: NodeCapability.participant.shortString,
  );

  /// Finds every publisher of [streamName] in the session, regardless of role.
  static DiscoveryQuery streamPublishers({
    required String streamName,
    required String sessionName,
    String? nodeUId,
  }) => peers(
    streamNamePrefix: streamName,
    sessionName: sessionName,
    nodeUId: nodeUId,
  );
}
