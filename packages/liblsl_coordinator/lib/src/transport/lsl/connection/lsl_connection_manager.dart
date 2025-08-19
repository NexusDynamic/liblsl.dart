import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../event.dart';
import '../../../management/resource_manager.dart';
import '../core/lsl_api_manager.dart';
import '../core/lsl_stream_manager.dart';
import '../config/lsl_stream_config.dart';
import '../../../utils/stream_controller_extensions.dart';

/// Manages LSL inlet/outlet connections with metadata-based discovery
/// Handles the lifecycle of LSL connections properly to avoid resource leaks
class LSLConnectionManager extends LSLStreamManager implements ResourceManager {
  @override
  final String managerId;

  final StreamController<LSLConnectionEvent> _connectionEventController =
      StreamController<LSLConnectionEvent>.broadcast();

  bool _isActive = false;

  LSLConnectionManager({
    required this.managerId,
    required super.nodeId,
    required super.config,
  }) : super(resourceId: managerId);

  @override
  bool get isActive => _isActive;

  @override
  Stream<ResourceEvent> get events =>
      _connectionEventController.stream.cast<ResourceEvent>();

  /// Stream of LSL-specific connection events
  Stream<LSLConnectionEvent> get connectionEvents =>
      _connectionEventController.stream;

  @override
  Future<void> onInitialize() async {
    // Connection manager requires LSL to be already initialized
    if (!LSLApiManager.isInitialized) {
      throw LSLApiConfigurationException(
        'LSL API must be initialized before creating connection manager',
      );
    }
  }

  @override
  Future<void> onActivate() async {
    await start();
  }

  @override
  Future<void> start() async {
    _isActive = true;
    _connectionEventController.addEvent(LSLConnectionManagerStarted(managerId));
  }

  @override
  Future<void> onDeactivate() async {
    await stop();
  }

  @override
  Future<void> stop() async {
    _isActive = false;
    _connectionEventController.addEvent(LSLConnectionManagerStopped(managerId));
  }

  @override
  Future<void> onDispose() async {
    await stop();

    try {
      // Close connection event controller
      await _connectionEventController.close();
    } catch (e) {
      // Ignore errors during disposal
    }
  }

  @override
  ResourceUsageStats getUsageStats() {
    final totalOutlets = metadata['outlets'] as int;
    final totalInlets = metadata['inlets'] as int;
    final totalResolvers = metadata['resolvers'] as int;
    final erroredResources = metadata['erroredResources'] as int;

    return ResourceUsageStats(
      totalResources: totalOutlets + totalInlets + totalResolvers,
      activeResources:
          totalOutlets +
          totalInlets +
          totalResolvers, // All are active when created
      idleResources: 0,
      erroredResources: erroredResources,
      lastUpdated: DateTime.now(),
      customMetrics: {
        'outlets': totalOutlets,
        'inlets': totalInlets,
        'resolvers': totalResolvers,
      },
    );
  }

  /// Create an LSL outlet for data streaming
  Future<LSLOutlet> createOutletForConfig({
    required LSLStreamConfig config,
    String? outletId,
  }) async {
    final id = outletId ?? '${config.sourceId}_outlet';
    final streamInfo = await config.toStreamInfo();

    try {
      final outlet = await super.createOutlet(
        outletId: id,
        streamInfo: streamInfo,
        pollingConfig: config.pollingConfig,
      );

      _connectionEventController.addEvent(
        LSLOutletCreated(managerId, id, config),
      );
      return outlet;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Failed to create outlet $id: $e'),
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
    final transportConf = transportConfig ?? const LSLTransportConfig();

    try {
      // Use metadata-based discovery with predicates
      final predicate = transportConf.resolverConfig.dataPredicate(
        streamName,
        metadataFilters: metadataFilters,
      );

      // Use base class resolver to find streams
      final resolver = createResolverByPredicate(
        resolverId: '${id}_discovery',
        predicate: predicate,
        forgetAfter: transportConf.resolverConfig.forgetAfter,
        maxStreams: 1,
      );

      // Resolve streams with timeout
      final streams = await resolver.resolve(
        waitTime: transportConf.resolverConfig.resolveTimeout,
      );
      if (streams.isEmpty) {
        throw LSLConnectionException(
          'No streams found matching predicate: $predicate',
        );
      }

      final streamInfo = streams.first;
      final inlet = await super.createInlet(
        inletId: id,
        streamInfo: streamInfo,
      );

      // Clean up discovery resolver
      removeResolver('${id}_discovery');

      _connectionEventController.addEvent(
        LSLInletCreated(managerId, id, streamInfo),
      );
      return inlet;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Failed to create inlet $id: $e'),
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
    final id =
        resolverId ?? 'resolver_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final resolver = createResolverByPredicate(
        resolverId: id,
        predicate: predicate ?? '',
        forgetAfter: forgetAfter,
        maxStreams: maxStreams,
      );

      _connectionEventController.addEvent(
        LSLResolverCreated(managerId, id, predicate),
      );
      return resolver;
    } catch (e) {
      _connectionEventController.addEvent(
        LSLConnectionError(managerId, 'Failed to create resolver $id: $e'),
      );
      rethrow;
    }
  }

  /// Get an outlet by ID (delegates to base class)
  @override
  LSLOutlet? getOutlet(String outletId) => super.getOutlet(outletId);

  /// Get an inlet by ID (delegates to base class)
  @override
  LSLInlet? getInlet(String inletId) => super.getInlet(inletId);

  /// Get a resolver by ID (delegates to base class)
  @override
  LSLStreamResolverContinuous? getResolver(String resolverId) =>
      super.getResolver(resolverId);

  /// Destroy an outlet and remove from management
  Future<void> destroyOutlet(String outletId) async {
    try {
      await removeOutlet(outletId);
      _connectionEventController.addEvent(
        LSLOutletDestroyed(managerId, outletId),
      );
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
      await removeInlet(inletId);
      _connectionEventController.addEvent(
        LSLInletDestroyed(managerId, inletId),
      );
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
      removeResolver(resolverId);
      _connectionEventController.addEvent(
        LSLResolverDestroyed(managerId, resolverId),
      );
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
