import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../event.dart';
import '../../../management/resource_manager.dart';
import '../core/lsl_api_manager.dart';
import '../core/lsl_stream_manager.dart';
import '../config/lsl_stream_config.dart';
import '../../../utils/stream_controller_extensions.dart';

/// Manages LSL inlet/outlet connections with metadata-based discovery
/// This is a pure ResourceManager that manages LSLStreamManager instances
class LSLConnectionManager implements ResourceManager {
  @override
  final String managerId;
  
  final String nodeId;

  // Managed LSL stream managers
  final Map<String, LSLStreamManager> _streamManagers = {};
  final Set<String> _erroredResources = {};
  
  final StreamController<LSLConnectionEvent> _connectionEventController =
      StreamController<LSLConnectionEvent>.broadcast();

  bool _isActive = false;
  late final ConfiguredLSL _lsl;

  LSLConnectionManager({
    required this.managerId,
    required this.nodeId,
  }) {
    _lsl = LSLApiManager.lsl;
  }

  @override
  bool get isActive => _isActive;

  @override
  Stream<ResourceEvent> get events =>
      _connectionEventController.stream.cast<ResourceEvent>();

  /// Stream of LSL-specific connection events
  Stream<LSLConnectionEvent> get connectionEvents =>
      _connectionEventController.stream;

  @override
  Future<void> initialize() async {
    // Connection manager requires LSL to be already initialized
    if (!LSLApiManager.isInitialized) {
      throw LSLApiConfigurationException(
        'LSL API must be initialized before creating connection manager',
      );
    }
  }

  @override
  Future<void> start() async {
    _isActive = true;
    _connectionEventController.addEvent(LSLConnectionManagerStarted(managerId));
  }

  @override
  Future<void> stop() async {
    // Stop all managed stream managers
    final stopFutures = _streamManagers.values.map((manager) async {
      try {
        await manager.deactivate();
      } catch (e) {
        _connectionEventController.addEvent(
          LSLConnectionError(managerId, 'Error stopping manager ${manager.resourceId}: $e'),
        );
      }
    });
    await Future.wait(stopFutures);
    
    _isActive = false;
    _connectionEventController.addEvent(LSLConnectionManagerStopped(managerId));
  }

  @override
  Future<void> dispose() async {
    await stop();

    // Dispose all managed stream managers
    final disposeFutures = _streamManagers.values.map((manager) async {
      try {
        await manager.dispose();
      } catch (e) {
        logger.warning('Error disposing stream manager ${manager.resourceId}: $e');
      }
    });
    await Future.wait(disposeFutures);
    _streamManagers.clear();
    
    // Clear error tracking
    _erroredResources.clear();

    try {
      await _connectionEventController.close();
    } catch (e) {
      // Ignore errors during disposal
    }
  }

  @override
  ResourceUsageStats getUsageStats() {
    final totalManagers = _streamManagers.length;
    
    // Aggregate stats from all managed stream managers
    int totalOutlets = 0;
    int totalInlets = 0;
    int totalResolvers = 0;
    
    for (final manager in _streamManagers.values) {
      final metadata = manager.metadata;
      totalOutlets += metadata['outlets'] as int? ?? 0;
      totalInlets += metadata['inlets'] as int? ?? 0;
      totalResolvers += metadata['resolvers'] as int? ?? 0;
    }

    return ResourceUsageStats(
      totalResources: totalManagers,
      activeResources: totalManagers,
      idleResources: 0,
      erroredResources: _erroredResources.length,
      lastUpdated: DateTime.now(),
      customMetrics: {
        'streamManagers': totalManagers,
        'totalOutlets': totalOutlets,
        'totalInlets': totalInlets,
        'totalResolvers': totalResolvers,
      },
    );
  }

  /// Create a stream manager and outlet for the given config
  Future<LSLOutlet> createOutletForConfig({
    required LSLStreamConfig config,
    String? outletId,
  }) async {
    final id = outletId ?? '${config.sourceId}_outlet';
    final managerId = '${this.managerId}_manager_$id';
    
    try {
      // Create a dedicated stream manager for this outlet
      final streamManager = _createStreamManager(managerId, config);
      await streamManager.initialize();
      await streamManager.activate();
      
      _streamManagers[managerId] = streamManager;
      
      // Create the outlet through the stream manager
      final streamInfo = await config.toStreamInfo();
      final outlet = await streamManager.createOutlet(
        outletId: id,
        streamInfo: streamInfo,
        pollingConfig: config.pollingConfig,
      );

      _connectionEventController.addEvent(
        LSLOutletCreated(this.managerId, id, config),
      );
      return outlet;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(this.managerId, 'Failed to create outlet $id: $e'),
      );
      rethrow;
    }
  }

  /// Create an LSL inlet for data consumption with metadata-based discovery
  Future<LSLInlet> createInletByDiscovery({
    required String streamName,
    Map<String, String>? metadataFilters,
    String? inletId,
    LSLTransportConfig? transportConfig,
  }) async {
    final id = inletId ?? '${streamName}_inlet';
    final managerId = '${this.managerId}_manager_$id';
    final transportConf = transportConfig ?? const LSLTransportConfig();

    try {
      // Create a temporary stream manager for discovery
      final tempConfig = LSLStreamConfig(
        id: streamName,
        pollingConfig: const LSLPollingConfig(),
        transportConfig: transportConf,
      );
      final streamManager = _createStreamManager('${managerId}_discovery', tempConfig);
      await streamManager.initialize();
      
      // Use metadata-based discovery with predicates
      final predicate = transportConf.resolverConfig.dataPredicate(
        streamName,
        metadataFilters: metadataFilters,
      );

      // Use stream manager resolver to find streams
      final resolver = streamManager.createResolverByPredicate(
        resolverId: '${id}_discovery',
        predicate: predicate,
        forgetAfter: transportConf.resolverConfig.forgetAfter,
        maxStreams: 1,
      );

      // Resolve streams
      final streams = await resolver.resolve();
      if (streams.isEmpty) {
        await streamManager.dispose(); // Clean up temp manager
        throw LSLConnectionException(
          'No streams found matching predicate: $predicate',
        );
      }

      final streamInfo = streams.first;
      
      // Create permanent stream manager for the inlet
      final permanentManager = _createStreamManager(managerId, tempConfig);
      await permanentManager.initialize();
      await permanentManager.activate();
      _streamManagers[managerId] = permanentManager;
      
      final inlet = await permanentManager.createInlet(
        inletId: id,
        streamInfo: streamInfo,
      );

      // Clean up temporary manager and unused streams
      await streamManager.dispose();
      streams.skip(1).toList().destroy(); // Destroy unused streams

      _connectionEventController.addEvent(
        LSLInletCreated(this.managerId, id, streamInfo),
      );
      return inlet;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(this.managerId, 'Failed to create inlet $id: $e'),
      );
      rethrow;
    }
  }

  /// Create a continuous resolver for ongoing stream discovery
  LSLStreamResolverContinuous createContinuousResolver({
    String? predicate,
    String? resolverId,
    double? forgetAfter,
    int? maxStreams,
  }) {
    final id = resolverId ?? 'resolver_${DateTime.now().millisecondsSinceEpoch}';
    final managerId = '${this.managerId}_resolver_manager_$id';

    try {
      // Create a dedicated stream manager for this resolver
      final tempConfig = LSLStreamConfig(
        id: 'resolver_$id',
        pollingConfig: const LSLPollingConfig(),
        transportConfig: const LSLTransportConfig(),
      );
      final streamManager = _createStreamManager(managerId, tempConfig);
      streamManager.initialize();
      _streamManagers[managerId] = streamManager;
      
      final resolver = streamManager.createResolverByPredicate(
        resolverId: id,
        predicate: predicate ?? '',
        forgetAfter: forgetAfter,
        maxStreams: maxStreams,
      );

      _connectionEventController.addEvent(
        LSLResolverCreated(this.managerId, id, predicate),
      );
      return resolver;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(this.managerId, 'Failed to create resolver $id: $e'),
      );
      rethrow;
    }
  }

  /// Get an outlet by ID (searches all managed stream managers)
  LSLOutlet? getOutlet(String outletId) {
    for (final manager in _streamManagers.values) {
      final outlet = manager.getOutlet(outletId);
      if (outlet != null) return outlet;
    }
    return null;
  }

  /// Get an inlet by ID (searches all managed stream managers)
  LSLInlet? getInlet(String inletId) {
    for (final manager in _streamManagers.values) {
      final inlet = manager.getInlet(inletId);
      if (inlet != null) return inlet;
    }
    return null;
  }

  /// Get a resolver by ID (searches all managed stream managers)
  LSLStreamResolverContinuous? getResolver(String resolverId) {
    for (final manager in _streamManagers.values) {
      final resolver = manager.getResolver(resolverId);
      if (resolver != null) return resolver;
    }
    return null;
  }

  /// Destroy an outlet and remove from management
  Future<void> destroyOutlet(String outletId) async {
    try {
      // Find and remove outlet from appropriate stream manager
      for (final manager in _streamManagers.values) {
        if (manager.hasOutlet(outletId)) {
          await manager.removeOutlet(outletId);
          _connectionEventController.addEvent(
            LSLOutletDestroyed(managerId, outletId),
          );
          return;
        }
      }
      throw LSLConnectionException('Outlet $outletId not found');
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Error destroying outlet $outletId: $e'),
      );
      rethrow;
    }
  }

  /// Destroy an inlet and remove from management
  Future<void> destroyInlet(String inletId) async {
    try {
      // Find and remove inlet from appropriate stream manager
      for (final manager in _streamManagers.values) {
        if (manager.hasInlet(inletId)) {
          await manager.removeInlet(inletId);
          _connectionEventController.addEvent(
            LSLInletDestroyed(managerId, inletId),
          );
          return;
        }
      }
      throw LSLConnectionException('Inlet $inletId not found');
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Error destroying inlet $inletId: $e'),
      );
      rethrow;
    }
  }

  /// Destroy a resolver and remove from management
  void destroyResolver(String resolverId) {
    try {
      // Find and remove resolver from appropriate stream manager
      for (final manager in _streamManagers.values) {
        if (manager.hasResolver(resolverId)) {
          manager.removeResolver(resolverId);
          _connectionEventController.addEvent(
            LSLResolverDestroyed(managerId, resolverId),
          );
          return;
        }
      }
      throw LSLConnectionException('Resolver $resolverId not found');
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(
          managerId,
          'Error destroying resolver $resolverId: $e',
        ),
      );
    }
  }

  /// List all managed outlet IDs
  List<String> get outletIds {
    // Extract from metadata or iterate through base class resources
    final outlets = <String>[];
    // Base class doesn't expose internal maps, so we rely on metadata
    return outlets;
  }

  /// List all managed inlet IDs
  List<String> get inletIds {
    final inlets = <String>[];
    return inlets;
  }

  /// List all managed resolver IDs
  List<String> get resolverIds {
    final resolvers = <String>[];
    return resolvers;
  }

  /// List all errored resource IDs
  List<String> get erroredResourceIds {
    // Extract from base class metadata
    return [];
  }

  /// Mark a resource as errored
  void markResourceErrored(String resourceId, String error) {
    if (!_connectionEventController.isClosed) {
      _connectionEventController.add(
        LSLConnectionError(managerId, 'Resource $resourceId errored: $error'),
      );
    }
  }

  /// Clear error state for a resource (when it recovers)
  void clearResourceError(String resourceId) {
    if (!_connectionEventController.isClosed) {
      _connectionEventController.add(
        LSLConnectionRecovered(managerId, resourceId),
      );
    }
  }

  /// Check if a resource is in error state
  bool isResourceErrored(String resourceId) {
    // This would need to check base class error tracking
    return false;
  }
}

/// Exception for LSL connection operations
class LSLConnectionException implements Exception {
  final String message;

  const LSLConnectionException(this.message);

  @override
  String toString() => 'LSLConnectionException: $message';
}

/// Events specific to LSL connections
sealed class LSLConnectionEvent extends TimestampedEvent {
  final String resourceId;

  const LSLConnectionEvent(this.resourceId, DateTime timestamp)
    : super(eventId: 'lsl_connection_event_$resourceId', timestamp: timestamp);
}

class LSLConnectionManagerStarted extends LSLConnectionEvent {
  LSLConnectionManagerStarted(String managerId)
    : super(managerId, DateTime.now());
}

class LSLConnectionManagerStopped extends LSLConnectionEvent {
  LSLConnectionManagerStopped(String managerId)
    : super(managerId, DateTime.now());
}

class LSLOutletCreated extends LSLConnectionEvent {
  final LSLStreamConfig config;

  LSLOutletCreated(String managerId, String outletId, this.config)
    : super('${managerId}_outlet_$outletId', DateTime.now());
}

class LSLOutletDestroyed extends LSLConnectionEvent {
  LSLOutletDestroyed(String managerId, String outletId)
    : super('${managerId}_outlet_$outletId', DateTime.now());
}

class LSLInletCreated extends LSLConnectionEvent {
  final LSLStreamInfo streamInfo;

  LSLInletCreated(String managerId, String inletId, this.streamInfo)
    : super('${managerId}_inlet_$inletId', DateTime.now());
}

class LSLInletDestroyed extends LSLConnectionEvent {
  LSLInletDestroyed(String managerId, String inletId)
    : super('${managerId}_inlet_$inletId', DateTime.now());
}

class LSLResolverCreated extends LSLConnectionEvent {
  final String? predicate;

  LSLResolverCreated(String managerId, String resolverId, this.predicate)
    : super('${managerId}_resolver_$resolverId', DateTime.now());
}

class LSLResolverDestroyed extends LSLConnectionEvent {
  LSLResolverDestroyed(String managerId, String resolverId)
    : super('${managerId}_resolver_$resolverId', DateTime.now());
}

class LSLConnectionError extends LSLConnectionEvent {
  final String error;

  LSLConnectionError(String managerId, this.error)
    : super('${managerId}_error', DateTime.now());
}

class LSLConnectionRecovered extends LSLConnectionEvent {
  LSLConnectionRecovered(String managerId, String resourceId)
    : super('${managerId}_recovered_$resourceId', DateTime.now());
}
