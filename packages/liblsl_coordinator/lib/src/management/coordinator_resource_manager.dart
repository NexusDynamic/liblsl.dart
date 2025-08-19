import 'dart:async';
import '../transport/lsl/connection/lsl_connection_manager.dart';
import '../transport/lsl/core/lsl_coordination_session.dart';
import '../transport/lsl/core/lsl_data_stream.dart';
import '../utils/logging.dart';
import 'resource_manager.dart';

/// Central resource manager for coordination resources
/// 
/// Manages the lifecycle of all coordination-related resources including:
/// - Coordination sessions
/// - Data streams
/// - LSL connections (outlets/inlets/resolvers)
/// - Isolate controllers
class CoordinatorResourceManager implements ResourceManager {
  @override
  final String managerId;
  
  final Map<String, ManagedResource> _resources = {};
  final Map<String, LSLConnectionManager> _connectionManagers = {};
  final StreamController<ResourceEvent> _eventController = 
      StreamController<ResourceEvent>.broadcast();
  
  bool _isActive = false;
  DateTime _lastHealthCheck = DateTime.now();
  Timer? _healthCheckTimer;
  
  CoordinatorResourceManager({required this.managerId});
  
  @override
  bool get isActive => _isActive;
  
  @override
  Stream<ResourceEvent> get events => _eventController.stream;
  
  @override
  Future<void> initialize() async {
    if (_isActive) {
      logger.warning('CoordinatorResourceManager $managerId already initialized');
      return;
    }
    
    logger.info('Initializing CoordinatorResourceManager: $managerId');
    _lastHealthCheck = DateTime.now();
  }
  
  @override
  Future<void> start() async {
    if (_isActive) {
      logger.warning('CoordinatorResourceManager $managerId already active');
      return;
    }
    
    logger.info('Starting CoordinatorResourceManager: $managerId');
    _isActive = true;
    
    // Start health check timer (every 30 seconds)
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 30), 
      (_) => _performHealthCheck(),
    );
  }
  
  @override
  Future<void> stop() async {
    if (!_isActive) {
      logger.warning('CoordinatorResourceManager $managerId already stopped');
      return;
    }
    
    logger.info('Stopping CoordinatorResourceManager: $managerId');
    
    // Stop health check timer
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    
    _isActive = false;
  }
  
  @override
  Future<void> dispose() async {
    logger.info('Disposing CoordinatorResourceManager: $managerId');
    
    await stop();
    
    // Dispose all managed resources in reverse order of creation
    final resourceIds = _resources.keys.toList().reversed;
    final disposeFutures = <Future<void>>[];
    
    for (final resourceId in resourceIds) {
      final resource = _resources[resourceId];
      if (resource != null) {
        disposeFutures.add(_disposeResource(resourceId, resource));
      }
    }
    
    // Wait for all resources to dispose
    await Future.wait(disposeFutures);
    
    // Dispose connection managers
    for (final entry in _connectionManagers.entries) {
      try {
        logger.info('Disposing connection manager: ${entry.key}');
        await entry.value.dispose();
      } catch (e) {
        logger.warning('Error disposing connection manager ${entry.key}: $e');
        _eventController.add(ResourceError(entry.key, 'Disposal error: $e', e));
      }
    }
    _connectionManagers.clear();
    
    _resources.clear();
    await _eventController.close();
    
    logger.info('CoordinatorResourceManager $managerId disposed');
  }
  
  @override
  ResourceUsageStats getUsageStats() {
    final now = DateTime.now();
    int activeResources = 0;
    int erroredResources = 0;
    int idleResources = 0;
    
    // Count resource states
    for (final resource in _resources.values) {
      switch (resource.resourceState) {
        case ResourceState.active:
          activeResources++;
          break;
        case ResourceState.error:
          erroredResources++;
          break;
        case ResourceState.idle:
          idleResources++;
          break;
        default:
          // Other states don't count as active/idle/errored
          break;
      }
    }
    
    // Add connection manager stats
    final connectionStats = <String, dynamic>{};
    int totalConnections = 0;
    for (final entry in _connectionManagers.entries) {
      final stats = entry.value.getUsageStats();
      connectionStats[entry.key] = {
        'outlets': stats.customMetrics['outlets'] ?? 0,
        'inlets': stats.customMetrics['inlets'] ?? 0,
        'resolvers': stats.customMetrics['resolvers'] ?? 0,
      };
      totalConnections += stats.totalResources;
    }
    
    return ResourceUsageStats(
      totalResources: _resources.length + totalConnections,
      activeResources: activeResources,
      idleResources: idleResources,
      erroredResources: erroredResources,
      lastUpdated: now,
      customMetrics: {
        'sessions': _resources.values.whereType<LSLCoordinationSession>().length,
        'dataStreams': _resources.values.whereType<LSLDataStream>().length,
        'connectionManagers': _connectionManagers.length,
        'connections': connectionStats,
        'lastHealthCheck': _lastHealthCheck.toIso8601String(),
      },
    );
  }
  
  /// Add a resource to management
  Future<void> addResource(ManagedResource resource) async {
    if (_resources.containsKey(resource.resourceId)) {
      throw ResourceManagerException(
        'Resource ${resource.resourceId} already exists'
      );
    }
    
    logger.info('Adding resource to management: ${resource.resourceId}');
    
    try {
      _resources[resource.resourceId] = resource;
      
      // Subscribe to resource state changes
      resource.stateChanges.listen((stateEvent) {
        _eventController.add(ResourceStateChanged(
          stateEvent.resourceId,
          stateEvent.oldState,
          stateEvent.newState,
          stateEvent.reason,
        ));
      });
      
      _eventController.add(ResourceCreated(
        resource.resourceId,
        resource.runtimeType.toString(),
        resource.metadata,
      ));
      
      logger.info('Resource added to management: ${resource.resourceId}');
    } catch (e) {
      logger.severe('Failed to add resource ${resource.resourceId}: $e');
      _eventController.add(ResourceError(
        resource.resourceId, 
        'Failed to add resource: $e', 
        e,
      ));
      rethrow;
    }
  }
  
  /// Remove a resource from management
  Future<void> removeResource(String resourceId) async {
    final resource = _resources.remove(resourceId);
    if (resource == null) {
      logger.warning('Attempted to remove non-existent resource: $resourceId');
      return;
    }
    
    logger.info('Removing resource from management: $resourceId');
    await _disposeResource(resourceId, resource);
  }
  
  /// Add a connection manager to management
  void addConnectionManager(LSLConnectionManager connectionManager) {
    if (_connectionManagers.containsKey(connectionManager.managerId)) {
      throw ResourceManagerException(
        'Connection manager ${connectionManager.managerId} already exists'
      );
    }
    
    logger.info('Adding connection manager: ${connectionManager.managerId}');
    _connectionManagers[connectionManager.managerId] = connectionManager;
    
    // Forward connection events as resource events
    connectionManager.connectionEvents.listen((event) {
      _eventController.add(ResourceStateChanged(
        event.resourceId,
        ResourceState.active, // Connection events don't have old state
        ResourceState.active,
        event.runtimeType.toString(),
      ));
    });
  }
  
  /// Remove a connection manager from management
  Future<void> removeConnectionManager(String managerId) async {
    final manager = _connectionManagers.remove(managerId);
    if (manager != null) {
      logger.info('Removing connection manager: $managerId');
      try {
        await manager.dispose();
      } catch (e) {
        logger.warning('Error disposing connection manager $managerId: $e');
        _eventController.add(ResourceError(managerId, 'Disposal error: $e', e));
      }
    }
  }
  
  /// Get a managed resource by ID
  ManagedResource? getResource(String resourceId) => _resources[resourceId];
  
  /// Get a connection manager by ID
  LSLConnectionManager? getConnectionManager(String managerId) =>
      _connectionManagers[managerId];
  
  /// List all managed resource IDs
  List<String> get resourceIds => _resources.keys.toList();
  
  /// List all connection manager IDs
  List<String> get connectionManagerIds => _connectionManagers.keys.toList();
  
  /// Perform health check on all managed resources
  Future<void> _performHealthCheck() async {
    logger.fine('Performing health check on ${_resources.length} resources');
    _lastHealthCheck = DateTime.now();
    
    final healthCheckFutures = <Future<void>>[];
    
    for (final entry in _resources.entries) {
      healthCheckFutures.add(_checkResourceHealth(entry.key, entry.value));
    }
    
    for (final entry in _connectionManagers.entries) {
      healthCheckFutures.add(_checkConnectionManagerHealth(entry.key, entry.value));
    }
    
    try {
      await Future.wait(healthCheckFutures);
      logger.fine('Health check completed');
    } catch (e) {
      logger.warning('Health check encountered errors: $e');
    }
  }
  
  Future<void> _checkResourceHealth(String resourceId, ManagedResource resource) async {
    try {
      final isHealthy = await resource.healthCheck();
      if (!isHealthy) {
        logger.warning('Resource $resourceId failed health check');
        _eventController.add(ResourceError(
          resourceId, 
          'Health check failed',
        ));
      }
    } catch (e) {
      logger.warning('Error checking health of resource $resourceId: $e');
      _eventController.add(ResourceError(
        resourceId, 
        'Health check error: $e', 
        e,
      ));
    }
  }
  
  Future<void> _checkConnectionManagerHealth(String managerId, LSLConnectionManager manager) async {
    try {
      // Connection managers don't have explicit health checks yet,
      // but we can check if they're responsive
      final stats = manager.getUsageStats();
      logger.fine('Connection manager $managerId: ${stats.totalResources} resources');
    } catch (e) {
      logger.warning('Error checking health of connection manager $managerId: $e');
      _eventController.add(ResourceError(
        managerId, 
        'Connection manager health check error: $e', 
        e,
      ));
    }
  }
  
  Future<void> _disposeResource(String resourceId, ManagedResource resource) async {
    try {
      logger.info('Disposing resource: $resourceId');
      await resource.dispose();
      _eventController.add(ResourceDisposed(resourceId));
      logger.info('Resource disposed: $resourceId');
    } catch (e) {
      logger.severe('Error disposing resource $resourceId: $e');
      _eventController.add(ResourceError(
        resourceId, 
        'Disposal error: $e', 
        e,
      ));
    }
  }
}

/// Exception for resource manager operations
class ResourceManagerException implements Exception {
  final String message;
  
  const ResourceManagerException(this.message);
  
  @override
  String toString() => 'ResourceManagerException: $message';
}