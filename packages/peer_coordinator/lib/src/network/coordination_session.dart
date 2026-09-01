import 'dart:async';

import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/config.dart';
import 'package:meta/meta.dart';

/// What a node does when the coordinator goes away.
///
/// "Goes away" covers both a coordinator that announced its departure and one
/// that simply stopped answering — see [SessionEndReason] for which happened.
///
/// This is deliberately a policy rather than a fixed behaviour: a research
/// paradigm whose coordinator drives the trial usually wants the run to end
/// (there is nothing to salvage), while a long-lived service wants the
/// survivors to carry on between themselves.
enum CoordinatorLossPolicy {
  /// The session is over. Stop the timers, drop the topology, emit
  /// [SessionEndedEvent], and refuse further sends. The application decides
  /// whether to build a fresh session.
  endSession,

  /// The survivors re-run the election and rebuild the session between
  /// themselves. Whichever node wins re-announces the coordinator role and the
  /// others re-join it.
  reelect,

  /// Keep trying to re-join a coordinator, staying a participant throughout.
  ///
  /// For a session with one authoritative coordinator that the participants
  /// cannot stand in for — a headless server driving an experiment, say. The
  /// node tears its role down, then retries [_connectToCoordinator] with
  /// backoff until a coordinator answers, and emits [SessionRejoinedEvent] when
  /// one does.
  ///
  /// This is the policy to want when a *transient* fault can evict a node that
  /// is otherwise healthy: [endSession] makes a network hiccup permanent, and
  /// [reelect] would promote a participant that has no business coordinating.
  rejoin,

  /// Do nothing beyond emitting [SessionEndedEvent].
  ///
  /// The pre-existing behaviour, kept as an escape hatch. Only sound if the
  /// application drives recovery itself off the event: nothing else in the
  /// session will notice that the coordinator is gone, so heartbeats and
  /// messages keep going out to a stream nobody consumes.
  remainOpen,
}

/// Why a session ended, as carried by [SessionEndedEvent] and
/// [SessionEndMessage].
enum SessionEndReason {
  /// The coordinator announced its own departure. A clean stop.
  coordinatorLeft,

  /// The coordinator stopped sending heartbeats for longer than
  /// [CoordinationSessionConfig.nodeTimeout].
  coordinatorTimedOut,

  /// The transport reported that the coordinator's endpoint is gone — a closed
  /// socket, say — before any timeout could elapse.
  coordinatorTransportLost,

  /// The coordinator evicted this node from the session.
  evicted,
}

class CoordinationSessionConfig implements IConfig {
  @override
  String get id => 'coordination-${hashCode.toString()}';

  /// Human-readable name for the session.
  @override
  final String name;

  @override
  String? get description =>
      'Configuration for coordination session $name (id: $id)';

  /// Maximum number of nodes allowed in the session.
  /// if [maxNodes] < 1, it means unlimited.
  final int maxNodes;

  /// Minimum number of nodes required in the session.
  final int minNodes;

  /// How often nodes should emit heartbeats to indicate they are alive.
  final Duration heartbeatInterval;

  /// How often to search for new nodes (should be less than [nodeTimeout]).
  final Duration discoveryInterval;

  /// The amount of time to wait before considering a node disconnected
  /// if no heartbeat is received.
  /// This should be at least twice the [heartbeatInterval].
  final Duration nodeTimeout;

  /// Determines whether on becoming coordinator, the node should
  /// also consume the coordination stream - specifically, this is used for
  /// a coordinator to be able to consume UserMessages (UserCoordinationMessage)
  /// within the coordination session, this allows for a session coordinator
  /// to also act as a participant in the session, and have similar latency
  /// characteristics as other nodes.
  /// Default is true.

  final bool consumeCoordinationStreamAsCoordinator;

  /// Tuning for peer clock-offset estimation.
  ///
  /// Only consulted by transports that need it — currently WebSocket. Defaults
  /// mirror liblsl's `[tuning]` section; raise [ClockSyncConfig.timeUpdateInterval]
  /// or lower [ClockSyncConfig.timeProbeCount] if the probe traffic is too
  /// costly for a large session, at the price of a staler estimate.
  final ClockSyncConfig clockSyncConfig;

  /// What this node does if the coordinator goes away.
  ///
  /// Defaults to [CoordinatorLossPolicy.endSession]: a session with no
  /// coordinator has no membership authority and no stream lifecycle, so
  /// carrying on is not a well-defined state. Pass
  /// [CoordinatorLossPolicy.reelect] to have the survivors continue between
  /// themselves.
  final CoordinatorLossPolicy coordinatorLossPolicy;

  CoordinationSessionConfig({
    required this.name,
    this.maxNodes = 10,
    this.minNodes = 1,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.discoveryInterval = const Duration(seconds: 10),
    this.nodeTimeout = const Duration(seconds: 15),
    this.consumeCoordinationStreamAsCoordinator = true,
    this.clockSyncConfig = const ClockSyncConfig(),
    this.coordinatorLossPolicy = CoordinatorLossPolicy.endSession,
  }) {
    validate(throwOnError: true);
  }

  /// Validates the configuration.
  @override
  bool validate({bool throwOnError = false}) {
    if (name.isEmpty) {
      if (throwOnError) {
        throw ArgumentError('Session name cannot be empty');
      }
      return false;
    }
    if (minNodes < 1) {
      if (throwOnError) {
        throw ArgumentError('Minimum nodes must be at least 1');
      }
      return false;
    }
    if (maxNodes >= 1 && maxNodes < minNodes) {
      if (throwOnError) {
        throw ArgumentError(
          'Max nodes must be greater than or equal to min nodes if specified',
        );
      }
      return false;
    }
    if (heartbeatInterval <= Duration.zero) {
      if (throwOnError) {
        throw ArgumentError('Heartbeat interval must be greater than 0');
      }
      return false;
    }
    if (discoveryInterval <= Duration.zero) {
      if (throwOnError) {
        throw ArgumentError('Discovery interval must be greater than 0');
      }
      return false;
    }
    if (nodeTimeout < heartbeatInterval * 2) {
      if (throwOnError) {
        throw ArgumentError(
          'Node timeout must be at least twice the heartbeat interval',
        );
      }
      return false;
    }
    if (!clockSyncConfig.validate(throwOnError: throwOnError)) return false;
    return true;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'maxNodes': maxNodes,
      'minNodes': minNodes,
      'heartbeatInterval': heartbeatInterval.inMilliseconds,
      'discoveryInterval': discoveryInterval.inMilliseconds,
      'nodeTimeout': nodeTimeout.inMilliseconds,
      'consumeCoordinationStreamAsCoordinator':
          consumeCoordinationStreamAsCoordinator,
      'coordinatorLossPolicy': coordinatorLossPolicy.name,
      'clockSync': {
        'timeUpdateInterval': clockSyncConfig.timeUpdateInterval.inMilliseconds,
        'timeProbeCount': clockSyncConfig.timeProbeCount,
        'timeProbeInterval': clockSyncConfig.timeProbeInterval.inMilliseconds,
        'timeProbeMaxRtt': clockSyncConfig.timeProbeMaxRtt.inMilliseconds,
        'timeUpdateMinProbes': clockSyncConfig.timeUpdateMinProbes,
      },
    };
  }

  @override
  String toString() {
    return 'NetworkSessionConfig(name: $name, maxNodes: $maxNodes, '
        'minNodes: $minNodes, heartbeatInterval: $heartbeatInterval, '
        'discoveryInterval: $discoveryInterval, nodeTimeout: $nodeTimeout, '
        'consumeCoordinationStreamAsCoordinator: '
        '$consumeCoordinationStreamAsCoordinator, '
        'coordinatorLossPolicy: ${coordinatorLossPolicy.name})';
  }

  @override
  CoordinationSessionConfig copyWith({
    String? name,
    int? maxNodes,
    int? minNodes,
    Duration? heartbeatInterval,
    Duration? discoveryInterval,
    Duration? nodeTimeout,
    bool? consumeCoordinationStreamAsCoordinator,
    ClockSyncConfig? clockSyncConfig,
    CoordinatorLossPolicy? coordinatorLossPolicy,
  }) {
    return CoordinationSessionConfig(
      name: name ?? this.name,
      maxNodes: maxNodes ?? this.maxNodes,
      minNodes: minNodes ?? this.minNodes,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      discoveryInterval: discoveryInterval ?? this.discoveryInterval,
      nodeTimeout: nodeTimeout ?? this.nodeTimeout,
      consumeCoordinationStreamAsCoordinator:
          consumeCoordinationStreamAsCoordinator ??
          this.consumeCoordinationStreamAsCoordinator,
      // Both used to be dropped here, silently resetting a tuned session to the
      // defaults on any copyWith.
      clockSyncConfig: clockSyncConfig ?? this.clockSyncConfig,
      coordinatorLossPolicy:
          coordinatorLossPolicy ?? this.coordinatorLossPolicy,
    );
  }

  static CoordinationSessionConfig standard() {
    return CoordinationSessionConfig(
      name: 'Default Coordination Session',
      maxNodes: 10,
      minNodes: 1,
      heartbeatInterval: const Duration(seconds: 5),
      discoveryInterval: const Duration(seconds: 10),
      nodeTimeout: const Duration(seconds: 15),
      consumeCoordinationStreamAsCoordinator: true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    // Deliberately not comparing [id]: it is derived from [hashCode], which is
    // derived from these fields, so reading it here recursed — id -> hashCode ->
    // id -> ... -> stack overflow — and was redundant with comparing the fields
    // themselves anyway.
    return other is CoordinationSessionConfig &&
        other.runtimeType == runtimeType &&
        other.name == name &&
        other.maxNodes == maxNodes &&
        other.minNodes == minNodes &&
        other.heartbeatInterval == heartbeatInterval &&
        other.discoveryInterval == discoveryInterval &&
        other.nodeTimeout == nodeTimeout &&
        other.consumeCoordinationStreamAsCoordinator ==
            consumeCoordinationStreamAsCoordinator &&
        other.coordinatorLossPolicy == coordinatorLossPolicy;
  }

  @override
  int get hashCode {
    // [id] is `'coordination-$hashCode'`, so hashing it here was infinite
    // recursion: any call to hashCode or == on this config overflowed the stack.
    // Nothing called them, which is why it went unnoticed.
    return name.hashCode ^
        maxNodes.hashCode ^
        minNodes.hashCode ^
        heartbeatInterval.hashCode ^
        discoveryInterval.hashCode ^
        nodeTimeout.hashCode ^
        consumeCoordinationStreamAsCoordinator.hashCode ^
        coordinatorLossPolicy.hashCode;
  }
}

class CoordinationSessionConfigFactory
    implements IConfigFactory<CoordinationSessionConfig> {
  @override
  CoordinationSessionConfig defaultConfig() {
    return CoordinationSessionConfig.standard();
  }

  @override
  CoordinationSessionConfig fromMap(Map<String, dynamic> map) {
    return CoordinationSessionConfig(
      name: map['name'] ?? 'Default Coordination Session',
      maxNodes: map['maxNodes'] ?? 10,
      minNodes: map['minNodes'] ?? 1,
      heartbeatInterval: Duration(
        milliseconds: map['heartbeatInterval'] ?? 5000,
      ),
      discoveryInterval: Duration(
        milliseconds: map['discoveryInterval'] ?? 10000,
      ),
      nodeTimeout: Duration(milliseconds: map['nodeTimeout'] ?? 15000),
      consumeCoordinationStreamAsCoordinator:
          map['consumeCoordinationStreamAsCoordinator'] ?? true,
      coordinatorLossPolicy:
          CoordinatorLossPolicy.values
              .where((p) => p.name == map['coordinatorLossPolicy'])
              .firstOrNull ??
          CoordinatorLossPolicy.endSession,
    );
  }
}

/// Abstract base class for coordination sessions.
abstract class CoordinationSession
    implements
        IResourceManager,
        IInitializable,
        ILifecycle,
        IJoinable,
        IPausable,
        IUniqueIdentity,
        IConfigurable<CoordinationSessionConfig> {
  /// Configuration for the coordination session.
  @override
  late final CoordinationSessionConfig config;

  /// Overall configration for Coordination, Session, Streams, Topology,
  /// Transport.
  /// This is a [CoordinationConfig] object.
  final CoordinationConfig coordinationConfig;

  /// Transport used for coordination.
  ITransport get transport;

  /// Human-readable name for the session.
  @override
  String get name => config.name;

  /// Unique identifier for the session.
  @override
  String get id => config.hashCode.toString();

  @override
  bool get created => _created;

  @override
  bool get initialized => _initialized;

  @override
  bool get joined => _joined;

  @override
  bool get disposed => _disposed;

  @override
  bool get paused => _paused;

  bool _created = false;
  bool _initialized = false;
  bool _joined = false;
  bool _disposed = false;
  bool _paused = false;

  late Node _thisNode;

  /// The node representing this instance in the coordination session.
  Node get thisNode => _thisNode;

  /// Unique identifier for the session.
  CoordinationSession(this.coordinationConfig, {NodeConfig? thisNodeConfig}) {
    config = coordinationConfig.sessionConfig;
    config.validate(throwOnError: true);
    _thisNode = Node(
      thisNodeConfig ?? coordinationConfig.topologyConfig.defaultNodeConfig,
    );
  }

  @override
  @mustCallSuper
  FutureOr<void> create() async {
    if (_created) return;
    _created = true;
  }

  @override
  @mustCallSuper
  FutureOr<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _created = false;
    _initialized = false;
    _joined = false;
    _paused = false;
  }

  @override
  @mustCallSuper
  FutureOr<void> initialize() async {
    if (_initialized) return;
    await create();
    _initialized = true;
  }

  @override
  @mustCallSuper
  FutureOr<void> join() async {
    if (_joined) return;
    _joined = true;
  }

  @override
  @mustCallSuper
  FutureOr<void> leave() async {
    if (!_joined) return;
    _joined = false;
  }

  @override
  @mustCallSuper
  FutureOr<void> pause() async {
    if (_paused) return;
    _paused = true;
  }

  @override
  @mustCallSuper
  FutureOr<void> resume() async {
    if (!_paused) return;
    _paused = false;
  }

  @protected
  void updateThisNode(Node node) {
    _thisNode = node;
  }
}

/// Promotion strategy
abstract class PromotionStrategy implements IIdentity {
  const PromotionStrategy();
}

class PromotionStrategyFirst extends PromotionStrategy {
  @override
  String get id => 'promote_first';

  @override
  String get name => 'First Promotion Strategy';

  @override
  String? get description =>
      'Promotes the first node with coordination capabilities that attempts to become the coordinator.';

  const PromotionStrategyFirst();

  Node promote(Iterable<Node> candidates) {
    if (candidates.isEmpty) {
      throw ArgumentError('No candidates provided for promotion');
    }
    // first filter candidates with coordination capabilities
    final filteredCandidates = candidates.where(
      (node) => node.capabilities.contains(NodeCapability.coordinator),
    );
    if (filteredCandidates.isEmpty) {
      throw ArgumentError('No candidates with coordinator capability found');
    }
    // Use the lowest candidate.nodeStartedAt if not null, otherwise the earliest createdAt
    final candidate = filteredCandidates.reduce((a, b) {
      final aStart = a.nodeStartedAt ?? a.createdAt;
      final bStart = b.nodeStartedAt ?? b.createdAt;
      return aStart.isBefore(bStart) ? a : b;
    });
    // Return the first candidate
    return candidate;
  }

  @override
  String toString() => 'PromotionStrategyFirst(id: $id, name: $name)';
}

class PromotionStrategyRandom extends PromotionStrategy {
  @override
  String get id => 'promote_random';

  @override
  String get name => 'Random Promotion Strategy';

  @override
  String? get description =>
      'Promotes a random node with coordination capabilities that attempts to become the coordinator.';

  Node promote(Iterable<Node> candidates) {
    if (candidates.isEmpty) {
      throw ArgumentError('No candidates provided for promotion');
    }
    // filter candidates with coordination capabilities
    final filteredCandidates = candidates.where(
      (node) => node.capabilities.contains(NodeCapability.coordinator),
    );
    if (filteredCandidates.isEmpty) {
      throw ArgumentError('No candidates with coordinator capability found');
    }
    // Select a random candidate based on the randomRoll metadata
    final candidate = filteredCandidates.reduce((a, b) {
      final aRoll =
          double.tryParse(a.getMetadata('randomRoll', defaultValue: '1.0')!) ??
          1.0;
      final bRoll =
          double.tryParse(b.getMetadata('randomRoll') ?? '1.0') ?? 1.0;
      return aRoll <= bRoll ? a : b;
    });

    // Return the selected candidate
    return candidate;
  }

  @override
  String toString() => 'PromotionStrategyRandom(id: $id, name: $name)';
}
