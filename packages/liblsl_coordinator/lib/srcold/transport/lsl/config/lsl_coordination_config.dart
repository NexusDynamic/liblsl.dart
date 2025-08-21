import 'package:liblsl/lsl.dart';

import '../../../liblsl_coordinator.dart';
import '../../../session_config.dart';
import '../../../session/coordination_session.dart';
import 'lsl_stream_config.dart';

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

  /// Coordination stream configuration (restricted DataStream subtype)
  final LSLCoordinationStreamConfig coordinationStreamConfig;

  /// Default data stream configuration (for user-requested data streams)
  final LSLDataStreamConfig? defaultDataStreamConfig;

  LSLCoordinationConfig({
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
    LSLCoordinationStreamConfig? coordinationStreamConfig,
    this.defaultDataStreamConfig,
  }) : coordinationStreamConfig = LSLCoordinationStreamConfig(),
       super();
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
  String dataPredicate(
    String streamName, {
    Map<String, String>? metadataFilters,
  }) {
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
    return 'desc/type="coordination_$nodeRole"';
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

/// Configuration for coordination streams (restricted DataStream subtype)
/// Coordination streams handle network topology and communication between nodes
class LSLCoordinationStreamConfig extends LSLDataStreamConfig {
  /// Stream type identifier for coordination streams
  final String streamType;

  /// Whether coordination stream can be disabled (for testing)
  final bool enabled;

  LSLCoordinationStreamConfig({
    LSLPollingConfig? pollingConfig,
    this.streamType = 'coordination',
    this.enabled = true,
  }) : super(
         maxSampleRate: 20, // Default coordination rate
         channelCount: 1, // Single channel for coordination messages
         contentType: LSLContentType.markers, // String format for messages
         protocol: ProducerConsumerProtocol(),
         sourceId:
             'coordinator', // this IS NOT CORRECT LSL sourceId MUST be unique
         metadata: {'stream_purpose': 'coordination'},
         pollingConfig:
             pollingConfig ??
             const LSLPollingConfig(
               useBusyWait: false,
               usePollingIsolate: true,
               targetIntervalMicroseconds: 50000, // 20 Hz coordination
               bufferSize: 50,
               pullTimeout: 0.1,
             ),
       );

  /// Create minimal config for testing (no isolates)
  factory LSLCoordinationStreamConfig.testing() {
    return LSLCoordinationStreamConfig(
      pollingConfig: LSLPollingConfig(
        useBusyWait: false,
        usePollingIsolate: false,
        targetIntervalMicroseconds: 10000,
        bufferSize: 100,
        pullTimeout: 0.0,
      ),
      enabled: false,
    );
  }
}
