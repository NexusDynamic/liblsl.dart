import 'dart:async';
import 'protocol.dart';
import '../session/coordination_session.dart';

/// Protocol for leader election in hierarchical networks
abstract class ElectionProtocol extends Protocol {
  /// Start an election process
  Future<ElectionResult> startElection(List<NetworkNode> candidates);
  
  /// Vote in an ongoing election
  Future<void> vote(String electionId, String candidateId);
  
  /// Handle election results
  Future<void> handleElectionResult(ElectionResult result);
  
  /// Stream of election events
  Stream<ElectionEvent> get electionEvents;
}

/// Strategy pattern for different election algorithms
abstract class ElectionStrategy {
  /// Determine if this node should become the leader
  bool shouldBecomeLeader(
    String nodeId,
    List<NetworkNode> candidates,
    Map<String, dynamic> context,
  );
  
  /// Calculate election priority for this node (higher = more likely to win)
  double calculatePriority(NetworkNode node, Map<String, dynamic> context);
}

/// Result of an election
class ElectionResult {
  final String electionId;
  final NetworkNode? winner;
  final List<NetworkNode> candidates;
  final Map<String, int> votes;
  final DateTime completedAt;
  
  const ElectionResult({
    required this.electionId,
    required this.winner,
    required this.candidates,
    required this.votes,
    required this.completedAt,
  });
  
  bool get hasWinner => winner != null;
}

/// Election events
sealed class ElectionEvent {
  final String electionId;
  final DateTime timestamp;
  
  const ElectionEvent(this.electionId, this.timestamp);
}

class ElectionStarted extends ElectionEvent {
  final List<NetworkNode> candidates;
  
  ElectionStarted(String electionId, this.candidates) : super(electionId, DateTime.now());
}

class ElectionCompleted extends ElectionEvent {
  final ElectionResult result;
  
  ElectionCompleted(String electionId, this.result) : super(electionId, DateTime.now());
}

class ElectionFailed extends ElectionEvent {
  final String reason;
  
  ElectionFailed(String electionId, this.reason) : super(electionId, DateTime.now());
}

/// Common election strategies
class FirstNodeElectionStrategy implements ElectionStrategy {
  const FirstNodeElectionStrategy();
  
  @override
  bool shouldBecomeLeader(String nodeId, List<NetworkNode> candidates, Map<String, dynamic> context) {
    if (candidates.isEmpty) return true;
    candidates.sort((a, b) => a.nodeId.compareTo(b.nodeId));
    return candidates.first.nodeId == nodeId;
  }
  
  @override
  double calculatePriority(NetworkNode node, Map<String, dynamic> context) {
    // Use negative hash to prioritize earlier nodes
    return -node.nodeId.hashCode.toDouble();
  }
}

class CapabilityBasedElectionStrategy implements ElectionStrategy {
  final String capabilityKey;
  final bool higherIsBetter;
  
  const CapabilityBasedElectionStrategy(
    this.capabilityKey, {
    this.higherIsBetter = true,
  });
  
  @override
  bool shouldBecomeLeader(String nodeId, List<NetworkNode> candidates, Map<String, dynamic> context) {
    if (candidates.isEmpty) return true;
    
    final thisNode = candidates.firstWhere((n) => n.nodeId == nodeId);
    final thisPriority = calculatePriority(thisNode, context);
    
    for (final candidate in candidates) {
      final candidatePriority = calculatePriority(candidate, context);
      if (higherIsBetter ? candidatePriority > thisPriority : candidatePriority < thisPriority) {
        return false;
      }
    }
    
    return true;
  }
  
  @override
  double calculatePriority(NetworkNode node, Map<String, dynamic> context) {
    final value = node.metadata[capabilityKey] as num? ?? 0;
    return value.toDouble();
  }
}