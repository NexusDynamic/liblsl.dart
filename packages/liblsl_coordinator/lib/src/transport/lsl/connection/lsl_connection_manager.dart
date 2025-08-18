import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../management/resource_manager.dart';
import '../core/lsl_api_manager.dart';
import '../config/lsl_stream_config.dart';

/// Manages LSL inlet/outlet connections with metadata-based discovery
/// Handles the lifecycle of LSL connections properly to avoid resource leaks
class LSLConnectionManager implements ResourceManager {
  @override
  final String managerId;
  
  final Map<String, LSLOutlet> _outlets = {};
  final Map<String, LSLInlet> _inlets = {};
  final Map<String, LSLStreamResolverContinuous> _resolvers = {};
  final StreamController<LSLConnectionEvent> _eventController = 
      StreamController<LSLConnectionEvent>.broadcast();
  
  bool _isActive = false;
  late final ConfiguredLSL _lsl;
  
  LSLConnectionManager({required this.managerId}) {
    _lsl = LSLApiManager.lsl; // Will throw if not initialized
  }
  
  @override
  bool get isActive => _isActive;
  
  @override
  Stream<ResourceEvent> get events => _eventController.stream.cast<ResourceEvent>();
  
  /// Stream of LSL-specific connection events
  Stream<LSLConnectionEvent> get connectionEvents => _eventController.stream;
  
  @override
  Future<void> initialize() async {
    // Connection manager requires LSL to be already initialized
    if (!LSLApiManager.isInitialized) {
      throw LSLApiConfigurationException(
        'LSL API must be initialized before creating connection manager'
      );
    }
  }
  
  @override
  Future<void> start() async {
    _isActive = true;
    _eventController.add(LSLConnectionManagerStarted(managerId));
  }
  
  @override
  Future<void> stop() async {
    // Stop all resolvers
    for (final resolver in _resolvers.values) {
      try {
        resolver.destroy();
      } catch (e) {
        _eventController.add(LSLConnectionError(managerId, 'Error stopping resolver: $e'));
      }
    }
    
    _isActive = false;
    _eventController.add(LSLConnectionManagerStopped(managerId));
  }
  
  @override
  Future<void> dispose() async {
    await stop();
    
    // Dispose all outlets
    for (final entry in _outlets.entries) {
      try {
        await entry.value.destroy();
        _eventController.add(LSLOutletDestroyed(managerId, entry.key));
      } catch (e) {
        _eventController.add(LSLConnectionError(managerId, 'Error disposing outlet ${entry.key}: $e'));
      }
    }
    _outlets.clear();
    
    // Dispose all inlets
    for (final entry in _inlets.entries) {
      try {
        await entry.value.destroy();
        _eventController.add(LSLInletDestroyed(managerId, entry.key));
      } catch (e) {
        _eventController.add(LSLConnectionError(managerId, 'Error disposing inlet ${entry.key}: $e'));
      }
    }
    _inlets.clear();
    
    // Clear resolvers (should already be destroyed in stop())
    _resolvers.clear();
    
    await _eventController.close();
  }
  
  @override
  ResourceUsageStats getUsageStats() {
    final totalOutlets = _outlets.length;
    final totalInlets = _inlets.length;
    final totalResolvers = _resolvers.length;
    
    return ResourceUsageStats(
      totalResources: totalOutlets + totalInlets + totalResolvers,
      activeResources: totalOutlets + totalInlets + totalResolvers, // All are active when created
      idleResources: 0,
      erroredResources: 0, // TODO: Track errored connections
      lastUpdated: DateTime.now(),
      customMetrics: {
        'outlets': totalOutlets,
        'inlets': totalInlets,
        'resolvers': totalResolvers,
      },
    );
  }
  
  /// Create an LSL outlet for data streaming
  Future<LSLOutlet> createOutlet({
    required LSLStreamConfig config,
    String? outletId,
  }) async {
    final id = outletId ?? '${config.sourceId}_outlet';
    
    if (_outlets.containsKey(id)) {
      throw LSLConnectionException('Outlet with ID $id already exists');
    }
    
    try {
      final streamInfo = await config.toStreamInfo();
      final outlet = await _lsl.createOutlet(
        streamInfo: streamInfo,
        chunkSize: config.transportConfig.outletChunkSize,
        maxBuffer: config.transportConfig.maxOutletBuffer,
        useIsolates: config.pollingConfig.useIsolatedOutlets,
      );
      
      _outlets[id] = outlet;
      _eventController.add(LSLOutletCreated(managerId, id, config));
      
      return outlet;
    } catch (e) {
      _eventController.add(LSLConnectionError(managerId, 'Failed to create outlet $id: $e'));
      rethrow;
    }
  }
  
  /// Create an LSL inlet for data consumption with metadata-based discovery
  Future<LSLInlet> createInlet({
    required String streamName,
    Map<String, String>? metadataFilters,
    String? inletId,
    Duration? resolveTimeout,
    LSLTransportConfig? transportConfig,
  }) async {
    final id = inletId ?? '${streamName}_inlet';
    final timeout = resolveTimeout ?? const Duration(seconds: 5);
    final config = transportConfig ?? const LSLTransportConfig();
    
    if (_inlets.containsKey(id)) {
      throw LSLConnectionException('Inlet with ID $id already exists');
    }
    
    try {
      // Use metadata-based discovery with predicates
      final predicate = config.resolverConfig.dataPredicate(
        streamName, 
        metadataFilters: metadataFilters,
      );
      
      final streams = await _lsl.resolveStreamsByPredicate(
        predicate: predicate,
        waitTime: timeout.inMilliseconds / 1000.0,
        maxStreams: 1, // We want exactly one stream
      );
      
      if (streams.isEmpty) {
        throw LSLConnectionException(
          'No streams found matching predicate: $predicate'
        );
      }
      
      final streamInfo = streams.first;
      final inlet = await _lsl.createInlet(
        streamInfo: streamInfo,
        maxBuffer: config.maxInletBuffer,
        chunkSize: config.inletChunkSize,
        recover: config.enableRecovery,
        includeMetadata: true, // Always include metadata for our use case
        useIsolates: false, // Inlet-level isolation usually not needed
      );
      
      _inlets[id] = inlet;
      _eventController.add(LSLInletCreated(managerId, id, streamInfo));
      
      return inlet;
    } catch (e) {
      _eventController.add(LSLConnectionError(managerId, 'Failed to create inlet $id: $e'));
      rethrow;
    }
  }
  
  /// Create a continuous resolver for ongoing stream discovery
  LSLStreamResolverContinuous createContinuousResolver({
    String? predicate,
    String? resolverId,
    double forgetAfter = 5.0,
    int maxStreams = 50,
  }) {
    final id = resolverId ?? 'resolver_${DateTime.now().millisecondsSinceEpoch}';
    
    if (_resolvers.containsKey(id)) {
      throw LSLConnectionException('Resolver with ID $id already exists');
    }
    
    final resolver = _lsl.createContinuousStreamResolver(
      forgetAfter: forgetAfter,
      maxStreams: maxStreams,
    );
    
    _resolvers[id] = resolver;
    _eventController.add(LSLResolverCreated(managerId, id, predicate));
    
    return resolver;
  }
  
  /// Get an outlet by ID
  LSLOutlet? getOutlet(String outletId) => _outlets[outletId];
  
  /// Get an inlet by ID  
  LSLInlet? getInlet(String inletId) => _inlets[inletId];
  
  /// Get a resolver by ID
  LSLStreamResolverContinuous? getResolver(String resolverId) => _resolvers[resolverId];
  
  /// Destroy an outlet and remove from management
  Future<void> destroyOutlet(String outletId) async {
    final outlet = _outlets.remove(outletId);
    if (outlet != null) {
      try {
        await outlet.destroy();
        _eventController.add(LSLOutletDestroyed(managerId, outletId));
      } catch (e) {
        _eventController.add(LSLConnectionError(managerId, 'Error destroying outlet $outletId: $e'));
        rethrow;
      }
    }
  }
  
  /// Destroy an inlet and remove from management
  Future<void> destroyInlet(String inletId) async {
    final inlet = _inlets.remove(inletId);
    if (inlet != null) {
      try {
        await inlet.destroy();
        _eventController.add(LSLInletDestroyed(managerId, inletId));
      } catch (e) {
        _eventController.add(LSLConnectionError(managerId, 'Error destroying inlet $inletId: $e'));
        rethrow;
      }
    }
  }
  
  /// Destroy a resolver and remove from management
  void destroyResolver(String resolverId) {
    final resolver = _resolvers.remove(resolverId);
    if (resolver != null) {
      try {
        resolver.destroy();
        _eventController.add(LSLResolverDestroyed(managerId, resolverId));
      } catch (e) {
        _eventController.add(LSLConnectionError(managerId, 'Error destroying resolver $resolverId: $e'));
      }
    }
  }
  
  /// List all managed outlet IDs
  List<String> get outletIds => _outlets.keys.toList();
  
  /// List all managed inlet IDs
  List<String> get inletIds => _inlets.keys.toList();
  
  /// List all managed resolver IDs
  List<String> get resolverIds => _resolvers.keys.toList();
}

/// Exception for LSL connection operations
class LSLConnectionException implements Exception {
  final String message;
  
  const LSLConnectionException(this.message);
  
  @override
  String toString() => 'LSLConnectionException: $message';
}

/// Events specific to LSL connections
sealed class LSLConnectionEvent {
  final String resourceId;
  final DateTime timestamp;
  
  const LSLConnectionEvent(this.resourceId, this.timestamp);
}

class LSLConnectionManagerStarted extends LSLConnectionEvent {
  LSLConnectionManagerStarted(String managerId) : super(managerId, DateTime.now());
}

class LSLConnectionManagerStopped extends LSLConnectionEvent {
  LSLConnectionManagerStopped(String managerId) : super(managerId, DateTime.now());
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