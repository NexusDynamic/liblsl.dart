/// Universal coordination example - works on all platforms
/// 
/// This example demonstrates the new CoordinatorFactory API that automatically
/// selects the best transport for the current platform:
/// - LSL transport on native platforms (Android, iOS, Desktop)
/// - WebSocket transport on web platforms
///
/// The exact same code works everywhere!
library;

import 'dart:async';
import 'package:logging/logging.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

void main() async {
  // Setup logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  print('🌐 Starting Universal Coordination Example');

  try {
    // Step 1: Show transport information
    await showTransportInfo();

    // Step 2: Create session using universal API
    final sessionResult = await createUniversalSession();

    // Step 3: Demonstrate session operations
    await demonstrateSessionOperations(sessionResult.session);

    // Step 4: Clean shutdown
    await cleanShutdown(sessionResult.session);

    print('✅ Universal coordination example completed successfully');
  } catch (e) {
    print('❌ Error during execution: $e');
    rethrow;
  }
}

/// Show information about the selected transport
Future<void> showTransportInfo() async {
  print('\n📋 Step 1: Transport Information');

  final transportInfo = CoordinatorFactory.getTransportInfo();
  print('✓ Transport: ${transportInfo['name']}');
  print('✓ Available: ${transportInfo['available']}');
  print('✓ Supported platforms: ${transportInfo['supported_platforms']}');
  print('✓ Active sessions: ${transportInfo['active_sessions']}');
}

/// Create a coordination session using the universal API
Future<SessionResult> createUniversalSession() async {
  print('\n🌐 Step 2: Creating Universal Session');

  // Method 1: Using convenience method
  final sessionResult = await CoordinatorFactory.createSession(
    sessionId: 'universal_demo_001',
    nodeId: 'demo_node_primary',
    nodeName: 'Demo Primary Node',
    topology: NetworkTopology.hierarchical,
    sessionMetadata: {
      'experiment_type': 'universal_demo',
      'version': '2.0.0',
      'supports_cross_platform': true,
    },
    nodeMetadata: {
      'device_type': 'demonstration_device',
      'capabilities': ['coordination', 'data_streaming'],
      'platform': _getCurrentPlatform(),
    },
    heartbeatInterval: const Duration(seconds: 5),
  );

  print('✓ Session created with ${sessionResult.transportUsed} transport');
  print('✓ Session ID: ${sessionResult.session.sessionId}');
  print('✓ Session state: ${sessionResult.session.state}');
  
  return sessionResult;
}

/// Demonstrate session operations that work on all platforms
Future<void> demonstrateSessionOperations(NetworkSession session) async {
  print('\n🔄 Step 3: Session Operations');

  // Join the network
  print('  Joining coordination network...');
  await session.join();
  print('  ✓ Joined network successfully');
  print('  ✓ Current role: ${session.role}');
  print('  ✓ Network topology: ${session.topology}');
  print('  ✓ Node count: ${session.nodes.length}');

  // Listen to session events
  final eventSubscription = session.events.listen((event) {
    print('  📨 Session Event: ${event.runtimeType}');
  });

  // Simulate waiting for other nodes (optional)
  print('  Simulating network activity...');
  await Future.delayed(const Duration(seconds: 2));

  // Note: Data streaming would be demonstrated here in a transport-specific way
  // For now, we keep the example focused on the coordination aspects

  eventSubscription.cancel();
}

/// Clean shutdown of the session
Future<void> cleanShutdown(NetworkSession session) async {
  print('\n🛑 Step 4: Clean Shutdown');

  // Leave the session
  print('  Leaving coordination network...');
  await session.leave();
  print('  ✓ Left network successfully');

  // Cleanup transport resources
  print('  Disposing transport resources...');
  await CoordinatorFactory.dispose();
  print('  ✓ Transport resources disposed');
}

/// Get a platform description (this would be different on each platform)
String _getCurrentPlatform() {
  // In a real app, you might use dart.library.* conditionals
  // For this demo, we'll detect based on available APIs
  try {
    // This will be true on native platforms with LSL
    final info = CoordinatorFactory.getTransportInfo();
    return info['name'] == 'lsl' ? 'native_with_lsl' : 'web_or_fallback';
  } catch (e) {
    return 'unknown';
  }
}

/// Alternative example using SessionConfig object
Future<void> alternativeConfigExample() async {
  print('\n🔧 Alternative: Using SessionConfig');

  // Method 2: Using SessionConfig for more control
  final config = SessionConfig(
    sessionId: 'advanced_demo_001',
    nodeId: 'demo_node_advanced',
    nodeName: 'Advanced Demo Node',
    topology: NetworkTopology.peer2peer,
    sessionMetadata: {
      'demo_type': 'advanced_configuration',
      'features': ['custom_config', 'transport_agnostic'],
    },
    nodeMetadata: {
      'node_capabilities': ['peer_communication', 'auto_discovery'],
      'priority_level': 'high',
    },
    transportConfig: {
      // Transport-specific configuration can be added here
      'timeout': 30000,
      'retry_attempts': 3,
    },
  );

  final sessionResult = await CoordinatorFactory.createSessionFromConfig(config);
  print('✓ Advanced session created: ${sessionResult.session.sessionId}');

  // Clean up
  await sessionResult.session.leave();
}

/// Utility configurations for common use cases
void showUtilityConfigurations() {
  print('\n🛠️ Utility Configurations:');

  // Hierarchical session
  final hierarchicalConfig = SessionConfigs.hierarchical(
    sessionId: 'hierarchy_demo',
    nodeId: 'leader_node',
    nodeName: 'Leader Node',
  );
  print('✓ Hierarchical config: ${hierarchicalConfig.topology}');

  // Peer-to-peer session
  final p2pConfig = SessionConfigs.peer2peer(
    sessionId: 'p2p_demo',
    nodeId: 'peer_node',
    nodeName: 'Peer Node',
  );
  print('✓ P2P config: ${p2pConfig.topology}');

  // Hybrid session
  final hybridConfig = SessionConfigs.hybrid(
    sessionId: 'hybrid_demo',
    nodeId: 'hybrid_node',
    nodeName: 'Hybrid Node',
  );
  print('✓ Hybrid config: ${hybridConfig.topology}');
}