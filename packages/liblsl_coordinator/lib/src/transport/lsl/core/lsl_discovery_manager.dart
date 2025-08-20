import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../management/resource_manager.dart';
import '../../../event.dart';
import '../core/lsl_api_manager.dart';
import '../../../utils/logging.dart';
import '../../../utils/stream_controller_extensions.dart';

/// Discovery configuration for node roles and timeouts
class LSLDiscoveryConfig {
  final Duration? nodeDiscoveryTimeout;
  final Duration nodeDiscoveryInterval;
  final double resolverForgetAfter;
  final int maxStreamsPerResolver;
  
  const LSLDiscoveryConfig({
    this.nodeDiscoveryTimeout,
    this.nodeDiscoveryInterval = const Duration(seconds: 5),
    this.resolverForgetAfter = 5.0,
    this.maxStreamsPerResolver = 50,
  });
}

/// Node role definitions for discovery predicates
enum NodeRole {
  server,
  client, 
  peer,
  coordinator,
  custom;
  
  /// Get predicate for discovering this node role
  String predicate([Map<String, String>? metadata]) {
    switch (this) {
      case NodeRole.server:
        return 'type="coordination_server"';
      case NodeRole.client:
        return 'type="coordination_client"';
      case NodeRole.peer:
        return 'type="coordination_peer"';
      case NodeRole.coordinator:
        return 'type="coordination_coordinator"';
      case NodeRole.custom:
        return metadata?['predicate'] ?? '';
    }
  }
}

/// Manages LSL stream discovery without creating connections
/// Pure discovery layer - finds and catalogs available nodes/streams
class LSLDiscoveryManager implements ResourceManager {
  @override
  final String managerId;
  
  final String nodeId;
  final LSLDiscoveryConfig config;
  
  final Map<String, LSLStreamResolverContinuous> _activeResolvers = {};
  final Map<String, LSLStreamResolverContinuousByPredicate> _predicateResolvers = {};
  final Set<String> _erroredResources = {};
  
  final StreamController<LSLDiscoveryEvent> _discoveryEventController =
      StreamController<LSLDiscoveryEvent>.broadcast();
      
  bool _isActive = false;
  Timer? _discoveryTimer;
  
  late final ConfiguredLSL _lsl;

  LSLDiscoveryManager({
    required this.managerId,
    required this.nodeId,
    this.config = const LSLDiscoveryConfig(),
  }) {
    _lsl = LSLApiManager.lsl;
  }

  @override
  bool get isActive => _isActive;

  @override
  Stream<ResourceEvent> get events =>
      _discoveryEventController.stream.cast<ResourceEvent>();

  /// Stream of LSL-specific discovery events
  Stream<LSLDiscoveryEvent> get discoveryEvents =>
      _discoveryEventController.stream;

  @override
  Future<void> initialize() async {
    if (!LSLApiManager.isInitialized) {
      throw LSLApiConfigurationException(
        'LSL API must be initialized before creating discovery manager',
      );
    }
  }

  @override
  Future<void> start() async {
    _isActive = true;
    _discoveryEventController.addEvent(LSLDiscoveryManagerStarted(managerId));
    
    // Start periodic discovery timer if configured
    if (config.nodeDiscoveryTimeout != null) {
      _startDiscoveryTimer();
    }
  }

  @override
  Future<void> stop() async {
    // Stop discovery timer
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    
    // Stop all active resolvers but don't destroy them
    // (they may still be needed by coordination layer)
    
    _isActive = false;
    _discoveryEventController.addEvent(LSLDiscoveryManagerStopped(managerId));
  }

  @override
  Future<void> dispose() async {
    await stop();
    
    // Destroy all resolvers and clean up resources
    for (final resolver in _activeResolvers.values) {
      try {
        resolver.destroy();
      } catch (e) {
        logger.warning('Error destroying resolver: $e');
      }
    }
    
    for (final resolver in _predicateResolvers.values) {
      try {
        resolver.destroy();
      } catch (e) {
        logger.warning('Error destroying predicate resolver: $e');
      }
    }
    
    _activeResolvers.clear();
    _predicateResolvers.clear();
    _erroredResources.clear();
    
    try {
      await _discoveryEventController.close();
    } catch (e) {
      // Ignore errors during disposal
    }
  }

  @override
  ResourceUsageStats getUsageStats() {
    final totalResolvers = _activeResolvers.length + _predicateResolvers.length;
    
    return ResourceUsageStats(
      totalResources: totalResolvers,
      activeResources: _isActive ? totalResolvers : 0,
      idleResources: _isActive ? 0 : totalResolvers,
      erroredResources: _erroredResources.length,
      lastUpdated: DateTime.now(),
      customMetrics: {
        'continuousResolvers': _activeResolvers.length,
        'predicateResolvers': _predicateResolvers.length,
        'discoveryActive': _isActive,
      },
    );
  }

  /// Discover nodes by role using predicate-based continuous resolution
  Future<List<LSLStreamInfo>> discoverByRole(
    NodeRole role, {
    Map<String, String>? metadata,
    Duration? timeout,
  }) async {
    final predicate = role.predicate(metadata);
    return discoverByPredicate(predicate, timeout: timeout);
  }

  /// Discover streams using custom predicate with optional timeout
  Future<List<LSLStreamInfo>> discoverByPredicate(
    String predicate, {
    Duration? timeout,
  }) async {
    final resolverId = 'discovery_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // Create continuous resolver for this discovery
      final resolver = _createPredicateResolver(resolverId, predicate);
      
      // If timeout specified, resolve with blocking behavior
      if (timeout != null) {
        final streams = await resolver.resolve(waitTime: timeout.inMilliseconds / 1000.0);
        
        // Clean up temporary resolver
        _destroyResolver(resolverId);
        
        _discoveryEventController.addEvent(
          LSLNodesDiscovered(managerId, predicate, streams.length),
        );
        
        return streams;
      } else {
        // For continuous discovery, return empty list but keep resolver active
        _discoveryEventController.addEvent(
          LSLContinuousDiscoveryStarted(managerId, predicate),
        );
        return [];
      }
    } catch (e) {
      _discoveryEventController.addEvent(
        LSLDiscoveryError(managerId, 'Discovery failed for predicate $predicate: $e'),
      );
      rethrow;
    }
  }

  /// Start continuous discovery for a specific role
  /// Returns resolver ID for managing the discovery session
  String startContinuousDiscovery(
    NodeRole role, {
    Map<String, String>? metadata,
  }) {
    final predicate = role.predicate(metadata);
    return startContinuousDiscoveryByPredicate(predicate);
  }

  /// Start continuous discovery with custom predicate
  String startContinuousDiscoveryByPredicate(String predicate) {
    final resolverId = 'continuous_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      _createPredicateResolver(resolverId, predicate);
      
      _discoveryEventController.addEvent(
        LSLContinuousDiscoveryStarted(managerId, predicate),
      );
      
      return resolverId;
    } catch (e) {
      _discoveryEventController.addEvent(
        LSLDiscoveryError(managerId, 'Failed to start continuous discovery: $e'),
      );
      rethrow;
    }
  }

  /// Stop and destroy a continuous discovery session
  void stopContinuousDiscovery(String resolverId) {
    try {
      _destroyResolver(resolverId);
      
      _discoveryEventController.addEvent(
        LSLContinuousDiscoveryStopped(managerId, resolverId),
      );
    } catch (e) {
      _discoveryEventController.addEvent(
        LSLDiscoveryError(managerId, 'Error stopping continuous discovery $resolverId: $e'),
      );
    }
  }

  /// Get current discovered streams from a continuous resolver
  Future<List<LSLStreamInfo>> getDiscoveredStreams(String resolverId) async {
    final resolver = _predicateResolvers[resolverId];
    if (resolver == null) {
      throw LSLDiscoveryException('Resolver $resolverId not found');
    }
    
    try {
      // Get immediately available streams (non-blocking)
      return await resolver.resolve(waitTime: 0.0);
    } catch (e) {
      _discoveryEventController.addEvent(
        LSLDiscoveryError(managerId, 'Error getting streams from $resolverId: $e'),
      );
      rethrow;
    }
  }

  /// Create a predicate-based continuous resolver
  LSLStreamResolverContinuousByPredicate _createPredicateResolver(
    String resolverId,
    String predicate,
  ) {
    if (_predicateResolvers.containsKey(resolverId)) {
      throw LSLDiscoveryException('Resolver $resolverId already exists');
    }
    
    final resolver = _lsl.createContinuousStreamResolverByPredicate(
      predicate: predicate,
      forgetAfter: config.resolverForgetAfter,
      maxStreams: config.maxStreamsPerResolver,
    );
    
    _predicateResolvers[resolverId] = resolver;
    
    _discoveryEventController.addEvent(
      LSLResolverCreated(managerId, resolverId, predicate),
    );
    
    return resolver;
  }

  /// Destroy a resolver by ID
  void _destroyResolver(String resolverId) {
    // Try predicate resolvers first
    final predicateResolver = _predicateResolvers.remove(resolverId);
    if (predicateResolver != null) {
      predicateResolver.destroy();
      return;
    }
    
    // Try continuous resolvers
    final continuousResolver = _activeResolvers.remove(resolverId);
    if (continuousResolver != null) {
      continuousResolver.destroy();
      return;
    }
    
    throw LSLDiscoveryException('Resolver $resolverId not found');
  }

  /// Start the discovery timer for periodic node discovery
  void _startDiscoveryTimer() {
    _discoveryTimer = Timer.periodic(config.nodeDiscoveryInterval, (_) async {
      if (!_isActive) return;
      
      // Trigger discovery events for all active resolvers
      for (final entry in _predicateResolvers.entries) {
        try {
          final streams = await entry.value.resolve(waitTime: 0.0);
          _discoveryEventController.addEvent(
            LSLPeriodicDiscovery(managerId, entry.key, streams.length),
          );
        } catch (e) {
          _discoveryEventController.addEvent(
            LSLDiscoveryError(managerId, 'Periodic discovery error for ${entry.key}: $e'),
          );
        }
      }
    });
  }

  /// Check if a resolver exists
  bool hasResolver(String resolverId) {
    return _predicateResolvers.containsKey(resolverId) || 
           _activeResolvers.containsKey(resolverId);
  }

  /// List all active resolver IDs
  List<String> get resolverIds {
    return [
      ..._predicateResolvers.keys,
      ..._activeResolvers.keys,
    ];
  }
}

/// Exception for LSL discovery operations
class LSLDiscoveryException implements Exception {
  final String message;

  const LSLDiscoveryException(this.message);

  @override
  String toString() => 'LSLDiscoveryException: $message';
}

/// Events specific to LSL discovery operations
sealed class LSLDiscoveryEvent extends TimestampedEvent {
  final String managerId;

  const LSLDiscoveryEvent(this.managerId, DateTime timestamp)
    : super(eventId: 'lsl_discovery_event_$managerId', timestamp: timestamp);
}

class LSLDiscoveryManagerStarted extends LSLDiscoveryEvent {
  LSLDiscoveryManagerStarted(String managerId) : super(managerId, DateTime.now());
}

class LSLDiscoveryManagerStopped extends LSLDiscoveryEvent {
  LSLDiscoveryManagerStopped(String managerId) : super(managerId, DateTime.now());
}

class LSLNodesDiscovered extends LSLDiscoveryEvent {
  final String predicate;
  final int nodeCount;

  LSLNodesDiscovered(String managerId, this.predicate, this.nodeCount)
    : super(managerId, DateTime.now());
}

class LSLContinuousDiscoveryStarted extends LSLDiscoveryEvent {
  final String predicate;

  LSLContinuousDiscoveryStarted(String managerId, this.predicate)
    : super(managerId, DateTime.now());
}

class LSLContinuousDiscoveryStopped extends LSLDiscoveryEvent {
  final String resolverId;

  LSLContinuousDiscoveryStopped(String managerId, this.resolverId)
    : super(managerId, DateTime.now());
}

class LSLPeriodicDiscovery extends LSLDiscoveryEvent {
  final String resolverId;
  final int streamCount;

  LSLPeriodicDiscovery(String managerId, this.resolverId, this.streamCount)
    : super(managerId, DateTime.now());
}

class LSLResolverCreated extends LSLDiscoveryEvent {
  final String resolverId;
  final String predicate;

  LSLResolverCreated(String managerId, this.resolverId, this.predicate)
    : super(managerId, DateTime.now());
}

class LSLDiscoveryError extends LSLDiscoveryEvent {
  final String error;

  LSLDiscoveryError(String managerId, this.error)
    : super(managerId, DateTime.now());
}