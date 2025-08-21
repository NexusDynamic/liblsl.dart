import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../network/connection_manager.dart';
import '../../../utils/logging.dart';
import '../config/lsl_stream_config.dart';
import 'lsl_api_manager.dart';
import 'lsl_stream_manager.dart';

/// Base coordinator for managing LSL-based coordination sessions
///
/// This is a ResourceManager that manages multiple LSLStreamManager instances
/// and coordination sessions. It does not inherit from LSLStreamManager because
/// it manages them rather than being one.
abstract class LSLStreamCoordinator implements ConnectionManager {
  @override
  final String managerId;

  final String nodeId;

  // Managed resources
  final Map<String, LSLStreamManager> _streamManagers = {};
  final Map<String, CoordinationSessionManager> _coordinationSessions = {};
  final Set<String> _erroredResources = {};

  // Event handling
  final StreamController<ResourceEvent> _eventController =
      StreamController<ResourceEvent>.broadcast();

  bool _isActive = false;
  late final ConfiguredLSL _lsl;

  LSLStreamCoordinator({required this.managerId, required this.nodeId}) {
    _lsl = LSLApiManager.lsl;
  }

  @override
  bool get isActive => _isActive;

  @override
  Stream<ResourceEvent> get events => _eventController.stream;

  @override
  Future<void> initialize() async {
    if (!LSLApiManager.isInitialized) {
      throw LSLApiConfigurationException(
        'LSL API must be initialized before creating stream coordinator',
      );
    }

    await onInitialize();
    logger.info('LSL stream coordinator $managerId initialized');
  }

  @override
  Future<void> start() async {
    _isActive = true;
    await onStart();
    _eventController.add(ResourceStarted(managerId, null));
    logger.info('LSL stream coordinator $managerId started');
  }

  @override
  Future<void> stop() async {
    await onStop();
    _isActive = false;
    _eventController.add(ResourceStopped(managerId, null));
    logger.info('LSL stream coordinator $managerId stopped');
  }

  @override
  Future<void> dispose() async {
    await stop();

    // Dispose all coordination sessions
    final sessionDisposeFutures = _coordinationSessions.values.map((
      session,
    ) async {
      try {
        await session.dispose();
      } catch (e) {
        logger.warning(
          'Error disposing coordination session ${session.managerId}: $e',
        );
      }
    });
    await Future.wait(sessionDisposeFutures);
    _coordinationSessions.clear();

    // Dispose all stream managers
    final managerDisposeFutures = _streamManagers.values.map((manager) async {
      try {
        await manager.dispose();
      } catch (e) {
        logger.warning(
          'Error disposing stream manager ${manager.resourceId}: $e',
        );
      }
    });
    await Future.wait(managerDisposeFutures);
    _streamManagers.clear();

    await onDispose();
    await _eventController.close();
    logger.info('LSL stream coordinator $managerId disposed');
  }

  @override
  NetworkStats getUsageStats() {
    final totalSessions = _coordinationSessions.length;
    final totalManagers = _streamManagers.length;

    return NetworkStats(
      totalResources: totalSessions + totalManagers,
      activeResources: totalSessions + totalManagers,
      idleResources: 0,
      erroredResources: _erroredResources.length,
      lastUpdated: DateTime.now(),
      customMetrics: {
        'coordinationSessions': totalSessions,
        'streamManagers': totalManagers,
      },
    );
  }

  // === PROTECTED METHODS FOR SUBCLASSES ===

  /// Override to perform coordinator-specific initialization
  Future<void> onInitialize() async {}

  /// Override to perform coordinator-specific startup
  Future<void> onStart() async {}

  /// Override to perform coordinator-specific shutdown
  Future<void> onStop() async {}

  /// Override to perform coordinator-specific disposal
  Future<void> onDispose() async {}

  // === RESOURCE MANAGEMENT ===

  /// Add a coordination session to management
  void addCoordinationSession(CoordinationSessionManager session) {
    _coordinationSessions[session.managerId] = session;
    _eventController.add(
      ResourceAdded(session.managerId, null, managerId: managerId),
    );
  }

  /// Remove a coordination session from management
  Future<void> removeCoordinationSession(String sessionId) async {
    final session = _coordinationSessions.remove(sessionId);
    if (session != null) {
      try {
        await session.dispose();
        _eventController.add(
          ResourceRemoved(sessionId, null, managerId: managerId),
        );
      } catch (e) {
        _markResourceErrored(sessionId, 'Failed to dispose session: $e');
        rethrow;
      }
    }
    _erroredResources.remove(sessionId);
  }

  /// Add a stream manager to management
  void addStreamManager(LSLStreamManager manager) {
    _streamManagers[manager.resourceId] = manager;
    _eventController.add(
      ResourceAdded(manager.resourceId, null, managerId: managerId),
    );
  }

  /// Remove a stream manager from management
  Future<void> removeStreamManager(String managerId) async {
    final manager = _streamManagers.remove(managerId);
    if (manager != null) {
      try {
        await manager.dispose();
        _eventController.add(
          ResourceRemoved(managerId, null, managerId: this.managerId),
        );
      } catch (e) {
        _markResourceErrored(managerId, 'Failed to dispose manager: $e');
        rethrow;
      }
    }
    _erroredResources.remove(managerId);
  }

  /// Get a coordination session by ID
  CoordinationSessionManager? getCoordinationSession(String sessionId) {
    return _coordinationSessions[sessionId];
  }

  /// Get a stream manager by ID
  LSLStreamManager? getStreamManager(String managerId) {
    return _streamManagers[managerId];
  }

  /// List all coordination session IDs
  List<String> get coordinationSessionIds =>
      _coordinationSessions.keys.toList();

  /// List all stream manager IDs
  List<String> get streamManagerIds => _streamManagers.keys.toList();

  /// Mark a resource as errored
  void _markResourceErrored(String resourceId, String error) {
    _erroredResources.add(resourceId);
    _eventController.add(
      ResourceError(resourceId, error, managerId: managerId),
    );
    logger.warning('Resource $resourceId marked as errored: $error');
  }
}

/// Interface for coordination session management
abstract class CoordinationSessionManager implements ConnectionManager {
  // This will be implemented by LSLCoordinationSession
}
