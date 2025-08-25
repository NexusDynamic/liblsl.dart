import 'package:liblsl_coordinator/interfaces.dart';
import 'package:liblsl_coordinator/network.dart';

/// Represents the network topology used in the coordinator system.
/// Currently, only hierarchical topology is supported.
enum TopologyType { hierarchical }

enum NodeRole { peer, coordinator, client }

abstract class TopologyConfig implements IConfig {
  int get maxNodes;
  NodeConfig get defaultNodeConfig;
}

abstract class NetworkTopology<T extends TopologyConfig>
    implements IIdentity, IConfigurable<T>, IHasMetadata {
  final Map<String, Node> _nodes = {};

  /// Adds a node to the network topology.
  void addNode(Node node) {
    if (_nodes.containsKey(node.id)) {
      throw ArgumentError('Node with id ${node.id} already exists');
    }
    _nodes[node.id] = node;
  }

  /// Removes a node from the network topology.
  void removeNode(String nodeId) {
    if (!_nodes.containsKey(nodeId)) {
      throw ArgumentError('Node with id $nodeId does not exist');
    }
    _nodes.remove(nodeId);
  }

  /// Convenience method to add multiple nodes to the network topology.
  void addNodes(Iterable<Node> nodes) {
    for (Node node in nodes) {
      addNode(node);
    }
  }

  /// Convenience method to remove multiple nodes from the network topology.
  void removeNodes(Iterable<String> nodeIds) {
    for (String nodeId in nodeIds) {
      removeNode(nodeId);
    }
  }
}

class HierarchicalTopologyConfig implements TopologyConfig {
  @override
  String get id => 'hierarchical_topology_config_${hashCode.toString()}';

  @override
  String get name => 'Hierarchical Network Topology Config';

  @override
  String? get description =>
      'Configuration for hierarchical network topology (id: $id)';

  @override
  final int maxNodes;

  /// Default configuration for nodes in the topology, it is a default
  /// because node roles may change depending on the topology state.
  /// For example, a node may be promoted to a coordinator role if needed.
  @override
  late final NodeConfig defaultNodeConfig;

  /// Default configuration for the coordinator node in the topology.
  /// This node will have the coordinator role by default.
  /// It can be promoted from a regular node if needed.
  late final NodeConfig defaultCoordinatorConfig;

  final bool autoPromotion;

  final PromotionStrategy? promotionStrategy;

  HierarchicalTopologyConfig({
    this.maxNodes = 100,
    this.autoPromotion = true,
    this.promotionStrategy = const PromotionStrategyFirst(),
    NodeConfig? defaultNodeConfig,
    NodeConfig? defaultCoordinatorConfig,
  }) {
    this.defaultNodeConfig =
        defaultNodeConfig ?? NodeConfigFactory().defaultConfig();
    this.defaultCoordinatorConfig =
        defaultCoordinatorConfig ?? NodeConfigFactory().defaultConfig();
    validate(throwOnError: true);
  }

  @override
  bool validate({bool throwOnError = false}) {
    if (maxNodes <= 0) {
      if (throwOnError) {
        throw ArgumentError('Max nodes must be greater than 0');
      }
      return false;
    }
    if (autoPromotion && promotionStrategy is! PromotionStrategy) {
      if (throwOnError) {
        throw ArgumentError('Invalid promotion strategy: $promotionStrategy');
      }
      return false;
    }
    if (!defaultNodeConfig.validate(throwOnError: false)) {
      if (throwOnError) {
        throw ArgumentError(
          'Invalid default node configuration: ${defaultNodeConfig.toMap()}',
        );
      }
      return false;
    }
    if (!defaultCoordinatorConfig.validate(throwOnError: false)) {
      if (throwOnError) {
        throw ArgumentError(
          'Invalid default coordinator configuration: ${defaultCoordinatorConfig.toMap()}',
        );
      }
      return false;
    }

    return true;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'maxNodes': maxNodes,
      'autoPromotion': autoPromotion,
      'promotionStrategy': promotionStrategy.toString(),
      'defaultNodeConfig': defaultNodeConfig.toMap(),
      'defaultCoordinatorConfig': defaultCoordinatorConfig.toMap(),
    };
  }

  @override
  HierarchicalTopologyConfig copyWith({
    int? maxNodes,
    bool? autoPromotion,
    PromotionStrategy? promotionStrategy,
    NodeConfig? defaultNodeConfig,
    NodeConfig? defaultCoordinatorConfig,
  }) {
    return HierarchicalTopologyConfig(
      maxNodes: maxNodes ?? this.maxNodes,
      autoPromotion: autoPromotion ?? this.autoPromotion,
      promotionStrategy: promotionStrategy ?? this.promotionStrategy,
      defaultNodeConfig: defaultNodeConfig,
      defaultCoordinatorConfig: defaultCoordinatorConfig,
    );
  }

  @override
  String toString() {
    return 'HierarchicalNetworkTopologyConfig(maxNodes: $maxNodes, autoPromotion: $autoPromotion, promotionStrategy: $promotionStrategy)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HierarchicalTopologyConfig &&
        other.runtimeType == runtimeType &&
        other.maxNodes == maxNodes &&
        other.autoPromotion == autoPromotion &&
        other.promotionStrategy == promotionStrategy &&
        other.defaultNodeConfig == defaultNodeConfig &&
        other.defaultCoordinatorConfig == defaultCoordinatorConfig;
  }

  @override
  int get hashCode =>
      maxNodes.hashCode ^
      autoPromotion.hashCode ^
      promotionStrategy.hashCode ^
      defaultNodeConfig.hashCode ^
      defaultCoordinatorConfig.hashCode;
}

class HierarchicalTopologyConfigFactory
    implements IConfigFactory<HierarchicalTopologyConfig> {
  @override
  HierarchicalTopologyConfig defaultConfig() {
    return HierarchicalTopologyConfig(
      maxNodes: 100,
      autoPromotion: true,
      promotionStrategy: const PromotionStrategyFirst(),
    );
  }

  @override
  HierarchicalTopologyConfig fromMap(Map<String, dynamic> map) {
    return HierarchicalTopologyConfig(
      maxNodes: map['maxNodes'] ?? 100,
      autoPromotion: map['autoPromotion'] ?? true,
      promotionStrategy:
          map['promotionStrategy'] ?? const PromotionStrategyFirst(),
      defaultNodeConfig:
          map['defaultNodeConfig'] != null
              ? NodeConfigFactory().fromMap(
                map['defaultNodeConfig'] as Map<String, dynamic>,
              )
              : null,
      defaultCoordinatorConfig:
          map['defaultCoordinatorConfig'] != null
              ? NodeConfigFactory().fromMap(
                map['defaultCoordinatorConfig'] as Map<String, dynamic>,
              )
              : null,
    );
  }
}

/// Hierarchical network topology used in the coordinator system.
class HierarchicalTopology<T extends HierarchicalTopologyConfig>
    extends NetworkTopology {
  @override
  final String id = 'hierarchical_topology';

  @override
  final String name = 'Hierarchical Network Topology';

  @override
  final String description =
      'A hierarchical network topology used in the coordinator system.';

  final Map<String, String> _metadata = {
    'type': TopologyType.hierarchical.toString(),
    'createdAt': DateTime.now().toIso8601String(),
    'version': '1.0.0',
  };

  @override
  Map<String, dynamic> get metadata => Map.unmodifiable(_metadata);

  /// Returns all nodes in the network topology.
  Map<String, Node> get nodes => Map.unmodifiable(_nodes);

  @override
  final HierarchicalTopologyConfig config;

  HierarchicalTopology({required this.config}) {
    if (!config.validate(throwOnError: true)) {
      throw ArgumentError(
        'Invalid network topology configuration: ${config.toMap()}',
      );
    }
  }

  @override
  dynamic getMetadata(String key, {dynamic defaultValue}) {
    return _metadata[key] ?? '';
  }
}
