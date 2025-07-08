import 'dart:async';

import '../core/coordination_node.dart';
import '../lsl/lsl_coordination_node.dart';

/// Extension methods for easier coordination usage
extension CoordinationNodeExtensions on CoordinationNode {
  /// Wait for the node to reach a specific role
  Future<void> waitForRole(NodeRole targetRole, {Duration? timeout}) async {
    if (role == targetRole) return;

    final completer = Completer<void>();
    late StreamSubscription subscription;

    subscription = eventStream.listen((event) {
      if (event is RoleChangedEvent && event.newRole == targetRole) {
        subscription.cancel();
        completer.complete();
      }
    });

    if (timeout != null) {
      Timer(timeout, () {
        if (!completer.isCompleted) {
          subscription.cancel();
          completer.completeError(
            TimeoutException('Role change timeout', timeout),
          );
        }
      });
    }

    return completer.future;
  }

  /// Wait for a specific number of nodes to join
  Future<List<NetworkNode>> waitForNodes(int count, {Duration? timeout}) async {
    if (this is LSLCoordinationNode) {
      final lslNode = this as LSLCoordinationNode;
      if (lslNode.knownNodes.length >= count) {
        return lslNode.knownNodes;
      }

      final completer = Completer<List<NetworkNode>>();
      late StreamSubscription subscription;

      subscription = eventStream.listen((event) {
        if (event is TopologyChangedEvent && event.nodes.length >= count) {
          subscription.cancel();
          completer.complete(event.nodes);
        }
      });

      if (timeout != null) {
        Timer(timeout, () {
          if (!completer.isCompleted) {
            subscription.cancel();
            completer.completeError(
              TimeoutException('Node count timeout', timeout),
            );
          }
        });
      }

      return completer.future;
    }

    throw UnsupportedError(
      'waitForNodes only supported on LSLCoordinationNode',
    );
  }
}
