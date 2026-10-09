import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

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

  /// Receive without polling.
  ///
  /// By default an inlet is polled, at the sample period for a data stream
  /// (within 0.1 to 10 ms), so a sample is seen up to one poll interval
  /// after it arrives and that wait is part of every transit time. With
  /// this set, each inlet instead has a native thread waiting inside
  /// liblsl's pull (`LSLInlet.sampleStream`), which liblsl wakes when a
  /// sample is queued: the receive clock is read as the sample arrives and
  /// the sample is forwarded at once. It applies to the coordination stream
  /// and to data streams.
  ///
  /// The cost is one native thread per inlet, idle while its stream is
  /// quiet; it is not an isolate, so it does not hold up other isolates.
  /// Local to this node: peers need not agree on it.
  ///
  /// An inlet is then read only by its listener; see
  /// [restartFailedListeners] for what happens when that ends by itself.
  final bool eventDrivenInlets;

  /// With [eventDrivenInlets]: restart an inlet's listener if it ends by
  /// itself. On by default.
  ///
  /// Such a listener can end without being stopped: a pull that fails with
  /// anything but a timeout, or an error of its own. From then on nothing
  /// reads that inlet, while the inlet stays open and its peer registered.
  /// Either way this is logged as severe and reported on the stream's
  /// `inletHealth` (and so as a `StreamReceiveHealthEvent` on the session's
  /// events). With this set the listener is also started again, at once the
  /// first time and with a growing delay (up to 5 s) after that, and from
  /// the third failure in a row, or at once if liblsl reported the stream
  /// lost, on a newly opened inlet. It keeps trying for as long as the inlet
  /// exists. Without it, the inlet stays unread until the stream is paused
  /// and resumed, flushed, or the inlet is removed and added again.
  ///
  /// Local to this node, and without effect on polled inlets.
  final bool restartFailedListeners;

  @override
  LSLTransport createTransport() => LSLTransport(config: this);

  /// Creates a new [LSLTransportConfig] with the given parameters.
  /// If [lslApiConfig] is not provided, a default configuration is used.
  /// The [coordinationFrequency] (Hz) must be greater than 0.
  LSLTransportConfig({
    LSLApiConfig? lslApiConfig,
    this.coordinationFrequency = 100.0,
    this.eventDrivenInlets = false,
    this.restartFailedListeners = true,
  }) : super() {
    this.lslApiConfig = lslApiConfig ?? LSLApiConfig();
  }

  @override
  String toString() {
    return 'LSLTransportConfig(lslApiConfig: $lslApiConfig, coordinationFrequency: $coordinationFrequency, eventDrivenInlets: $eventDrivenInlets, restartFailedListeners: $restartFailedListeners)';
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'lslApiConfig': lslApiConfig.toIniString(),
      'coordinationFrequency': coordinationFrequency,
      'eventDrivenInlets': eventDrivenInlets,
      'restartFailedListeners': restartFailedListeners,
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
    bool? eventDrivenInlets,
    bool? restartFailedListeners,
  }) {
    return LSLTransportConfig(
      lslApiConfig: lslApiConfig ?? this.lslApiConfig,
      coordinationFrequency:
          coordinationFrequency ?? this.coordinationFrequency,
      eventDrivenInlets: eventDrivenInlets ?? this.eventDrivenInlets,
      restartFailedListeners:
          restartFailedListeners ?? this.restartFailedListeners,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LSLTransportConfig &&
        other.runtimeType == runtimeType &&
        other.lslApiConfig == lslApiConfig &&
        other.coordinationFrequency == coordinationFrequency &&
        other.eventDrivenInlets == eventDrivenInlets &&
        other.restartFailedListeners == restartFailedListeners;
  }

  @override
  int get hashCode {
    return lslApiConfig.hashCode ^
        coordinationFrequency.hashCode ^
        eventDrivenInlets.hashCode ^
        restartFailedListeners.hashCode;
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
      lslApiConfig: map.containsKey('lslApiConfig')
          ? LSLApiConfig.fromString(map['lslApiConfig'] as String)
          : null,
      coordinationFrequency: map.containsKey('coordinationFrequency')
          ? (map['coordinationFrequency'] as num).toDouble()
          : 100.0,
      eventDrivenInlets: map['eventDrivenInlets'] as bool? ?? false,
      restartFailedListeners: map['restartFailedListeners'] as bool? ?? true,
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
    implements ITransport, IResourceManager, ITransportClock {
  /// LSL's clock, which every LSL timestamp is a reading of.
  @override
  double now() => LSL.localClock();

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

  @override
  NetworkStreamFactory get streamFactory => LSLNetworkStreamFactory();

  // Null: liblsl already runs a time_receiver per inlet and reports the result
  // through lsl_time_correction, which the inlet isolate caches and attaches to
  // every sample. A second estimator here would duplicate it, less accurately
  // and over the coordination stream instead of LSL's dedicated UDP service.
  @override
  PeerClockOffsets? get clockOffsets => null;

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
  @override
  Future<LslDiscovery> createDiscovery({
    required NetworkStreamConfig streamConfig,
    required CoordinationConfig coordinationConfig,
    required String id,
    IResourceManager? manager,
  }) async {
    _ensureCreated();
    final discovery = LslDiscovery(
      streamConfig: streamConfig,
      coordinationConfig: coordinationConfig,
      id: id,
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
      if (resource.disposed) continue;
      final dispose = resource.dispose();
      if (dispose is Future) {
        disposeFutures.add(dispose);
      }
    }
    logger.fine('Disposing ${disposeFutures.length} managed resources');
    await Future.wait(disposeFutures);
    _resources.clear();

    await super.dispose();
    _disposed = true;
    _created = false;
    _initialized = false;
  }

  @override
  String toString() {
    return 'LSLTransport(config: $config)';
  }
}
