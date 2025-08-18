/// Main coordinator factory with conditional transport selection
/// 
/// This factory automatically chooses the best available transport for the
/// current platform: LSL on native platforms, WebSocket on web.
library;

import 'dart:async';
import 'session_config.dart';
import 'session/coordination_session.dart';

// Conditional imports - only one will compile per platform
import 'transport/lsl/create_network_session.dart'
    if (dart.library.js) 'transport/websocket/create_network_session.dart'
    as transport_impl;

/// Main entry point for creating coordination sessions
/// 
/// This factory automatically selects the appropriate transport based on
/// the target platform:
/// - Native platforms (Android, iOS, Desktop): Uses LSL transport
/// - Web platform: Uses WebSocket transport
class CoordinatorFactory {
  /// Create a coordination session using the platform's default transport
  /// 
  /// This method provides a unified API for creating sessions regardless of
  /// the underlying transport mechanism.
  static Future<SessionResult> createSession({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    required NetworkTopology topology,
    Map<String, dynamic>? sessionMetadata,
    Map<String, dynamic>? nodeMetadata,
    Duration? heartbeatInterval,
    Map<String, dynamic>? transportConfig,
  }) async {
    final config = SessionConfig(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      topology: topology,
      sessionMetadata: sessionMetadata ?? {},
      nodeMetadata: nodeMetadata ?? {},
      heartbeatInterval: heartbeatInterval ?? const Duration(seconds: 5),
      transportConfig: transportConfig ?? {},
    );

    return await transport_impl.createNetworkSession(config);
  }

  /// Create a coordination session from a SessionConfig object
  static Future<SessionResult> createSessionFromConfig(SessionConfig config) async {
    return await transport_impl.createNetworkSession(config);
  }

  /// Get information about the current transport
  /// 
  /// Returns details about which transport is being used and its capabilities
  static Map<String, dynamic> getTransportInfo() {
    return transport_impl.getTransportInfo();
  }

  /// Initialize the transport layer with specific configuration
  /// 
  /// This is optional - the transport will auto-initialize on first use
  static Future<void> initializeTransport([Map<String, dynamic>? config]) async {
    await transport_impl.initializeTransport(config);
  }

  /// Cleanup transport resources
  /// 
  /// Call this when shutting down your application
  static Future<void> dispose() async {
    await transport_impl.disposeTransport();
  }
}

/// Utility class for creating common session configurations
class SessionConfigs {
  /// Create a hierarchical session configuration
  /// 
  /// In this topology, one node acts as a server/leader and others as clients
  static SessionConfig hierarchical({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    Map<String, dynamic>? sessionMetadata,
    Map<String, dynamic>? nodeMetadata,
    Duration? heartbeatInterval,
  }) {
    return SessionConfig(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      topology: NetworkTopology.hierarchical,
      sessionMetadata: sessionMetadata ?? {},
      nodeMetadata: nodeMetadata ?? {},
      heartbeatInterval: heartbeatInterval ?? const Duration(seconds: 5),
    );
  }

  /// Create a peer-to-peer session configuration
  /// 
  /// In this topology, all nodes are equal and communicate directly
  static SessionConfig peer2peer({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    Map<String, dynamic>? sessionMetadata,
    Map<String, dynamic>? nodeMetadata,
    Duration? heartbeatInterval,
  }) {
    return SessionConfig(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      topology: NetworkTopology.peer2peer,
      sessionMetadata: sessionMetadata ?? {},
      nodeMetadata: nodeMetadata ?? {},
      heartbeatInterval: heartbeatInterval ?? const Duration(seconds: 5),
    );
  }

  /// Create a hybrid session configuration
  /// 
  /// This topology can switch between hierarchical and P2P as needed
  static SessionConfig hybrid({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    Map<String, dynamic>? sessionMetadata,
    Map<String, dynamic>? nodeMetadata,
    Duration? heartbeatInterval,
  }) {
    return SessionConfig(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      topology: NetworkTopology.hybrid,
      sessionMetadata: sessionMetadata ?? {},
      nodeMetadata: nodeMetadata ?? {},
      heartbeatInterval: heartbeatInterval ?? const Duration(seconds: 5),
    );
  }
}