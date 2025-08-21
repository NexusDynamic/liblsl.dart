/// LibLSL Coordinator with WebSocket Transport
///
/// This library provides coordination capabilities for web platforms using
/// WebSocket and WebRTC connections instead of LSL.
///
/// ## Features
/// - WebSocket-based coordination for web compatibility
/// - WebRTC data channels for peer-to-peer communication
/// - Automatic fallback to relay servers
/// - Cross-platform compatibility (web, mobile, desktop)
///
/// ## Usage
///
/// ```dart
/// import 'package:liblsl_coordinator/liblsl_coordinator_web.dart';
///
/// // Universal API (automatically uses WebSocket on web)
/// final result = await CoordinatorFactory.createSession(
///   sessionId: 'web_experiment_001',
///   nodeId: 'browser_client',
///   nodeName: 'Web Client',
///   topology: NetworkTopology.hierarchical,
/// );
///
/// // WebSocket-specific API for advanced configuration
/// final transportInfo = CoordinatorFactory.getTransportInfo();
/// print('Using transport: ${transportInfo['name']}'); // 'websocket'
///
/// // Create session with WebSocket-specific config
/// final config = SessionConfig(
///   sessionId: 'web_session',
///   nodeId: 'web_node_1',
///   nodeName: 'Web Node 1',
///   topology: NetworkTopology.peer2peer,
///   transportConfig: {
///     'websocket': {
///       'signaling_server': 'wss://signaling.example.com',
///       'stun_servers': ['stun:stun.l.google.com:19302'],
///     },
///   },
/// );
///
/// final result = await CoordinatorFactory.createSessionFromConfig(config);
/// ```
///
/// ## WebSocket-Specific Configuration
///
/// The WebSocket transport supports additional configuration options:
/// - `signaling_server`: WebSocket URL for peer discovery
/// - `stun_servers`: List of STUN servers for NAT traversal
/// - `turn_servers`: List of TURN servers for relay connections
/// - `ice_candidate_timeout`: Timeout for ICE candidate gathering
library;

// Export universal API
export 'liblsl_coordinator.dart';

// Export WebSocket-specific components
export '../src/transport/websocket/ws_factory_adapter.dart';
export '../src/transport/websocket/core/ws_network_factory.dart';
