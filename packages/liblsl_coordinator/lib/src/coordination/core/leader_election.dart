import 'coordination_node.dart';

/// Strategy for leader election
abstract class LeaderElectionStrategy {
  /// Determine if this node should become the leader
  bool shouldBecomeLeader(
    String nodeId,
    List<NetworkNode> candidates,
    Map<String, dynamic> context,
  );
}

/// First node becomes leader (your current approach)
class FirstNodeLeaderElection implements LeaderElectionStrategy {
  @override
  bool shouldBecomeLeader(
    String nodeId,
    List<NetworkNode> candidates,
    Map<String, dynamic> context,
  ) {
    if (candidates.isEmpty) return true;

    // Sort by join time or node ID for deterministic ordering
    candidates.sort((a, b) => a.nodeId.compareTo(b.nodeId));
    return candidates.first.nodeId == nodeId;
  }
}

/// Leader election based on node capabilities
class CapabilityBasedLeaderElection implements LeaderElectionStrategy {
  final String capabilityKey;
  final bool higherIsBetter;

  const CapabilityBasedLeaderElection(
    this.capabilityKey, {
    this.higherIsBetter = true,
  });

  @override
  bool shouldBecomeLeader(
    String nodeId,
    List<NetworkNode> candidates,
    Map<String, dynamic> context,
  ) {
    if (candidates.isEmpty) return true;

    final thisNode = candidates.firstWhere((n) => n.nodeId == nodeId);
    final thisValue = thisNode.metadata[capabilityKey] as num? ?? 0;

    for (final candidate in candidates) {
      if (candidate.nodeId == nodeId) continue;

      final candidateValue = candidate.metadata[capabilityKey] as num? ?? 0;

      if (higherIsBetter) {
        if (candidateValue > thisValue) return false;
      } else {
        if (candidateValue < thisValue) return false;
      }
    }

    return true;
  }
}
