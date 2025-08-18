import 'dart:async';
import '../../../protocol/election_protocol.dart';
import '../../../session/coordination_session.dart';
import '../../../utils/logging.dart';

/// LSL-based implementation of ElectionProtocol
///
/// Simple implementation that uses the FirstNodeElectionStrategy
class LSLElectionProtocol extends ElectionProtocol {
  final String nodeId;
  final String sessionId;
  final ElectionStrategy _strategy;

  final StreamController<ElectionEvent> _eventController =
      StreamController<ElectionEvent>.broadcast();

  bool _isInitialized = false;

  LSLElectionProtocol({
    required this.nodeId,
    required this.sessionId,
    ElectionStrategy? strategy,
  }) : _strategy = strategy ?? const FirstNodeElectionStrategy();

  @override
  String get name => 'LSLElectionProtocol';

  @override
  String get version => '1.0.0';

  @override
  Stream<ElectionEvent> get electionEvents => _eventController.stream;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    logger.info('Initializing LSL election protocol for node $nodeId');
    _isInitialized = true;
    logger.info('LSL election protocol initialized');
  }

  @override
  Future<void> dispose() async {
    if (!_isInitialized) return;

    logger.info('Disposing LSL election protocol');
    await _eventController.close();
    _isInitialized = false;
  }

  @override
  Future<ElectionResult> startElection(List<NetworkNode> candidates) async {
    if (!_isInitialized) {
      throw StateError('Election protocol not initialized');
    }

    final electionId =
        '${sessionId}_election_${DateTime.now().millisecondsSinceEpoch}';
    logger.info(
      'Starting election $electionId with ${candidates.length} candidates',
    );

    // Emit election started event
    _eventController.add(ElectionStarted(electionId, candidates));

    // Use strategy to determine winner
    NetworkNode? winner;
    final votes = <String, int>{};

    try {
      // Simple deterministic election based on strategy
      for (final candidate in candidates) {
        final priority = _strategy.calculatePriority(candidate, {
          'sessionId': sessionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        votes[candidate.nodeId] = priority.round();
      }

      // Find candidate with highest priority
      if (votes.isNotEmpty) {
        final winnerNodeId =
            votes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
        winner = candidates.firstWhere((n) => n.nodeId == winnerNodeId);
      }

      final result = ElectionResult(
        electionId: electionId,
        winner: winner,
        candidates: candidates,
        votes: votes,
        completedAt: DateTime.now(),
      );

      logger.info(
        'Election $electionId completed - winner: ${winner?.nodeId ?? "none"}',
      );
      _eventController.add(ElectionCompleted(electionId, result));

      return result;
    } catch (e) {
      logger.severe('Election $electionId failed: $e');
      _eventController.add(
        ElectionFailed(electionId, 'Election process failed: $e'),
      );

      return ElectionResult(
        electionId: electionId,
        winner: null,
        candidates: candidates,
        votes: votes,
        completedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> vote(String electionId, String candidateId) async {
    if (!_isInitialized) {
      throw StateError('Election protocol not initialized');
    }

    logger.info('Node $nodeId voting for $candidateId in election $electionId');
    // In this simple implementation, votes are calculated automatically by strategy
    // In a more complex implementation, this would send vote messages via LSL
  }

  @override
  Future<void> handleElectionResult(ElectionResult result) async {
    if (!_isInitialized) {
      throw StateError('Election protocol not initialized');
    }

    logger.info(
      'Handling election result for ${result.electionId} - winner: ${result.winner?.nodeId ?? "none"}',
    );

    // In a more complex implementation, this would process the election result
    // and potentially trigger role changes, etc.
  }
}
