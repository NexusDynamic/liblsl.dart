import 'package:liblsl_coordinator/liblsl_coordinator.dart';
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

/// LSL Transport implementation for coordination.
class LSLTransport<T extends LSLTransportConfig> implements ITransport {
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

  /// Creates a new [LSLTransport] with the given [config].
  /// If no configuration is provided, a default configuration is used.
  LSLTransport({T? config})
    : config = config ?? LSLTransportConfigFactory().defaultConfig() as T {
    config!.validate(throwOnError: true);
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
    _created = true;
  }

  /// Disposes the LSL transport and releases any resources.
  /// After calling this method, the transport is no longer usable.
  @override
  Future<void> dispose() async {
    _ensureCreated();
    _disposed = true;
    _created = false;
    _initialized = false;
  }

  @override
  Future<NetworkStream> createStream(
    NetworkStreamConfig config, {
    List<Node>? producers,
    List<Node>? consumers,
  }) async {
    _ensureCreated();
    // Create and return an LSL stream with the given configuration.
    throw UnimplementedError();
    // return LSLNetworkStreamFactory().createDataStream(
    //   config,
    //   producers: producers,
    //   consumers: consumers,
    // );
  }

  @override
  String toString() {
    return 'LSLTransport(config: $config)';
  }
}
