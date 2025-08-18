/// LibLSL Coordinator - Transport-agnostic coordination library
///
/// This library provides transport-agnostic coordination capabilities that
/// automatically select the best transport for the current platform:
/// - LSL transport on native platforms (Android, iOS, Desktop)
/// - WebSocket transport on web platforms
///
/// ## Basic Usage
/// 
/// ```dart
/// import 'package:liblsl_coordinator/liblsl_coordinator.dart';
/// 
/// // Create a session - transport is automatically selected
/// final result = await CoordinatorFactory.createSession(
///   sessionId: 'my_session',
///   nodeId: 'node_1',
///   nodeName: 'My Node',
///   topology: NetworkTopology.hierarchical,
/// );
/// 
/// final session = result.session;
/// await session.join();
/// ```
///
/// ## Platform-Specific Usage
///
/// For native platforms with LSL support:
/// ```dart
/// import 'package:liblsl_coordinator/liblsl_coordinator_lsl.dart';
/// ```
///
/// For web platforms:
/// ```dart
/// import 'package:liblsl_coordinator/liblsl_coordinator_web.dart';
/// ```
library;

// Export core factory and configuration
export 'src/coordinator_factory.dart';
export 'src/session_config.dart';

// Export core interfaces
export 'src/session/coordination_session.dart';
export 'src/session/data_stream.dart';
export 'src/session/stream_config.dart';

// Export utilities
export 'src/utils/logging.dart';
