import 'dart:async';
import '../../coordinator_factory_interface.dart';
import '../../session_config.dart' as config;
import 'config/lsl_stream_config.dart';
import 'core/lsl_network_factory.dart' as lsl_factory;
import 'core/lsl_api_manager.dart';

/// LSL implementation of TransportFactoryInterface
///
/// This adapter wraps the existing LSLNetworkFactory to conform to the
/// standard transport interface, enabling seamless integration with the
/// conditional import system.
class LSLTransportFactory implements TransportFactoryInterface {
  static LSLTransportFactory? _instance;
  static LSLTransportFactory get instance =>
      _instance ??= LSLTransportFactory._();

  LSLTransportFactory._();

  @override
  String get name => 'lsl';

  @override
  List<String> get supportedPlatforms => [
    'android',
    'ios',
    'linux',
    'macos',
    'windows',
  ];

  @override
  bool get isAvailable {
    try {
      // Check if LSL is available (will only work on non-web platforms)
      // Since LSLApiManager doesn't have isSupported, we try to access LSL
      LSLApiManager.createDefaultConfig();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    if (!isAvailable) {
      throw TransportUnavailableException(name);
    }

    // Convert generic config to LSL-specific config if needed
    LSLApiConfig? lslConfig;
    if (config != null && config.containsKey('lsl')) {
      final lslConfigData = config['lsl'] as Map<String, dynamic>;
      lslConfig = LSLApiConfig.fromMap(lslConfigData);
    }

    await lsl_factory.LSLNetworkFactory.instance.initialize(
      config: lslConfig?.toLSLConfig() ?? LSLApiManager.createDefaultConfig(),
    );
  }

  @override
  Future<config.SessionResult> createSession(
    config.SessionConfig sessionConfig,
  ) async {
    if (!isAvailable) {
      throw TransportUnavailableException(name);
    }

    try {
      // Convert SessionConfig to LSL-specific parameters
      final networkSession = await lsl_factory.LSLNetworkFactory.instance
          .createNetwork(
            sessionId: sessionConfig.sessionId,
            nodeId: sessionConfig.nodeId,
            nodeName: sessionConfig.nodeName,
            topology: sessionConfig.topology,
            sessionMetadata: sessionConfig.sessionMetadata,
            heartbeatInterval: sessionConfig.heartbeatInterval,
          );

      return config.SessionResult(
        session: networkSession,
        transportUsed: name,
        metadata: {
          'transport_version': 'lsl_v1',
          'capabilities': sessionConfig.nodeMetadata,
          'lsl_initialized': LSLApiManager.isInitialized,
        },
      );
    } catch (e) {
      throw TransportException(name, 'Failed to create LSL session: $e', e);
    }
  }

  @override
  config.NetworkSession? getSession(String sessionId) {
    return lsl_factory.LSLNetworkFactory.instance.getNetworkSession(sessionId);
  }

  @override
  List<String> get activeSessionIds {
    return lsl_factory.LSLNetworkFactory.instance.activeSessionIds;
  }

  @override
  Future<void> dispose() async {
    await lsl_factory.LSLNetworkFactory.instance.dispose();
  }
}

/// Extension to add LSL-specific configuration
extension LSLSessionConfigExtensions on config.SessionConfig {
  /// Add LSL-specific transport configuration
  config.SessionConfig withLSLConfig(LSLApiConfig lslConfig) {
    return withTransportConfig('lsl', lslConfig.toMap());
  }

  /// Add LSL-specific polling configuration
  config.SessionConfig withPollingConfig(Map<String, dynamic> pollingConfig) {
    return withTransportConfig('polling', pollingConfig);
  }
}

/// Helper for creating LSL configurations
class LSLApiConfig {
  final Map<String, dynamic> _config;

  const LSLApiConfig(this._config);

  factory LSLApiConfig.fromMap(Map<String, dynamic> config) {
    return LSLApiConfig(config);
  }

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_config);

  /// Convert to actual LSL API config
  dynamic toLSLConfig() {
    // For now, return the default config since we don't have complex config needs
    return LSLApiManager.createDefaultConfig();
  }

  /// Create default LSL configuration
  factory LSLApiConfig.defaults() {
    return LSLApiConfig({'enable_logging': true, 'log_level': 'info'});
  }
}
