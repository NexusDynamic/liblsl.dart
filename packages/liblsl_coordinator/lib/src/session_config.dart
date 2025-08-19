import 'session/coordination_session.dart';

// Forward declaration - NetworkSession will be defined by transport implementations
abstract class NetworkSession {
  String get sessionId;
  SessionState get state;
  NetworkTopology get topology;
  NodeRole get role;
  List<NetworkNode> get nodes;
  
  // Core session operations
  Future<void> join();
  Future<void> leave();
  
  // Event stream
  Stream<SessionEvent> get events;
}

/// Configuration for network connection limits and behavior
class ConnectionConfig {
  /// Maximum number of peer connections in P2P or hybrid topologies
  final int maxPeerConnections;
  
  /// Maximum number of client connections to monitor (server role)
  final int maxClientConnections;
  
  /// Maximum number of leader connections in hybrid topology
  final int maxLeaderConnections;
  
  /// Whether to enable redundant coordinator connections
  final bool enableRedundantConnections;
  
  /// How long to remember disconnected nodes/streams (seconds)
  final double forgetAfter;
  
  const ConnectionConfig({
    this.maxPeerConnections = 10,
    this.maxClientConnections = 50,
    this.maxLeaderConnections = 5,
    this.enableRedundantConnections = true,
    this.forgetAfter = 10.0,
  });
  
  /// Create a configuration optimized for small lab setups
  factory ConnectionConfig.smallLab() => const ConnectionConfig(
    maxPeerConnections: 5,
    maxClientConnections: 20,
    maxLeaderConnections: 3,
  );
  
  /// Create a configuration optimized for large experiments
  factory ConnectionConfig.largeLab() => const ConnectionConfig(
    maxPeerConnections: 20,
    maxClientConnections: 100,
    maxLeaderConnections: 10,
  );
}

/// Universal configuration for creating coordination sessions
/// 
/// This provides a transport-agnostic way to configure sessions while
/// allowing transport-specific extensions via metadata
class SessionConfig {
  /// Unique identifier for this session
  final String sessionId;
  
  /// Unique identifier for this node
  final String nodeId;
  
  /// Human-readable name for this node
  final String nodeName;
  
  /// Expected network topology
  final NetworkTopology topology;
  
  /// Session-level metadata
  final Map<String, dynamic> sessionMetadata;
  
  /// Node-level metadata (capabilities, device info, etc.)
  final Map<String, dynamic> nodeMetadata;
  
  /// Heartbeat interval for node presence
  final Duration heartbeatInterval;
  
  /// Transport-specific configuration
  final Map<String, dynamic> transportConfig;
  
  /// Connection configuration for network topology management
  final ConnectionConfig connectionConfig;
  
  const SessionConfig({
    required this.sessionId,
    required this.nodeId,
    required this.nodeName,
    required this.topology,
    this.sessionMetadata = const {},
    this.nodeMetadata = const {},
    this.heartbeatInterval = const Duration(seconds: 5),
    this.transportConfig = const {},
    this.connectionConfig = const ConnectionConfig(),
  });
  
  /// Create a copy with updated values
  SessionConfig copyWith({
    String? sessionId,
    String? nodeId,
    String? nodeName,
    NetworkTopology? topology,
    Map<String, dynamic>? sessionMetadata,
    Map<String, dynamic>? nodeMetadata,
    Duration? heartbeatInterval,
    Map<String, dynamic>? transportConfig,
    ConnectionConfig? connectionConfig,
  }) {
    return SessionConfig(
      sessionId: sessionId ?? this.sessionId,
      nodeId: nodeId ?? this.nodeId,
      nodeName: nodeName ?? this.nodeName,
      topology: topology ?? this.topology,
      sessionMetadata: sessionMetadata ?? this.sessionMetadata,
      nodeMetadata: nodeMetadata ?? this.nodeMetadata,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      transportConfig: transportConfig ?? this.transportConfig,
      connectionConfig: connectionConfig ?? this.connectionConfig,
    );
  }
  
  /// Add transport-specific configuration
  SessionConfig withTransportConfig(String key, dynamic value) {
    final newConfig = Map<String, dynamic>.from(transportConfig);
    newConfig[key] = value;
    return copyWith(transportConfig: newConfig);
  }
  
  /// Add node capability metadata
  SessionConfig withCapability(String capability, dynamic value) {
    final newMetadata = Map<String, dynamic>.from(nodeMetadata);
    newMetadata[capability] = value;
    return copyWith(nodeMetadata: newMetadata);
  }
}

/// Result of session creation
class SessionResult {
  /// The created network session
  final NetworkSession session;
  
  /// Transport that was used
  final String transportUsed;
  
  /// Additional information about session creation
  final Map<String, dynamic> metadata;
  
  const SessionResult({
    required this.session,
    required this.transportUsed,
    this.metadata = const {},
  });
}