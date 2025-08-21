/// WebSocket transport implementation for conditional imports
/// 
/// This provides the standard function signature that the conditional import
/// system expects, using WebSocket transport for web compatibility.
library;

import 'dart:async';
import '../../session_config.dart' as config;
import 'ws_factory_adapter.dart';

/// Create a network session using WebSocket transport
/// 
/// This function signature matches the LSL equivalent, enabling
/// seamless conditional imports based on platform.
Future<config.SessionResult> createNetworkSession(config.SessionConfig sessionConfig) async {
  final factory = WebSocketTransportFactory.instance;
  
  // WebSocket transport is always available
  if (!factory.isAvailable) {
    throw UnsupportedError('WebSocket transport not available on this platform');
  }
  
  // Auto-initialize with default config if no transport config provided
  if (!sessionConfig.transportConfig.containsKey('websocket')) {
    await factory.initialize();
  } else {
    await factory.initialize(sessionConfig.transportConfig);
  }
  
  return await factory.createSession(sessionConfig);
}

/// Get transport information for WebSocket
Map<String, dynamic> getTransportInfo() {
  final factory = WebSocketTransportFactory.instance;
  return {
    'name': factory.name,
    'available': factory.isAvailable,
    'supported_platforms': factory.supportedPlatforms,
    'active_sessions': factory.activeSessionIds.length,
  };
}

/// Initialize WebSocket transport with specific configuration
Future<void> initializeTransport([Map<String, dynamic>? config]) async {
  await WebSocketTransportFactory.instance.initialize(config);
}

/// Dispose of WebSocket transport resources
Future<void> disposeTransport() async {
  await WebSocketTransportFactory.instance.dispose();
}