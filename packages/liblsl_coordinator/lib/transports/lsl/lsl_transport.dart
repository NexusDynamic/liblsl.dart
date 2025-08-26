import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:liblsl/lsl.dart';

/// Transport configuration for LSL-based coordination.
class LSLTransportConfig implements ITransportConfig {
  @override
  String get id => 'lsl_transport_config';

  @override
  String get name => 'LSL Transport Configuration';

  @override
  String get description => 'Configuration for LSL Transport';

  /// Configuration for the LSL API, e.g. to disable ipv6.
  late final LSLApiConfig lslApiConfig;

  /// Frequency (in Hz) at which coordination messages are sent.
  final double coordinationFrequency;

  /// Creates a new [LSLTransportConfig] with the given parameters.
  /// If [lslApiConfig] is not provided, a default configuration is used.
  /// The [coordinationFrequency] (Hz) must be greater than 0.
  LSLTransportConfig({
    LSLApiConfig? lslApiConfig,
    this.coordinationFrequency = 100.0,
  }) : super() {
    this.lslApiConfig = lslApiConfig ?? LSLApiConfig();
  }

  @override
  String toString() {
    return 'LSLTransportConfig(lslApiConfig: $lslApiConfig, coordinationFrequency: $coordinationFrequency)';
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'lslApiConfig': lslApiConfig.toIniString(),
      'coordinationFrequency': coordinationFrequency,
    };
  }

  @override
  bool validate({bool throwOnError = false}) {
    if (coordinationFrequency <= 0) {
      if (throwOnError) {
        throw ArgumentError('Coordination frequency must be greater than 0');
      }
      return false;
    }
    return true;
  }

  @override
  LSLTransportConfig copyWith({
    LSLApiConfig? lslApiConfig,
    double? coordinationFrequency,
  }) {
    return LSLTransportConfig(
      lslApiConfig: lslApiConfig ?? this.lslApiConfig,
      coordinationFrequency:
          coordinationFrequency ?? this.coordinationFrequency,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LSLTransportConfig &&
        other.runtimeType == runtimeType &&
        other.lslApiConfig == lslApiConfig &&
        other.coordinationFrequency == coordinationFrequency;
  }

  @override
  int get hashCode {
    return lslApiConfig.hashCode ^ coordinationFrequency.hashCode;
  }
}

/// Factory for creating [LSLTransportConfig] instances.
class LSLTransportConfigFactory implements IConfigFactory<LSLTransportConfig> {
  /// The default configuration has a coordination frequency of 100 Hz
  /// and the default LSL API configuration.
  @override
  LSLTransportConfig defaultConfig() {
    return LSLTransportConfig();
  }

  @override
  LSLTransportConfig fromMap(Map<String, dynamic> map) {
    return LSLTransportConfig(
      lslApiConfig:
          map.containsKey('lslApiConfig')
              ? LSLApiConfig.fromString(map['lslApiConfig'] as String)
              : null,
      coordinationFrequency:
          map.containsKey('coordinationFrequency')
              ? (map['coordinationFrequency'] as num).toDouble()
              : 100.0,
    );
  }
}

/// Resource wrapper for LSL outlets with proper lifecycle management
class OutletResource extends LSLResource {
  final LSLOutlet outlet;

  OutletResource({required this.outlet, super.manager}) : super(id: 'outlet') {
    create();
  }

  @override
  String get id => 'lsl-outlet-${outlet.hashCode}';

  @override
  String? get description => 'LSL Outlet Resource (id: $id)';

  @override
  Future<void> create() async {
    await super.create();
    // No additional creation needed for outlet
  }

  @override
  Future<void> dispose() async {
    outlet.destroy();
    await super.dispose();
  }
}

/// Resource wrapper for LSL inlets with proper lifecycle management
class InletResource extends LSLResource {
  final LSLInlet inlet;

  InletResource({required this.inlet, super.manager}) : super(id: 'inlet') {
    create();
  }

  @override
  String get id => 'lsl-inlet-${inlet.hashCode}';

  @override
  String? get description => 'LSL Inlet Resource (id: $id)';

  @override
  Future<void> create() async {
    await super.create();
    // No additional creation needed for inlet
  }

  @override
  Future<void> dispose() async {
    inlet.destroy();
    await super.dispose();
  }
}

/// LSL Transport implementation for coordination.
class LSLTransport<T extends LSLTransportConfig> extends LSLResource
    implements ITransport, IResourceManager {
  /// The transport ID
  @override
  String get id => 'lsl_transport';

  @override
  String get name => 'LSL Transport';

  @override
  String get description =>
      'Commnication Transport using Lab Streaming Layer (LSL)';

  bool _created = false;
  bool _initialized = false;
  bool _disposed = false;

  @override
  bool get created => _created;
  @override
  bool get disposed => _disposed;

  @override
  bool get initialized => _initialized;

  /// The LSL transport configuration.
  @override
  final T config;

  /// Managed resources (outlets, inlets, discovery instances, etc.)
  final Map<String, IResource> _resources = {};

  /// Creates a new [LSLTransport] with the given [config].
  /// If no configuration is provided, a default configuration is used.
  LSLTransport({T? config})
    : config = config ?? LSLTransportConfigFactory().defaultConfig() as T,
      super(id: 'lsl_transport') {
    this.config.validate(throwOnError: true);
  }

  /// Ensures that the transport is initialized before use.
  void _ensureInitialized() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw StateError('Transport must be initialized before use');
    }
  }

  /// Ensures that the transport is not disposed before use.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Transport has been disposed');
    }
  }

  /// Ensures that the transport is created before use.
  void _ensureCreated() {
    _ensureNotDisposed();
    _ensureInitialized();
    if (!_created) {
      throw StateError('Transport must be created before use');
    }
  }

  /// Initializes the LSL transport by setting the LSL API configuration.
  /// This method must be called before using the transport, subsequent calls
  /// to [LSL.setConfigContent] have no effect once the FFI library is loaded.
  @override
  Future<void> initialize() async {
    _ensureNotDisposed();
    LSL.setConfigContent(config.lslApiConfig);
    _initialized = true;
  }

  /// Creates a new LSL stream with the given [config], [producers], and
  /// [consumers].
  /// This method must be called after [initialize].
  @override
  Future<void> create() async {
    _ensureInitialized();
    if (_created) return;
    await super.create();
    _created = true;
  }

  @override
  void manageResource<R extends IResource>(R resource) {
    resource.updateManager(this);
    _resources[resource.uId] = resource;
  }

  @override
  R releaseResource<R extends IResource>(String resourceUID) {
    final resource = _resources.remove(resourceUID);
    if (resource == null) {
      throw StateError('Resource with UID $resourceUID not found');
    }
    resource.updateManager(null);
    return resource as R;
  }

  /// Creates a managed LSL outlet resource
  Future<OutletResource> createOutlet({
    required LSLStreamInfo streamInfo,
    IResourceManager? manager,
  }) async {
    _ensureCreated();
    final outlet = await LSL.createOutlet(streamInfo: streamInfo);
    final resource = OutletResource(outlet: outlet, manager: manager ?? this);

    // Only manage the resource if no external manager is specified
    if (manager == null) {
      manageResource(resource);
    } else {
      manager.manageResource(resource);
    }

    return resource;
  }

  /// Creates a managed LSL inlet resource
  Future<InletResource> createInlet({
    required LSLStreamInfo streamInfo,
    bool includeMetadata = true,
    IResourceManager? manager,
  }) async {
    _ensureCreated();
    final inlet = await LSL.createInlet(
      streamInfo: streamInfo,
      includeMetadata: includeMetadata,
    );
    final resource = InletResource(inlet: inlet, manager: manager ?? this);

    // Only manage the resource if no external manager is specified
    if (manager == null) {
      manageResource(resource);
    } else {
      manager.manageResource(resource);
    }

    return resource;
  }

  /// Creates a managed discovery resource
  Future<LslDiscovery> createDiscovery({
    required NetworkStreamConfig streamConfig,
    required CoordinationConfig coordinationConfig,
    required String id,
    String? predicate,
    IResourceManager? manager,
  }) async {
    _ensureCreated();
    final discovery = LslDiscovery(
      streamConfig: streamConfig,
      coordinationConfig: coordinationConfig,
      id: id,
      predicate: predicate,
      manager: manager ?? this,
    );
    await discovery.create();

    // Only manage the resource if no external manager is specified
    if (manager == null) {
      manageResource(discovery);
    } else {
      manager.manageResource(discovery);
    }

    return discovery;
  }

  /// Disposes the LSL transport and releases any resources.
  /// After calling this method, the transport is no longer usable.
  @override
  Future<void> dispose() async {
    _ensureCreated();

    // Dispose all managed resources
    final disposeFutures = <Future>[];
    for (final resource in _resources.values) {
      final dispose = resource.dispose();
      if (dispose is Future) {
        disposeFutures.add(dispose);
      }
    }
    await Future.wait(disposeFutures);
    _resources.clear();

    await super.dispose();
    _disposed = true;
    _created = false;
    _initialized = false;
  }

  @override
  Future<NetworkStream> createStream(
    NetworkStreamConfig streamConfig, {
    CoordinationSession? coordinationSession,
  }) async {
    _ensureCreated();

    if (coordinationSession == null) {
      throw ArgumentError('CoordinationSession is required for LSL transport');
    }

    if (coordinationSession is! LSLCoordinationSession) {
      throw ArgumentError(
        'LSL transport requires LSLCoordinationSession, got ${coordinationSession.runtimeType}',
      );
    }

    // Use the factory to create the appropriate stream type
    final factory = LSLNetworkStreamFactory();

    if (streamConfig is CoordinationStreamConfig) {
      return await factory.createCoordinationStream(
        streamConfig,
        coordinationSession,
      );
    } else if (streamConfig is DataStreamConfig) {
      return await factory.createDataStream(streamConfig, coordinationSession);
    } else {
      throw ArgumentError(
        'Unknown stream config type: ${streamConfig.runtimeType}',
      );
    }
  }

  @override
  String toString() {
    return 'LSLTransport(config: $config)';
  }
}
