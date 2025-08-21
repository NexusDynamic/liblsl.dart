import 'package:liblsl_coordinator/interfaces.dart';

/// Represents the type of a node in the network.
/// Type, in this case means essentially the MAXIMUM privileges
/// and capabilities of the node in the network.
/// An observer node, will never be allowed to produce data,
/// while a coordinator node will be able to produce coordination
/// messages, but will not be able to produce data in data streams.
enum NodeCapability {
  none,
  observer,
  participant,
  relay,
  transformer,
  coordinator,
}

extension NodeCapabilityExtension on NodeCapability {
  static bool mayProduceData(Set<NodeCapability> capabilities) {
    return !capabilities.contains(NodeCapability.none) &&
            capabilities.contains(NodeCapability.participant) ||
        capabilities.contains(NodeCapability.relay) ||
        capabilities.contains(NodeCapability.transformer);
  }

  static bool mayProduceCoordination(Set<NodeCapability> capabilities) {
    return !capabilities.contains(NodeCapability.none) &&
            capabilities.contains(NodeCapability.coordinator) ||
        capabilities.contains(NodeCapability.relay);
  }

  static bool mayConsumeData(Set<NodeCapability> capabilities) {
    return !capabilities.contains(NodeCapability.none) &&
            capabilities.contains(NodeCapability.observer) ||
        capabilities.contains(NodeCapability.participant) ||
        capabilities.contains(NodeCapability.relay) ||
        capabilities.contains(NodeCapability.transformer);
  }

  static bool mayConsumeCoordination(Set<NodeCapability> capabilities) {
    return !capabilities.contains(NodeCapability.none);
  }

  static bool mayProcessData(Set<NodeCapability> capabilities) {
    return capabilities.contains(NodeCapability.transformer);
  }

  static bool mayBePromoted(
    Set<NodeCapability> capabilities,
    NodeCapability target,
  ) {
    if (capabilities.contains(NodeCapability.none)) return false;
    if (target == NodeCapability.none) return false;
    if (target == NodeCapability.observer) return true;
    if (target == NodeCapability.participant) {
      return capabilities.contains(NodeCapability.participant);
    }
    if (target == NodeCapability.relay) {
      return !capabilities.contains(NodeCapability.observer);
    }
    if (target == NodeCapability.transformer) {
      return capabilities.contains(NodeCapability.transformer);
    }
    if (target == NodeCapability.coordinator) {
      return capabilities.contains(NodeCapability.coordinator);
    }
    return false;
  }
}

class NodeConfig implements IConfig {
  /// Human-readable name for the node.
  final String name;

  /// Unique identifier for the node.
  final String id;

  /// Type of the node.
  /// This is a [NodeCapability] enum value.
  final Set<NodeCapability> capabilities;

  NodeConfig({
    required this.name,
    required this.id,
    this.capabilities = const {NodeCapability.participant},
  }) {
    validate(throwOnError: true);
  }

  /// Validates the configuration.
  @override
  bool validate({bool throwOnError = false}) {
    if (name.isEmpty) {
      if (throwOnError) {
        throw ArgumentError('Node name cannot be empty');
      }
      return false;
    }
    if (id.isEmpty) {
      if (throwOnError) {
        throw ArgumentError('Node ID cannot be empty');
      }
      return false;
    }
    return true;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'id': id,
      'capabilities': capabilities.map((e) => e.toString()).toList(),
    };
  }

  @override
  NodeConfig copyWith({
    String? name,
    String? id,
    Set<NodeCapability>? capabilities,
  }) {
    return NodeConfig(
      name: name ?? this.name,
      id: id ?? this.id,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  @override
  String toString() {
    return 'NodeConfig(name: $name, id: $id, capabilities: $capabilities)';
  }
}

abstract class Node implements IConfigurable<NodeConfig>, IUniqueIdentity {
  /// Unique identifier for the node.
  @override
  String get id => config.id;

  /// Human-readable name for the node.
  @override
  String get name => config.name;

  /// Configuration for the node.
  /// This is a [NodeConfig] object.
  @override
  final NodeConfig config;

  /// Type of the node.
  /// This is a [NodeCapability] enum value.
  Set<NodeCapability> get capabilities => config.capabilities;

  Node(this.config) {
    if (!config.validate()) {
      throw ArgumentError('Invalid node configuration: ${config.toMap()}');
    }
  }

  ObserverNode get asObserver =>
      NodeCapabilityExtension.mayBePromoted(
            capabilities,
            NodeCapability.observer,
          )
          ? this as ObserverNode
          : throw StateError('Node cannot be promoted to Observer');

  ParticipantNode get asParticipant =>
      NodeCapabilityExtension.mayBePromoted(
            capabilities,
            NodeCapability.participant,
          )
          ? this as ParticipantNode
          : throw StateError('Node cannot be promoted to Participant');

  RelayNode get asRelay =>
      NodeCapabilityExtension.mayBePromoted(capabilities, NodeCapability.relay)
          ? this as RelayNode
          : throw StateError('Node cannot be promoted to Relay');

  TransformerNode get asTransformer =>
      NodeCapabilityExtension.mayBePromoted(
            capabilities,
            NodeCapability.transformer,
          )
          ? this as TransformerNode
          : throw StateError('Node cannot be promoted to Transformer');

  CoordinatorNode get asCoordinator =>
      NodeCapabilityExtension.mayBePromoted(
            capabilities,
            NodeCapability.coordinator,
          )
          ? this as CoordinatorNode
          : throw StateError('Node cannot be promoted to Coordinator');

  ParticipatingCoordinatorNode get asParticipatingCoordinator =>
      NodeCapabilityExtension.mayBePromoted(
            capabilities,
            NodeCapability.coordinator,
          )
          ? this as ParticipatingCoordinatorNode
          : throw StateError(
            'Node cannot be promoted to Participating Coordinator',
          );
}

abstract class ObserverNode extends Node {
  ObserverNode(super.config);
}

abstract class ParticipantNode extends Node {
  ParticipantNode(super.config);
}

abstract class CoordinatorNode extends Node {
  CoordinatorNode(super.config);
}

abstract class ParticipatingCoordinatorNode extends Node {
  ParticipatingCoordinatorNode(super.config);
}

abstract class RelayNode extends Node {
  RelayNode(super.config);
}

abstract class TransformerNode extends Node {
  TransformerNode(super.config);
}
