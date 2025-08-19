import 'package:liblsl/lsl.dart';
import 'dart:async';

/// Exception thrown when LSL API configuration is attempted after initialization
class LSLApiConfigurationException implements Exception {
  final String message;

  const LSLApiConfigurationException(this.message);

  @override
  String toString() => 'LSLApiConfigurationException: $message';
}

/// Configured LSL wrapper that prevents config changes after initialization
class ConfiguredLSL {
  final LSLApiConfig _config;
  final DateTime _initializedAt;

  ConfiguredLSL._(this._config) : _initializedAt = DateTime.now();

  /// Get the configuration used to initialize this instance
  LSLApiConfig get config => _config;

  /// When this instance was initialized
  DateTime get initializedAt => _initializedAt;

  // Override the two config methods to prevent changes
  void setConfigFilename(String filename) {
    throw LSLApiConfigurationException(
      'Cannot change LSL API configuration after initialization.\n'
      'Current config initialized at: $_initializedAt\n'
      'To apply new configuration, restart the application and call LSLApiManager.initialize() with new config.',
    );
  }

  void setConfigContent(LSLApiConfig content) {
    throw LSLApiConfigurationException(
      'Cannot change LSL API configuration after initialization.\n'
      'Current config initialized at: $_initializedAt\n'
      'To apply new configuration, restart the application and call LSLApiManager.initialize() with new config.',
    );
  }

  // Delegate all other LSL methods to the static LSL class
  Future<LSLStreamInfoWithMetadata> createStreamInfo({
    String streamName = "DartLSLStream",
    LSLContentType streamType = LSLContentType.eeg,
    int channelCount = 1,
    double sampleRate = 150.0,
    LSLChannelFormat channelFormat = LSLChannelFormat.float32,
    String sourceId = "DartLSL",
  }) => LSL.createStreamInfo(
    streamName: streamName,
    streamType: streamType,
    channelCount: channelCount,
    sampleRate: sampleRate,
    channelFormat: channelFormat,
    sourceId: sourceId,
  );

  int get version => LSL.version;

  Future<LSLOutlet> createOutlet({
    required LSLStreamInfo streamInfo,
    int chunkSize = 1,
    int maxBuffer = 360,
    bool useIsolates = true,
  }) => LSL.createOutlet(
    streamInfo: streamInfo,
    chunkSize: chunkSize,
    maxBuffer: maxBuffer,
    useIsolates: useIsolates,
  );

  Future<LSLInlet> createInlet<T>({
    required LSLStreamInfo streamInfo,
    int maxBuffer = 360,
    int chunkSize = 0,
    bool recover = true,
    double createTimeout = LSL_FOREVER,
    bool includeMetadata = false,
    bool useIsolates = true,
  }) => LSL.createInlet<T>(
    streamInfo: streamInfo,
    maxBuffer: maxBuffer,
    chunkSize: chunkSize,
    recover: recover,
    createTimeout: createTimeout,
    includeMetadata: includeMetadata,
    useIsolates: useIsolates,
  );

  // Stream resolution methods
  Future<List<LSLStreamInfo>> resolveStreams({
    double waitTime = 5.0,
    int maxStreams = 5,
  }) => LSL.resolveStreams(waitTime: waitTime, maxStreams: maxStreams);

  Future<List<LSLStreamInfo>> resolveStreamsByProperty({
    required LSLStreamProperty property,
    required String value,
    double waitTime = 5.0,
    int minStreamCount = 0,
    int maxStreams = 5,
  }) => LSL.resolveStreamsByProperty(
    property: property,
    value: value,
    waitTime: waitTime,
    minStreamCount: minStreamCount,
    maxStreams: maxStreams,
  );

  Future<List<LSLStreamInfo>> resolveStreamsByPredicate({
    required String predicate,
    double waitTime = 5.0,
    int minStreamCount = 0,
    int maxStreams = 5,
  }) => LSL.resolveStreamsByPredicate(
    predicate: predicate,
    waitTime: waitTime,
    minStreamCount: minStreamCount,
    maxStreams: maxStreams,
  );

  LSLStreamResolver createResolver({int maxStreams = 5}) =>
      LSL.createResolver(maxStreams: maxStreams);

  LSLStreamResolverContinuous createContinuousStreamResolver({
    double forgetAfter = 5.0,
    int maxStreams = 5,
  }) => LSL.createContinuousStreamResolver(
    forgetAfter: forgetAfter,
    maxStreams: maxStreams,
  );

  /// Create a continuous stream resolver by predicate
  LSLStreamResolverContinuousByPredicate
  createContinuousStreamResolverByPredicate({
    required String predicate,
    double forgetAfter = 5.0,
    int maxStreams = 5,
  }) => LSLStreamResolverContinuousByPredicate(
    predicate: predicate,
    forgetAfter: forgetAfter,
    maxStreams: maxStreams,
  )..create();

  double localClock() => LSL.localClock();

  String libraryInfo() => LSL.libraryInfo();
}

/// Manages LSL API configuration with strict early initialization
class LSLApiManager {
  static ConfiguredLSL? _configuredLSL;
  static final Completer<ConfiguredLSL> _initializationCompleter =
      Completer<ConfiguredLSL>();

  /// Whether the LSL API has been initialized
  static bool get isInitialized => _configuredLSL != null;

  /// Get the configured LSL instance (throws if not initialized)
  static ConfiguredLSL get lsl {
    if (_configuredLSL == null) {
      throw LSLApiConfigurationException(
        'LSL API must be initialized before use. Call LSLApiManager.initialize() first.',
      );
    }
    return _configuredLSL!;
  }

  /// Wait for LSL API to be initialized and get the configured instance
  static Future<ConfiguredLSL> get initialized =>
      _initializationCompleter.future;

  /// Initialize the LSL API with the given configuration
  /// This MUST be called before any other LSL operations
  /// Can only be called once - subsequent calls will throw an exception
  static Future<ConfiguredLSL> initialize(LSLApiConfig config) async {
    if (_configuredLSL != null) {
      throw LSLApiConfigurationException(
        'LSL API is already initialized. To change configuration, restart the application.\n'
        'Current config: ${_configuredLSL!.config}\n'
        'Attempted config: $config',
      );
    }

    try {
      // Set the LSL configuration - this must be the first LSL API call
      LSL.setConfigContent(config);

      _configuredLSL = ConfiguredLSL._(config);
      _initializationCompleter.complete(_configuredLSL!);

      return _configuredLSL!;
    } catch (e) {
      final exception = LSLApiConfigurationException(
        'Failed to initialize LSL API: $e',
      );
      _initializationCompleter.completeError(exception);
      throw exception;
    }
  }

  /// Create a default configuration for most use cases
  static LSLApiConfig createDefaultConfig() => LSLApiConfig();

  /// Create configuration with common settings
  static LSLApiConfig createCustomConfig() {
    final config = LSLApiConfig();
    // Configure settings when API provides them
    return config;
  }

  /// Reset for testing purposes only
  /// WARNING: This is dangerous and should only be used in tests
  static void resetForTesting() {
    if (!_isTestEnvironment()) {
      throw LSLApiConfigurationException(
        'resetForTesting() can only be called in test environments',
      );
    }

    _configuredLSL = null;
    // Note: Cannot reset completer once completed
  }

  static bool _isTestEnvironment() {
    // Simple check - in real implementation might check Zone or test runner
    return Zone.current[#test] == true;
  }
}

/// Usage:
/// ```dart
/// void main() async {
///   // FIRST thing in main() - initialize LSL with config
///   final lsl = await LSLApiManager.initialize(LSLApiManager.createDefaultConfig());
///   
///   // Throughout the coordinator, use LSLApiManager.lsl instead of LSL
///   final streamInfo = await LSLApiManager.lsl.createStreamInfo(
///     streamName: 'test',
///     sourceId: 'coordinator',
///   );
///   
///   // Any attempt to change config will throw an exception with guidance
///   // LSLApiManager.lsl.setConfigContent(...); // <- throws exception
///   
///   runApp(MyApp());
/// }
/// ```
