/// LibLSL Coordinator with LSL Transport
///
/// This library provides the complete coordination system with LSL transport
/// for native platforms (Android, iOS, macOS, Windows, Linux).
///
/// ## Features
/// - High-performance LSL transport with isolate support
/// - Real-time data streaming with configurable polling
/// - Automatic network discovery and role assignment
/// - Resource lifecycle management
///
/// ## Usage
///
/// ```dart
/// import 'package:liblsl_coordinator/liblsl_coordinator_lsl.dart';
///
/// // Universal API (automatically uses LSL on native platforms)
/// final result = await CoordinatorFactory.createSession(
///   sessionId: 'experiment_001',
///   nodeId: 'device_primary',
///   nodeName: 'Primary Device',
///   topology: NetworkTopology.hierarchical,
/// );
///
/// // LSL-specific API for advanced configuration
/// await LSLNetworkFactory.instance.initialize();
/// final networkSession = await LSLNetworkFactory.instance.createNetwork(
///   sessionId: 'experiment_001',
///   nodeId: 'device_primary',
///   nodeName: 'Primary Device',
///   topology: NetworkTopology.hierarchical,
/// );
///
/// // Create high-frequency data streams
/// final eegStream = await networkSession.createDataStream(
///   StreamConfigs.eegProducer(
///     streamId: 'eeg_data',
///     sourceId: 'acti_champ_001',
///     channelCount: 64,
///     sampleRate: 1000.0,
///   ),
/// );
/// ```
library;

// Export universal API (hide conflicting NetworkSession to avoid ambiguity)
export 'liblsl_coordinator.dart';

// Export LSL-specific components
export '../src/transport/lsl/core/lsl_network_factory.dart';
export '../src/transport/lsl/core/lsl_api_manager.dart';
export '../src/transport/lsl/config/lsl_stream_config.dart';
export '../src/transport/lsl/config/lsl_channel_format.dart';
// export 'src/transport/lsl/lsl_factory_adapter.dart';

// Export LSL transport utilities
export '../src/transport/lsl/connection/lsl_connection_manager.dart';
export '../src/transport/lsl/connection/lsl_network_state.dart';
export '../src/transport/lsl/protocol/lsl_coordination_protocol.dart';
export '../src/transport/lsl/protocol/lsl_election_protocol.dart';
export '../src/transport/lsl/isolate/lsl_isolate_controller.dart';
