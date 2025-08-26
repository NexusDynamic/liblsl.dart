import 'package:liblsl_coordinator/interfaces.dart';
import 'package:liblsl_coordinator/logging.dart';
import 'package:meta/meta.dart';
import 'package:collection/collection.dart';
import 'dart:math';

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

class NodeConfig implements IConfig, IUniqueIdentity, IHasMetadata {
  @override
  final String uId;

  /// Identifier for the node (for logging and identification purposes).
  /// If not provided, the hashCode of the object will be used.
  @override
  String get id => suppliedId ?? 'node-${hashCode.toString()}';

  /// Human-readable name for the node.
  @override
  final String name;

  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => Map.unmodifiable(_metadata);

  @override
  String? get description => 'Configuration for node $name (id: $id)';

  /// Internal storage for the id, if provided.
  final String? suppliedId;

  /// Type of the node.
  /// This is a [NodeCapability] enum value.
  final Set<NodeCapability> capabilities;

  /// Creates a new [NodeConfig] with the given parameters.
  /// If [id] is not provided, an ID based on the hashCode will be used.
  ///   The [id] is not guaranteed to be unique, and should be used only for
  ///   logging and identification purposes.
  /// The [name] is a human-readable name for the node.
  /// The [capabilities] is a set of [NodeCapability] enum values that
  ///  define the maximum capabilities of the node.
  /// By default, the node is a participant node.
  /// The [uId] is a unique identifier for the node
  ///   Note: this should generally not be set manually, and should be
  ///   generated automatically, the argument is there to allow mirroring
  ///  of existing /found nodes, and maintain their uId.
  NodeConfig({
    required this.name,
    String? id,
    String? uId,
    this.capabilities = const {NodeCapability.participant},
    Map<String, dynamic>? metadata,
  }) : suppliedId = id,
       uId = uId ?? Uuid().v4(),
       _metadata = metadata ?? {} {
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
  dynamic getMetadata(String key, {dynamic defaultValue}) {
    return _metadata[key] ?? defaultValue;
  }

  void setMetadata(String key, dynamic value) {
    _metadata[key] = value;
  }

  /// Converts the configuration to a map representation.
  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'id': id,
      'capabilities': capabilities.map((e) => e.toString()).toList(),
      'uId': uId,
      'metadata': _metadata,
    };
  }

  /// Creates a copy of the configuration with the given parameters.
  /// If a parameter is not provided, the value from the current
  /// configuration is used.
  @override
  NodeConfig copyWith({
    String? name,
    String? id,
    String? uId,
    Set<NodeCapability>? capabilities,
    Map<String, dynamic>? metadata,
  }) {
    return NodeConfig(
      name: name ?? this.name,
      id: id ?? this.id,
      uId: uId ?? this.uId,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? _metadata,
    );
  }

  @override
  String toString() {
    return 'NodeConfig(uId: $uId, name: $name, id: $id, capabilities: $capabilities)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NodeConfig &&
        other.runtimeType == runtimeType &&
        other.uId == uId &&
        other.name == name &&
        other.suppliedId == suppliedId &&
        other.capabilities == capabilities &&
        const DeepCollectionEquality().equals(other._metadata, _metadata);
  }

  @override
  int get hashCode {
    return uId.hashCode ^
        name.hashCode ^
        suppliedId.hashCode ^
        capabilities.hashCode ^
        const DeepCollectionEquality().hash(_metadata);
  }
}

/// Factory for creating [NodeConfig] objects.
class NodeConfigFactory implements IConfigFactory<NodeConfig> {
  /// Returns the default / basic config
  @override
  NodeConfig defaultConfig() {
    return NodeConfig(
      name: 'Default Node',
      id: 'node-${Random().nextInt(10000)}',
      capabilities: {NodeCapability.coordinator, NodeCapability.participant},
    );
  }

  /// Creates a config from a map
  @override
  NodeConfig fromMap(Map<String, dynamic> map) {
    return NodeConfig(
      name: map['name'] ?? 'Default Node',
      id: map['id'] ?? 'node-${Random().nextInt(10000)}',
      capabilities:
          (map['capabilities'] as List<dynamic>?)
              ?.map(
                (e) => NodeCapability.values.firstWhere(
                  (cap) => cap.toString() == e,
                  orElse: () => NodeCapability.participant,
                ),
              )
              .toSet() ??
          {NodeCapability.participant},
    );
  }
}

/// Configuration for the LSL transport.
class Node implements IConfigurable<NodeConfig>, IUniqueIdentity, IHasMetadata {
  @override
  String get uId => config.uId;

  /// Unique identifier for the node.
  @override
  String get id => config.id;

  /// Human-readable name for the node.
  @override
  String get name => config.name;

  @override
  String? get description => 'Node $name (id: $id)';

  /// Configuration for the node.
  /// This is a [NodeConfig] object.
  @override
  final NodeConfig config;

  late DateTime _lastSeen;
  DateTime get lastSeen => _lastSeen;

  final DateTime _createdAt = DateTime.now();
  DateTime get createdAt => _createdAt;

  /// The node's reported start time.
  DateTime? _nodeStartedAt;
  DateTime? get nodeStartedAt => _nodeStartedAt;

  DateTime? _promotedAt;

  DateTime? get promotedAt => _promotedAt;

  @override
  Map<String, dynamic> get metadata => config.metadata;

  /// Type of the node.
  /// This is a [NodeCapability] enum value.
  Set<NodeCapability> get capabilities => config.capabilities;

  Node(this.config) {
    if (!config.validate()) {
      throw ArgumentError('Invalid node configuration: ${config.toMap()}');
    }
    _lastSeen = DateTime.now();
    setMetadata('type', config.capabilities.join(','));
    setMetadata('randomRoll', Random().nextDouble().toString());
    setMetadata('role', 'none');
    setMetadata('createdAt', _createdAt.toIso8601String());
    setMetadata('id', id);
    setMetadata('uId', id);
    setMetadata('name', name);
    setMetadata('version', '1.0.0');
    setMetadata('nodeStartedAt', _nodeStartedAt?.toIso8601String() ?? '');
  }

  @protected
  void seen() {
    _lastSeen = DateTime.now();
  }

  void setMetadata(String key, dynamic value) {
    config.setMetadata(key, value);
  }

  @override
  dynamic getMetadata(String key, {dynamic defaultValue}) {
    return config.getMetadata(key, defaultValue: defaultValue);
  }

  /// Attempts to promote the current node to an [ObserverNode].
  ObserverNode get asObserver {
    if (!NodeCapabilityExtension.mayBePromoted(
      capabilities,
      NodeCapability.observer,
    )) {
      throw StateError('Node cannot be promoted to Observer');
    }
    _promotedAt = DateTime.now();
    setMetadata('role', 'observer');
    logger.finest('Node $name promoted to Observer');
    return this as ObserverNode;
  }

  /// Attempts to promote the current node to a [ParticipantNode].
  ParticipantNode get asParticipant {
    if (!NodeCapabilityExtension.mayBePromoted(
      capabilities,
      NodeCapability.participant,
    )) {
      throw StateError('Node cannot be promoted to Participant');
    }
    _promotedAt = DateTime.now();
    setMetadata('role', 'participant');
    logger.finest('Node $name promoted to Participant');
    return this as ParticipantNode;
  }

  /// Attempts to promote the current node to a [RelayNode].
  RelayNode get asRelay {
    if (!NodeCapabilityExtension.mayBePromoted(
      capabilities,
      NodeCapability.relay,
    )) {
      throw StateError('Node cannot be promoted to Relay');
    }
    _promotedAt = DateTime.now();
    setMetadata('role', 'relay');
    logger.finest('Node $name promoted to Relay');
    return this as RelayNode;
  }

  /// Attempts to promote the current node to a [TransformerNode].
  TransformerNode get asTransformer {
    if (!NodeCapabilityExtension.mayBePromoted(
      capabilities,
      NodeCapability.transformer,
    )) {
      throw StateError('Node cannot be promoted to Transformer');
    }
    _promotedAt = DateTime.now();
    setMetadata('role', 'transformer');
    logger.finest('Node $name promoted to Transformer');
    return this as TransformerNode;
  }

  /// Attempts to promote the current node to a [CoordinatorNode].
  CoordinatorNode get asCoordinator {
    if (!NodeCapabilityExtension.mayBePromoted(
      capabilities,
      NodeCapability.coordinator,
    )) {
      throw StateError('Node cannot be promoted to Coordinator');
    }
    _promotedAt = DateTime.now();
    setMetadata('role', 'coordinator');
    logger.finest('Node $name promoted to Coordinator');
    return this as CoordinatorNode;
  }
}

/// A node that does not participate in the network at all.
class NullNode extends Node {
  @override
  String? get description => 'Null Node (id: $id)';
  NullNode()
    : super(
        NodeConfig(
          name: 'Null Node',
          id: 'null-node',
          capabilities: {NodeCapability.none},
        ),
      );
}

/// Observer nodes can only observe the network, and cannot
/// participate in sending data or and cannot coordinate. They can
/// receive coordination messages, but cannot send them.
class ObserverNode extends Node {
  @override
  String? get description => 'Observer Node $name (id: $id)';
  ObserverNode(super.config) : super() {
    setMetadata('role', 'observer');
  }
}

/// Participant nodes can produce and consume data, but cannot
/// participate in coordination (but will receive coordination messages).
class ParticipantNode extends Node {
  @override
  String? get description => 'Participant Node $name (id: $id)';
  ParticipantNode(super.config) : super() {
    setMetadata('role', 'participant');
  }
}

/// Coordinator nodes can coordinate the network, and may also participate
/// in data streams (if they have the capability).
class CoordinatorNode extends Node {
  @override
  String? get description => 'Coordinator Node $name (id: $id)';
  CoordinatorNode(super.config) : super() {
    setMetadata('role', 'coordinator');
  }
}

/// Relay nodes can relay data between nodes, but cannot
/// produce or consume data (non-relayed) themselves.
class RelayNode extends Node {
  @override
  String? get description => 'Relay Node $name (id: $id)';
  RelayNode(super.config) : super() {
    setMetadata('role', 'relay');
  }
}

/// Transformer nodes are a special case of relay nodes that can
/// also transform data as it passes through them.
class TransformerNode extends Node {
  @override
  String? get description => 'Transformer Node $name (id: $id)';
  TransformerNode(super.config) : super() {
    setMetadata('role', 'transformer');
  }
}
