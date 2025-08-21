import 'dart:async';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/src/event.dart';
import 'package:meta/meta.dart';
import '../../../network/connection_manager.dart';
import '../../../utils/logging.dart';
// import '../../../utils/stream_controller_extensions.dart';
import '../config/lsl_stream_config.dart';
import '../events/lsl_stream_events.dart';
import '../isolate/lsl_isolate_controller.dart';
import '../isolate/lsl_polling_isolates.dart';
import 'lsl_api_manager.dart';

/// Base class for managing LSL streams (inlets, outlets, resolvers)
///
/// Provides common functionality for:
/// - Stream discovery and resolution
/// - Inlet/outlet creation and management
/// - Isolate-based polling configuration (respects both levels)
/// - Resource lifecycle management
/// - Error handling and cleanup
abstract class LSLStreamManager implements ManagedResource {
  @override
  final String resourceId;

  final String nodeId;
  final LSLStreamConfig config;

  // Core LSL API
  late final ConfiguredLSL _lsl;

  // Resource tracking
  final Map<String, LSLOutlet> _outlets = {};
  final Map<String, LSLInlet> _inlets = {};
  final Map<String, LSLStreamResolverContinuous> _resolvers = {};
  final Map<String, LSLIsolateController> _isolateControllers = {};
  final Set<String> _erroredResources = {};

  // State management
  ResourceState _resourceState = ResourceState.created;
  final StreamController<ResourceStateEvent> _resourceStateController =
      StreamController<ResourceStateEvent>.broadcast();

  // Event tracking for subclasses - using base StreamEvent
  final StreamController<StreamEvent> _eventController =
      StreamController<StreamEvent>.broadcast();

  LSLStreamManager({
    required this.resourceId,
    required this.nodeId,
    required this.config,
  }) {
    _lsl = LSLApiManager.lsl;
  }

  // === RESOURCE MANAGER IMPLEMENTATION ===

  @override
  ResourceState get resourceState => _resourceState;

  @override
  Map<String, dynamic> get metadata => {
    'resourceId': resourceId,
    'nodeId': nodeId,
    'streamId': config.id,
    'outlets': _outlets.length,
    'inlets': _inlets.length,
    'resolvers': _resolvers.length,
    'isolateControllers': _isolateControllers.length,
    'erroredResources': _erroredResources.length,
    'pollingConfig': {
      'usePollingIsolate': config.pollingConfig.usePollingIsolate,
      'useIsolatedInlets': config.pollingConfig.useIsolatedInlets,
      'useIsolatedOutlets': config.pollingConfig.useIsolatedOutlets,
      'useBusyWait': config.pollingConfig.useBusyWait,
      'targetIntervalMicroseconds':
          config.pollingConfig.targetIntervalMicroseconds,
    },
  };

  @override
  Stream<ResourceStateEvent> get stateChanges =>
      _resourceStateController.stream;

  @override
  Future<void> initialize() async {
    if (_resourceState != ResourceState.created) {
      throw LSLStreamManagerException('Stream manager already initialized');
    }

    _updateResourceState(ResourceState.initializing);

    try {
      await onInitialize();
      _updateResourceState(ResourceState.idle);
      logger.info('LSL stream manager initialized: $resourceId');
    } catch (e) {
      _updateResourceState(ResourceState.error, 'Initialization failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> activate() async {
    if (_resourceState != ResourceState.idle) {
      logger.warning(
        'Stream manager $resourceId not in idle state, cannot activate',
      );
      return;
    }

    _updateResourceState(ResourceState.active);

    try {
      await onActivate();
      logger.info('LSL stream manager activated: $resourceId');
    } catch (e) {
      _updateResourceState(ResourceState.error, 'Activation failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> deactivate() async {
    if (_resourceState != ResourceState.active) {
      logger.warning(
        'Stream manager $resourceId not in active state, cannot deactivate',
      );
      return;
    }

    _updateResourceState(ResourceState.idle);

    try {
      await onDeactivate();
      logger.info('LSL stream manager deactivated: $resourceId');
    } catch (e) {
      _updateResourceState(ResourceState.error, 'Deactivation failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_resourceState == ResourceState.disposed) {
      logger.warning('Stream manager $resourceId already disposed');
      return;
    }

    _updateResourceState(ResourceState.stopping);

    try {
      // Call subclass cleanup first
      await onDispose();

      // Dispose all isolate controllers (these handle polling isolates)
      final isolateDisposeFutures = _isolateControllers.values.map((
        controller,
      ) async {
        try {
          await controller.stop();
        } catch (e) {
          logger.warning(
            'Error stopping isolate controller ${controller.controllerId}: $e',
          );
        }
      });
      await Future.wait(isolateDisposeFutures);
      _isolateControllers.clear();

      // Dispose all outlets (direct LSL objects)
      final outletDisposeFutures = _outlets.entries.map((entry) async {
        try {
          await entry.value.destroy();
          emitEvent(LSLOutletDestroyed(resourceId, entry.key));
        } catch (e) {
          logger.warning('Error disposing outlet ${entry.key}: $e');
        }
      });
      await Future.wait(outletDisposeFutures);
      _outlets.clear();

      // Dispose all inlets (direct LSL objects)
      final inletDisposeFutures = _inlets.entries.map((entry) async {
        try {
          await entry.value.destroy();
          emitEvent(LSLInletDestroyed(resourceId, entry.key));
        } catch (e) {
          logger.warning('Error disposing inlet ${entry.key}: $e');
        }
      });
      await Future.wait(inletDisposeFutures);
      _inlets.clear();

      // Dispose all resolvers
      for (final entry in _resolvers.entries) {
        try {
          entry.value.destroy();
          emitEvent(LSLResolverDestroyed(resourceId, entry.key));
        } catch (e) {
          logger.warning('Error disposing resolver ${entry.key}: $e');
        }
      }
      _resolvers.clear();

      // Close event controllers
      await _eventController.close();
      await _resourceStateController.close();

      _updateResourceState(ResourceState.disposed);
      logger.info('LSL stream manager disposed: $resourceId');
    } catch (e) {
      _updateResourceState(ResourceState.error, 'Disposal failed: $e');
      logger.severe('Error disposing stream manager $resourceId: $e');
      rethrow;
    }
  }

  @override
  Future<bool> healthCheck() async {
    try {
      // Check if all isolate controllers are healthy
      for (final controller in _isolateControllers.values) {
        if (!controller.isActive) {
          logger.warning(
            'Isolate controller ${controller.controllerId} is not active',
          );
          return false;
        }
        if (controller.hasErrors) {
          logger.warning(
            'Isolate controller ${controller.controllerId} has errors',
          );
          return false;
        }
      }

      // Check for errored resources
      if (_erroredResources.isNotEmpty) {
        logger.warning(
          'Stream manager $resourceId has errored resources: $_erroredResources',
        );
        return false;
      }

      return true;
    } catch (e) {
      logger.warning('Health check failed for stream manager $resourceId: $e');
      return false;
    }
  }

  // === PROTECTED METHODS FOR SUBCLASSES ===

  /// Override to perform subclass-specific initialization
  @protected
  Future<void> onInitialize() async {}

  /// Override to perform subclass-specific activation
  @protected
  Future<void> onActivate() async {}

  /// Override to perform subclass-specific deactivation
  @protected
  Future<void> onDeactivate() async {}

  /// Override to perform subclass-specific disposal
  @protected
  Future<void> onDispose() async {}

  /// Stream of stream events (accessible to subclasses)
  @protected
  Stream<Event> get events => _eventController.stream;

  /// Emit an event to listeners (protected for subclasses)
  @protected
  void emitEvent(StreamEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  /// Update resource state (protected for subclasses)
  @protected
  void updateResourceState(ResourceState newState, [String? reason]) {
    _updateResourceState(newState, reason);
  }

  // === LSL STREAM OPERATIONS ===

  /// Create an LSL outlet (direct or via polling isolate)
  ///
  /// If usePollingIsolate is true, this will be managed by an isolate controller.
  /// Otherwise, creates a direct LSL outlet using useIsolatedOutlets setting.
  Future<LSLOutlet> createOutlet({
    required String outletId,
    required LSLStreamInfo streamInfo,
    LSLPollingConfig? pollingConfig,
  }) async {
    if (_outlets.containsKey(outletId)) {
      throw LSLStreamManagerException('Outlet $outletId already exists');
    }

    final effectiveConfig = pollingConfig ?? config.pollingConfig;

    try {
      // If using polling isolate, outlets are managed by the isolate controller
      if (effectiveConfig.usePollingIsolate) {
        // Outlets via polling isolate are handled differently - they're created within the isolate
        // The isolate controller manages the actual outlet creation with useIsolatedOutlets setting
        throw LSLStreamManagerException(
          'Direct outlet creation not supported when usePollingIsolate is true. '
          'Use createIsolateController and manage outlets through the isolate.',
        );
      }

      // Direct outlet creation (no polling isolate)
      final outlet = await _lsl.createOutlet(
        streamInfo: streamInfo,
        chunkSize: config.transportConfig.outletChunkSize,
        maxBuffer: config.transportConfig.maxOutletBuffer,
        useIsolates: effectiveConfig.useIsolatedOutlets,
      );

      _outlets[outletId] = outlet;
      emitEvent(LSLOutletCreated(resourceId, outletId, streamInfo));

      logger.fine('Created direct outlet: $outletId');
      return outlet;
    } catch (e) {
      _markResourceErrored(outletId, 'Failed to create outlet: $e');
      rethrow;
    }
  }

  /// Create an LSL inlet (direct or via polling isolate)
  ///
  /// If usePollingIsolate is true, this will be managed by an isolate controller.
  /// Otherwise, creates a direct LSL inlet using useIsolatedInlets setting.
  Future<LSLInlet> createInlet({
    required String inletId,
    required LSLStreamInfo streamInfo,
    LSLPollingConfig? pollingConfig,
  }) async {
    if (_inlets.containsKey(inletId)) {
      throw LSLStreamManagerException('Inlet $inletId already exists');
    }

    final effectiveConfig = pollingConfig ?? config.pollingConfig;

    try {
      // If using polling isolate, inlets are managed by the isolate controller
      if (effectiveConfig.usePollingIsolate) {
        // Inlets via polling isolate are handled differently - they're created within the isolate
        // The isolate controller manages the actual inlet creation with useIsolatedInlets setting
        throw LSLStreamManagerException(
          'Direct inlet creation not supported when usePollingIsolate is true. '
          'Use createIsolateController and manage inlets through the isolate.',
        );
      }

      // Direct inlet creation (no polling isolate)
      final inlet = await _lsl.createInlet(
        streamInfo: streamInfo,
        maxBuffer: config.transportConfig.maxInletBuffer,
        chunkSize: config.transportConfig.inletChunkSize,
        recover: config.transportConfig.enableRecovery,
        includeMetadata: true,
        useIsolates: effectiveConfig.useIsolatedInlets,
      );

      _inlets[inletId] = inlet;
      emitEvent(LSLInletCreated(resourceId, inletId, streamInfo));

      logger.fine('Created direct inlet: $inletId');
      return inlet;
    } catch (e) {
      _markResourceErrored(inletId, 'Failed to create inlet: $e');
      rethrow;
    }
  }

  /// Create a continuous resolver by predicate
  LSLStreamResolverContinuousByPredicate createResolverByPredicate({
    required String resolverId,
    required String predicate,
    double? forgetAfter,
    int? maxStreams,
  }) {
    if (_resolvers.containsKey(resolverId)) {
      throw LSLStreamManagerException('Resolver $resolverId already exists');
    }

    try {
      final resolver = _lsl.createContinuousStreamResolverByPredicate(
        predicate: predicate,
        forgetAfter:
            forgetAfter ?? config.transportConfig.resolverConfig.forgetAfter,
        maxStreams:
            maxStreams ??
            config.transportConfig.resolverConfig.maxStreamsPerResolver,
      );

      _resolvers[resolverId] = resolver;
      emitEvent(LSLResolverCreated(resourceId, resolverId, predicate));

      logger.fine('Created resolver: $resolverId');
      return resolver;
    } catch (e) {
      _markResourceErrored(resolverId, 'Failed to create resolver: $e');
      rethrow;
    }
  }

  /// Create an isolate controller for polling-based operations
  ///
  /// This is used when usePollingIsolate is true. The isolate controller
  /// will handle inlet/outlet creation within the isolate using the
  /// useIsolatedInlets/useIsolatedOutlets settings.
  Future<LSLIsolateController> createIsolateController({
    required String controllerId,
    LSLPollingConfig? pollingConfig,
  }) async {
    if (_isolateControllers.containsKey(controllerId)) {
      throw LSLStreamManagerException(
        'Isolate controller $controllerId already exists',
      );
    }

    final effectiveConfig = pollingConfig ?? config.pollingConfig;

    try {
      final controller = LSLIsolateController(
        controllerId: controllerId,
        pollingConfig: effectiveConfig,
      );

      _isolateControllers[controllerId] = controller;
      emitEvent(LSLIsolateControllerCreated(resourceId, controllerId));

      logger.fine(
        'Created isolate controller: $controllerId (useIsolatedInlets: ${effectiveConfig.useIsolatedInlets}, useIsolatedOutlets: ${effectiveConfig.useIsolatedOutlets})',
      );
      return controller;
    } catch (e) {
      _markResourceErrored(
        controllerId,
        'Failed to create isolate controller: $e',
      );
      rethrow;
    }
  }

  /// Start a polling isolate for inlet operations
  ///
  /// This is a convenience method that creates an isolate controller and starts
  /// the inlet polling isolate with the correct configuration.
  Future<LSLIsolateController> startInletPolling({
    required String controllerId,
    LSLPollingConfig? pollingConfig,
  }) async {
    final controller = await createIsolateController(
      controllerId: controllerId,
      pollingConfig: pollingConfig,
    );

    final effectiveConfig = pollingConfig ?? config.pollingConfig;

    // Start the inlet polling isolate
    final params = LSLInletIsolateParams(
      nodeId: nodeId,
      config: effectiveConfig,
      sendPort: null, // Will be set by controller
      receiveOwnMessages: false,
    );

    await controller.start(lslInletConsumerIsolate, params);
    await controller.ready;

    logger.info('Started inlet polling isolate: $controllerId');
    return controller;
  }

  /// Start a polling isolate for outlet operations
  ///
  /// This is a convenience method that creates an isolate controller and starts
  /// the outlet polling isolate with the correct configuration.
  Future<LSLIsolateController> startOutletPolling({
    required String controllerId,
    LSLPollingConfig? pollingConfig,
  }) async {
    final controller = await createIsolateController(
      controllerId: controllerId,
      pollingConfig: pollingConfig,
    );

    final effectiveConfig = pollingConfig ?? config.pollingConfig;

    // Start the outlet polling isolate
    final params = LSLOutletIsolateParams(
      nodeId: nodeId,
      config: effectiveConfig,
      sendPort: null, // Will be set by controller
    );

    await controller.start(lslOutletProducerIsolate, params);
    await controller.ready;

    logger.info('Started outlet polling isolate: $controllerId');
    return controller;
  }

  // === CONVENIENCE METHODS ===

  /// Check if an outlet exists
  bool hasOutlet(String outletId) => _outlets.containsKey(outletId);

  /// Check if an inlet exists
  bool hasInlet(String inletId) => _inlets.containsKey(inletId);

  /// Check if a resolver exists
  bool hasResolver(String resolverId) => _resolvers.containsKey(resolverId);

  /// Check if an isolate controller exists
  bool hasIsolateController(String controllerId) =>
      _isolateControllers.containsKey(controllerId);

  /// Get an outlet by ID
  LSLOutlet? getOutlet(String outletId) => _outlets[outletId];

  /// Get an inlet by ID
  LSLInlet? getInlet(String inletId) => _inlets[inletId];

  /// Get a resolver by ID
  LSLStreamResolverContinuous? getResolver(String resolverId) =>
      _resolvers[resolverId];

  /// Get an isolate controller by ID
  LSLIsolateController? getIsolateController(String controllerId) =>
      _isolateControllers[controllerId];

  /// Remove and dispose an outlet
  Future<void> removeOutlet(String outletId) async {
    final outlet = _outlets.remove(outletId);
    if (outlet != null) {
      try {
        await outlet.destroy();
        emitEvent(LSLOutletDestroyed(resourceId, outletId));
      } catch (e) {
        logger.warning('Error disposing outlet $outletId: $e');
        _markResourceErrored(outletId, 'Failed to dispose outlet: $e');
      }
    }
    _erroredResources.remove(outletId);
  }

  /// Remove and dispose an inlet
  Future<void> removeInlet(String inletId) async {
    final inlet = _inlets.remove(inletId);
    if (inlet != null) {
      try {
        await inlet.destroy();
        emitEvent(LSLInletDestroyed(resourceId, inletId));
      } catch (e) {
        logger.warning('Error disposing inlet $inletId: $e');
        _markResourceErrored(inletId, 'Failed to dispose inlet: $e');
      }
    }
    _erroredResources.remove(inletId);
  }

  /// Remove and dispose a resolver
  void removeResolver(String resolverId) {
    final resolver = _resolvers.remove(resolverId);
    if (resolver != null) {
      try {
        resolver.destroy();
        emitEvent(LSLResolverDestroyed(resourceId, resolverId));
      } catch (e) {
        logger.warning('Error disposing resolver $resolverId: $e');
        _markResourceErrored(resolverId, 'Failed to dispose resolver: $e');
      }
    }
    _erroredResources.remove(resolverId);
  }

  /// Remove and dispose an isolate controller
  Future<void> removeIsolateController(String controllerId) async {
    final controller = _isolateControllers.remove(controllerId);
    if (controller != null) {
      try {
        await controller.stop();
        emitEvent(LSLIsolateControllerDestroyed(resourceId, controllerId));
      } catch (e) {
        logger.warning('Error stopping isolate controller $controllerId: $e');
        _markResourceErrored(
          controllerId,
          'Failed to stop isolate controller: $e',
        );
      }
    }
    _erroredResources.remove(controllerId);
  }

  // === PRIVATE METHODS ===

  void _updateResourceState(ResourceState newState, [String? reason]) {
    if (_resourceState == newState) return;

    final oldState = _resourceState;
    _resourceState = newState;

    final stateEvent = ResourceStateEvent(
      resourceId: resourceId,
      oldState: oldState,
      newState: newState,
      reason: reason,
      timestamp: DateTime.now(),
    );

    if (!_resourceStateController.isClosed) {
      _resourceStateController.add(stateEvent);
    }

    logger.fine(
      'Stream manager $resourceId state changed: $oldState -> $newState ${reason != null ? '($reason)' : ''}',
    );
  }

  void _markResourceErrored(String resourceId, String error) {
    _erroredResources.add(resourceId);
    emitEvent(LSLStreamError(this.resourceId, resourceId, error));
    logger.warning('Resource $resourceId marked as errored: $error');
  }
}

/// Exception for LSL stream manager operations
class LSLStreamManagerException implements Exception {
  final String message;

  const LSLStreamManagerException(this.message);

  @override
  String toString() => 'LSLStreamManagerException: $message';
}
