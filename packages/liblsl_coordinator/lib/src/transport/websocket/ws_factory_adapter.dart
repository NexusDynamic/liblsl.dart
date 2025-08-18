import 'dart:async';
import '../../coordinator_factory_interface.dart';
import '../../session_config.dart' as config;
import 'core/ws_network_factory.dart';

/// WebSocket implementation of TransportFactoryInterface
/// 
/// This provides WebSocket-based coordination for web platforms where
/// LSL is not available. Uses WebRTC or WebSocket connections for
/// peer-to-peer and client-server coordination.
class WebSocketTransportFactory implements TransportFactoryInterface {
  static WebSocketTransportFactory? _instance;
  static WebSocketTransportFactory get instance => _instance ??= WebSocketTransportFactory._();
  
  WebSocketTransportFactory._();
  
  @override
  String get name => 'websocket';
  
  @override
  List<String> get supportedPlatforms => [
    'web',
    'android',
    'ios', 
    'linux',
    'macos',
    'windows'
  ];
  
  @override
  bool get isAvailable {
    // WebSockets are available everywhere
    return true;
  }
  
  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    if (!isAvailable) {
      throw TransportUnavailableException(name);
    }
    
    // Initialize WebSocket transport
    await WSNetworkFactory.instance.initialize(config);
  }
  
  @override
  Future<config.SessionResult> createSession(config.SessionConfig sessionConfig) async {
    if (!isAvailable) {
      throw TransportUnavailableException(name);
    }
    
    try {
      // Convert SessionConfig to WebSocket-specific parameters
      final networkSession = await WSNetworkFactory.instance.createNetwork(
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
          'transport_version': 'websocket_v1',
          'capabilities': sessionConfig.nodeMetadata,
          'websocket_available': isAvailable,
        },
      );
    } catch (e) {
      throw TransportException(name, 'Failed to create WebSocket session: $e', e);
    }
  }
  
  @override
  config.NetworkSession? getSession(String sessionId) {
    return WSNetworkFactory.instance.getNetworkSession(sessionId);
  }
  
  @override
  List<String> get activeSessionIds {
    return WSNetworkFactory.instance.activeSessionIds;
  }
  
  @override
  Future<void> dispose() async {
    await WSNetworkFactory.instance.dispose();
  }
}