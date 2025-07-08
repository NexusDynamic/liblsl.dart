import 'package:meta/meta.dart';

/// Configuration for coordination behavior
@immutable
class CoordinationConfig {
  /// How often to send discovery messages (seconds)
  final double discoveryInterval;

  /// How often to send heartbeats (seconds)
  final double heartbeatInterval;

  /// How long to wait before considering a node dead (seconds)
  final double nodeTimeout;

  /// How long to wait for join responses (seconds)
  final double joinTimeout;

  /// Maximum number of nodes in the network
  final int maxNodes;

  /// Whether to auto-promote to coordinator if needed
  final bool autoPromote;

  /// Whether nodes should receive their own messages (for gaming scenarios)
  final bool receiveOwnMessages;

  /// Custom capabilities for this node
  final Map<String, dynamic> capabilities;

  const CoordinationConfig({
    this.discoveryInterval = 2.0,
    this.heartbeatInterval = 1.0,
    this.nodeTimeout = 5.0,
    this.joinTimeout = 10.0,
    this.maxNodes = 50,
    this.autoPromote = true,
    this.receiveOwnMessages = true,
    this.capabilities = const {},
  });

  CoordinationConfig copyWith({
    double? discoveryInterval,
    double? heartbeatInterval,
    double? nodeTimeout,
    double? joinTimeout,
    int? maxNodes,
    bool? autoPromote,
    bool? receiveOwnMessages,
    Map<String, dynamic>? capabilities,
  }) {
    return CoordinationConfig(
      discoveryInterval: discoveryInterval ?? this.discoveryInterval,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      nodeTimeout: nodeTimeout ?? this.nodeTimeout,
      joinTimeout: joinTimeout ?? this.joinTimeout,
      maxNodes: maxNodes ?? this.maxNodes,
      autoPromote: autoPromote ?? this.autoPromote,
      receiveOwnMessages:
          receiveOwnMessages ?? this.receiveOwnMessages,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}
