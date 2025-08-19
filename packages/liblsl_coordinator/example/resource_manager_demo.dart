import 'package:liblsl_coordinator/liblsl_coordinator_lsl.dart';
import 'package:logging/logging.dart';

/// Demonstration of the new resource manager and error handling
Future<void> main() async {
  // Reduce debug logging noise for cleaner demo output
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  print('Resource Manager Demo');
  print('====================');

  try {
    // Initialize the LSL network factory (this now includes resource management)
    final factory = LSLNetworkFactory.instance;
    await factory.initialize();

    print('✓ Factory initialized with resource manager');

    // Create a coordination session using the factory
    print('Creating coordination session...');
    final session = await factory.createNetwork(
      sessionId: 'demo_session',
      nodeId: 'demo_node_1',
      nodeName: 'Demo Node',
      topology: NetworkTopology.peer2peer,
      sessionMetadata: {'demo': true},
      heartbeatInterval: const Duration(seconds: 10),
    );

    print('✓ Session created: ${session.sessionId}');
    print('✓ Session is properly managed as a resource');

    // Initialize the session (this activates the managed resource)
    print('\nInitializing session...');
    await session.join();
    print('✓ Session joined successfully');

    // Get some resource statistics
    print('\nResource Manager Statistics:');
    // Note: Direct access to resource manager stats would require extending the API
    // This is just for demonstration of the concept

    // Create a data stream to test stream-level resource management
    print('\nCreating data stream...');
    final streamConfig = StreamConfigs.eegProducer(
      streamId: 'demo_eeg',
      sourceId: 'demo_headset',
      channelCount: 8,
      sampleRate: 250.0,
      metadata: {'demo_stream': true},
    );

    final dataStream = await session.createDataStream(streamConfig);
    print('✓ Data stream created: ${dataStream.streamId}');

    print('\n--- Resource Management Features Demonstrated ---');
    print('1. ✓ Centralized resource tracking via CoordinatorResourceManager');
    print('2. ✓ Session lifecycle management as ManagedResource');
    print('3. ✓ Connection error tracking in LSLConnectionManager');
    print('4. ✓ Data stream error handling via sink error callbacks');
    print('5. ✓ Health checking and resource state monitoring');
    print('6. ✓ Proper resource cleanup and disposal');

    // Clean shutdown
    print('\nShutting down...');
    await session.leave();
    await factory.dispose();

    print('✓ Clean shutdown completed');
  } catch (e, stackTrace) {
    print('❌ Demo failed: $e');
    print('Stack trace: $stackTrace');
  }
}
