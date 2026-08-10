import 'package:peer_coordinator/interfaces.dart';
import 'package:peer_coordinator/network.dart';

/// Represents the network topology used in the coordinator system.
/// Currently, only hierarchical topology is supported.

// enum NodeRole { peer, coordinator, client }

abstract class TopologyConfig implements IConfig {
  int get maxNodes;
  NodeConfig get defaultNodeConfig;
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
      defaultNodeConfig: map['defaultNodeConfig'] != null
          ? NodeConfigFactory().fromMap(
              map['defaultNodeConfig'] as Map<String, dynamic>,
            )
          : null,
      defaultCoordinatorConfig: map['defaultCoordinatorConfig'] != null
          ? NodeConfigFactory().fromMap(
              map['defaultCoordinatorConfig'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}
