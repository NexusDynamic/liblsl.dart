import 'dart:async';
//import 'dart:io';
import 'package:liblsl/lsl.dart';
import 'package:logging/logging.dart';

// Use the LSL-specific library for full LSL functionality
import 'package:liblsl_coordinator/liblsl_coordinator_lsl.dart';

/// Example demonstrating the complete end-to-end workflow for LSL coordination
///
/// This example uses the LSL-specific API for full control over LSL features.
/// For universal cross-platform examples, see universal_usage.dart
///
/// This showcases exactly what you requested:
/// 1. Create a network, configure it, join
/// 2. Wait for a specific number of nodes
/// 3. Start a data stream
/// 4. Pause/resume functionality
/// 5. Stop/destroy the stream layer
void main() async {
  // Setup logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  print('🚀 Starting LSL Coordination Example');

  try {
    // Step 1: Initialize the LSL Network Factory
    await initializeLSLFactory();

    // Step 2: Create and join a coordination network
    final networkSession = await createAndJoinNetwork();

    // Step 3: Wait for other nodes (optional - simulated here)
    await waitForNodes(networkSession);

    // Step 4: Create and start data streams
    final dataStreams = await createDataStreams(networkSession);

    // Step 5: Demonstrate pause/resume functionality
    await demonstratePauseResume(dataStreams);

    // Step 6: Simulate data flow
    await simulateDataFlow(dataStreams);

    // Step 7: Clean shutdown - stop and destroy streams
    await cleanShutdown(networkSession, dataStreams);

    print('✅ LSL Coordination Example completed successfully');
  } catch (e) {
    print('❌ Error during execution: $e');
    rethrow;
  }
  //exit(0);
}

/// Step 1: Initialize the LSL API and Network Factory
Future<void> initializeLSLFactory() async {
  print('\n📋 Step 1: Initializing LSL Network Factory');

  // Create LSL configuration
  final lslConfig = LSLApiManager.createDefaultConfig();

  // Initialize the factory - this MUST be done first
  await LSLNetworkFactory.instance.initialize(config: lslConfig);

  print('✓ LSL Network Factory initialized');
}

/// Step 2: Create a coordination network and join it
Future<NetworkSession> createAndJoinNetwork() async {
  print('\n🌐 Step 2: Creating and joining coordination network');

  // Create a new coordination network
  final networkSession = await LSLNetworkFactory.instance.createNetwork(
    sessionId: 'demo_session_001',
    nodeId: 'node_primary_001',
    nodeName: 'Demo Primary Node',
    topology: NetworkTopology.hierarchical, // or peer2peer, hybrid
    sessionMetadata: {
      'description': 'Demo coordination session',
      'version': '1.0.0',
      'experiment_id': 'demo_experiment',
    },
    heartbeatInterval: const Duration(seconds: 5),
  );

  // Join the network (handles discovery, role assignment, connections)
  await networkSession.join();

  print('✓ Network created and joined successfully');
  print('  - Session ID: ${networkSession.sessionId}');
  print('  - Topology: ${networkSession.topology}');
  print('  - Role: ${networkSession.role}');
  print('  - Current nodes: ${networkSession.nodes.length}');

  return networkSession;
}

/// Step 3: Wait for additional nodes to join (optional)
Future<void> waitForNodes(NetworkSession networkSession) async {
  print('\n⏳ Step 3: Waiting for additional nodes (optional)');

  final currentNodeCount = networkSession.nodes.length;
  print('  - Current node count: $currentNodeCount');

  // In a real scenario, you might wait for specific nodes:
  // await networkSession.waitForNodes(3, timeout: Duration(seconds: 30));

  // For this demo, we'll just simulate having the required nodes
  print('✓ Node requirements satisfied (simulated)');
}

/// Step 4: Create various types of data streams
Future<List<ManagedDataStream>> createDataStreams(
  NetworkSession networkSession,
) async {
  print('\n📊 Step 4: Creating data streams');

  final streams = <ManagedDataStream>[];

  // Create a high-frequency EEG producer stream
  print('  Creating EEG producer stream...');
  final eegConfig = StreamConfigs.eegProducer(
    streamId: 'eeg_primary',
    sourceId: 'eeg_device_001',
    channelCount: 32,
    sampleRate: 500.0, // 500 Hz
    metadata: {
      'device_type': 'ActiCHamp',
      'electrode_layout': 'standard_32',
      'impedance_check': 'passed',
    },
  );

  final eegStream = await networkSession.createDataStream(eegConfig);
  streams.add(eegStream);
  print('✓ EEG producer stream created and started');

  // Create a data consumer stream
  print('  Creating data consumer stream...');
  final consumerConfig = StreamConfigs.dataConsumer(
    streamId: 'analysis_consumer',
    sourceId: 'analysis_node_001',
    sampleRate: 100.0, // Lower frequency for analysis
    streamType: 'analysis',
    metadata: {'analysis_type': 'real_time_processing', 'buffer_size': '1000'},
  );

  final consumerStream = await networkSession.createDataStream(consumerConfig);
  streams.add(consumerStream);
  print('✓ Consumer stream created and started');

  // Create a relay stream (if needed)
  print('  Creating relay stream...');
  final relayConfig = StreamConfigs.relay(
    streamId: 'data_relay',
    sourceId: 'relay_node_001',
    sampleRate: 250.0,
    streamType: 'relay',
    metadata: {
      'relay_purpose': 'data_forwarding',
      'target_nodes': ['analysis_node_002', 'storage_node_001'],
    },
  );

  final relayStream = await networkSession.createDataStream(relayConfig);
  streams.add(relayStream);
  print('✓ Relay stream created and started');

  print('✓ All data streams created successfully');
  return streams;
}

/// Step 5: Demonstrate pause/resume functionality
Future<void> demonstratePauseResume(List<ManagedDataStream> streams) async {
  print('\n⏸️ Step 5: Demonstrating pause/resume functionality');

  // Pause all streams
  print('  Pausing all data streams...');
  for (final stream in streams) {
    await stream.pause();
    print('    ⏸️ Paused: ${stream.streamId}');
  }

  // Simulate some processing time while paused
  print('  📝 Performing maintenance while streams are paused...');
  await Future.delayed(const Duration(seconds: 2));

  // Resume all streams
  print('  Resuming all data streams...');
  for (final stream in streams) {
    await stream.resume();
    print('    ▶️ Resumed: ${stream.streamId}');
  }

  print('✓ Pause/resume functionality demonstrated');
}

/// Step 6: Simulate data flow for demonstration
Future<void> simulateDataFlow(List<ManagedDataStream> streams) async {
  print('\n🔄 Step 6: Simulating data flow');

  // Find producer and consumer streams
  final producers = streams.where((s) => s.config.protocol.isProducer).toList();
  final consumers = streams.where((s) => s.config.protocol.isConsumer).toList();

  print('  - Producers: ${producers.length}');
  print('  - Consumers: ${consumers.length}');

  // Set up data consumption listeners
  for (final consumer in consumers) {
    final dataStream = consumer.dataStream<List<double>>();
    if (dataStream != null) {
      print('  📡 Listening for data on: ${consumer.streamId}');

      // Listen for a few samples (non-blocking)
      dataStream
          .take(3)
          .listen(
            (sample) {
              print(
                '    📥 ${consumer.streamId} received: ${sample.take(4).toList()}...',
              );
            },
            onError: (error) {
              print('    ❌ Error on ${consumer.streamId}: $error');
            },
          );
    }
  }

  // Wait for producer streams to have consumers before sending data
  print('  ⏳ Waiting for consumers to connect...');
  for (final producer in producers) {
    final hasConsumers = await producer.waitForConsumer(timeout: 10.0);
    if (hasConsumers) {
      print('    ✓ ${producer.streamId} has consumers connected');
    } else {
      print('    ⚠️ ${producer.streamId} timeout waiting for consumers');
    }
  }

  // Simulate data production
  for (final producer in producers) {
    final dataSink = producer.dataSink<List<double>>();
    if (dataSink != null) {
      print('  📤 Sending sample data from: ${producer.streamId}');

      // Send a few sample data points
      for (int i = 0; i < 5; i++) {
        final sampleData = List.generate(
          producer.config.channelCount,
          (index) => (i * 10 + index).toDouble(),
        );

        dataSink.add(sampleData);
        print(
          '    📤 ${producer.streamId} sent sample $i: ${sampleData.take(4).toList()}...',
        );

        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  // Allow some time for data processing
  print('  ⏳ Allowing time for data processing...');
  await Future.delayed(const Duration(seconds: 2));

  print('✓ Data flow simulation completed');
}

/// Step 7: Clean shutdown - stop and destroy all resources
Future<void> cleanShutdown(
  NetworkSession networkSession,
  List<ManagedDataStream> streams,
) async {
  print('\n🛑 Step 7: Performing clean shutdown');

  // Stop all data streams first
  print('  Stopping all data streams...');
  for (final stream in streams) {
    await stream.stop();
    print('    🛑 Stopped: ${stream.streamId}');
  }

  // Destroy all data streams
  print('  Destroying all data streams...');
  for (final stream in streams) {
    await stream.destroy();
    print('    🗑️ Destroyed: ${stream.streamId}');
  }

  // Leave the coordination network
  print('  Leaving coordination network...');
  await networkSession.leave();
  print('    🚪 Left network: ${networkSession.sessionId}');

  // Shutdown the factory
  print('  Shutting down LSL Network Factory...');
  await LSLNetworkFactory.instance.dispose();
  print('    🔌 Factory shut down');

  print('✓ Clean shutdown completed');
}

/// Helper function to show current session state
void printSessionState(NetworkSession session) {
  print('📊 Session State:');
  print('  - Session ID: ${session.sessionId}');
  print('  - State: ${session.state}');
  print('  - Topology: ${session.topology}');
  print('  - Role: ${session.role}');
  print('  - Nodes: ${session.nodes.length}');
}

/// Example of handling session events (optional)
void listenToSessionEvents(NetworkSession session) {
  session.events.listen((event) {
    print('📨 Session Event: ${event.runtimeType}');
    // Handle specific event types as needed
  });
}

/// Example of creating custom stream configurations
LSLStreamConfig createCustomStreamConfig() {
  return LSLStreamConfig(
    id: 'custom_stream',
    maxSampleRate: 1000.0,
    pollingFrequency: 1000.0,
    channelCount: 16,
    channelFormat: CoordinatorLSLChannelFormat.float32,
    protocol: const ProducerOnlyProtocol(),
    sourceId: 'custom_device_001',
    streamType: 'custom_data',
    contentType: LSLContentType.eeg,
    metadata: {
      'custom_property': 'custom_value',
      'device_serial': '12345',
      'firmware_version': '2.1.0',
    },
    pollingConfig: LSLPollingConfig.highFrequency(
      targetFrequency: 1000.0,
      useBusyWait: true,
      bufferSize: 2000,
    ),
  );
}
