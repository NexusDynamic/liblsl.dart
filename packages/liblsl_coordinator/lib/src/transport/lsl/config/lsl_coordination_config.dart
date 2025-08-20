import '../../../session_config.dart';
import '../../../session/coordination_session.dart';

/// Configuration for LSL coordination session with user-configurable timeouts
class LSLCoordinationConfig extends SessionConfig {
  /// Discovery and network configuration
  final Duration nodeDiscoveryTimeout;
  final Duration nodeDiscoveryInterval;
  
  /// Resolver configuration
  final LSLResolverConfig resolverConfig;
  
  /// Connection limits
  final LSLConnectionLimits connectionLimits;
  
  /// Timer configuration
  final LSLTimerConfig timerConfig;
  
  const LSLCoordinationConfig({
    required super.sessionId,
    required super.nodeId,
    required super.nodeName,
    required super.topology,
    super.sessionMetadata,
    super.nodeMetadata,
    super.heartbeatInterval = const Duration(seconds: 5),
    super.transportConfig,
    super.connectionConfig,
    this.nodeDiscoveryTimeout = const Duration(seconds: 30),
    this.nodeDiscoveryInterval = const Duration(seconds: 5),
    this.resolverConfig = const LSLResolverConfig(),
    this.connectionLimits = const LSLConnectionLimits(),
    this.timerConfig = const LSLTimerConfig(),
  });
}

/// Configuration for LSL stream resolvers
class LSLResolverConfig {
  final double resolveWaitTime;
  final double forgetAfter;
  final int maxStreamsPerResolver;
  final Duration staleNodeThreshold;
  
  const LSLResolverConfig({
    this.resolveWaitTime = 5.0,
    this.forgetAfter = 5.0,
    this.maxStreamsPerResolver = 50,
    this.staleNodeThreshold = const Duration(seconds: 30),
  });
  
  /// Get predicate for data streams
  String dataPredicate(String streamName, {Map<String, String>? metadataFilters}) {
    var predicate = 'name="$streamName"';
    
    if (metadataFilters != null) {
      for (final entry in metadataFilters.entries) {
        predicate += ' and desc/${entry.key}="${entry.value}"';
      }
    }
    
    return predicate;
  }
  
  /// Get predicate for coordination streams
  String coordinationPredicate(String nodeRole) {
    return 'type="coordination_$nodeRole"';
  }
}

/// Connection limits for different node types
class LSLConnectionLimits {
  final int maxPeerConnections;
  final int maxClientConnections;
  final int maxLeaderConnections;
  final int maxNodes;
  
  const LSLConnectionLimits({
    this.maxPeerConnections = 10,
    this.maxClientConnections = 20,
    this.maxLeaderConnections = 5,
    this.maxNodes = 50,
  });
}

/// Timer configuration for periodic operations
class LSLTimerConfig {
  final Duration discoveryInterval;
  final Duration statePublishInterval;
  final Duration coordinationDiscoveryInterval;
  
  const LSLTimerConfig({
    this.discoveryInterval = const Duration(seconds: 10),
    this.statePublishInterval = const Duration(seconds: 3),
    this.coordinationDiscoveryInterval = const Duration(seconds: 2),
  });
}

/// Predefined topology configurations with sensible defaults
class LSLTopologyConfigs {
  /// Server-client topology configuration
  static LSLCoordinationConfig serverClient({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    bool canActAsServer = true,
    int maxClients = 10,
  }) {
    return LSLCoordinationConfig(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      topology: NetworkTopology.hierarchical,
      connectionLimits: LSLConnectionLimits(
        maxClientConnections: maxClients,
        maxLeaderConnections: 1,
      ),
      resolverConfig: const LSLResolverConfig(
        maxStreamsPerResolver: 25, // Smaller for client-server
      ),
    );
  }
  
  /// Peer-to-peer topology configuration
  static LSLCoordinationConfig peerToPeer({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    int maxPeers = 20,
  }) {
    return LSLCoordinationConfig(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      topology: NetworkTopology.peer2peer,
      connectionLimits: LSLConnectionLimits(
        maxPeerConnections: maxPeers,
        maxNodes: maxPeers + 5,
      ),
    );
  }
  
  /// Hybrid topology configuration
  static LSLCoordinationConfig hybrid({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    bool canActAsServer = true,
    int maxClients = 10,
    int maxPeers = 5,
  }) {
    return LSLCoordinationConfig(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      topology: NetworkTopology.hybrid,
      connectionLimits: LSLConnectionLimits(
        maxClientConnections: maxClients,
        maxPeerConnections: maxPeers,
        maxLeaderConnections: 3,
        maxNodes: maxClients + maxPeers + 5,
      ),
    );
  }
}