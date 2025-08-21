import 'package:logging/logging.dart';

void main() async {
  // Setup logging to see what's happening
  Logger.root.level = Level.ALL; // Set to Level.INFO for less verbosity
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  // This demonstrates how I want to have the config laid out,
  // this is a reference implementation, both a mix of classes and configsß
  final Map<String, dynamic> configBlueprint = {
    // === Required ===
    // Session (CoordinationSession())
    'session': {
      'sessionName':
          'liblsl_coordinator_example', // Human-readable name for the session, used to generate a reproducable ID
      'maxNodes':
          10, // Maximum number of nodes in the session - null for no limit,
      'minNodes':
          1, // Minimum number of nodes in the session (including this node, even if it is the "server")
    },
    // Node (NetworkNode().id)
    'deviceId':
        'example_device', // but we will use a UUID for uniqueness, this is for human readability
    // === Optional (with sane defaults, everything is configurable) ===
    // Tolpology()
    'topology': {
      // NetworkTopology()
      'type': {
        // NetworkTopologyType (enum)
        'hierarchical': {
          // .hierarchical (only one for now)
          'server': null, // NetworkNode or null
          'autoPromotion': {
            // AutoPromotion() or null
            // if no server is discovered, this node will become the server
            'promotionStrategy':
                'first', // 'first' or 'rng', FirstServe() or ShortStraw()
            'promotionDelay': 5, // Duration()
          },
        },
      },
    },
    'coordination': {
      // CoordinationConfig()
      'nodeDiscovery': {
        // DiscoveryConfig()
        'interval': 1, // Duration() in seconds
        'timeout': 5, // Duration() in seconds
      },
      'heartbeat': {
        'interval': 5, // Duration() in seconds, null for no heartbeat
      },
    },
    'transport': {
      // LSLTransport() or WSTransport() (later)
      'lsl': {
        // TransportConfig - LSLTransportConfig
        'lslApiConfig': null, // LSLApiConfig() or null (default)
        'coordination': {
          // StreamTransportConfig() -> LSLStreamTransportConfig() -> LSLCoordinationTransportConfig() (limited subclass)
          'coordinationFrequency': 100.0, // Sample rate in Hz
        },
      },
    },
  };

  // Create the session using the configuration blueprint (handles initialization and creation)
  final CoordinationSession session = await CoordinatorFactory.createSession( ... );

  final DataStream dataStream = await session.createDataStream(
    StreamConfigs.communication(
      name: 'game_inputs',
      channels: 5,
      dataType: 'float32',
      sampleRate: 250.0,
      producedBy: NodeRole | NodeType,
      consumedBy: NodeRole | NodeType,
    ),
    managed: true, // Managed by the session coordinator
    transportConfig?: null, // Optional transport config, null for default
  ); // handoff to transport-specific implementation

  final DataStream eegStream = await session.createDataStream(
    StreamConfigs.eegProducer(
      streamId: 'eeg_data',
      sourceId: 'acti_champ_001',
      channelCount: 64,
      sampleRate: 1000.0,
      producedBy: NodeRole | NodeType, // or something similar: have to define seperation between role in coordination and data strea participation
      consumedBy: NodeRole | NodeType,
    ),
    managed: true, // Managed by the session coordinator
  );

  session.coordination.listen((message) {
    // Handle incoming coordination messages
    print('Received coordination message: ${message.type} from ${message.fromNodeId}');
  });

  // Join the session (this will start the transport and begin discovery)
  await session.join();

  print('Joined session: ${session.sessionId} as node: ${session.nodeId}');

  // if we want to start sending data, we need to start the data streams
  // by design, for now, all clients would have to have a matching stream ID and configuration
  await dataStream.start(); // if we are the coordinator, this will send a coordination message to all nodes to start the stream with the given configuration

  await eegStream.start(); // same for EEG stream

  print('Data streams started: ${dataStream.streamId}, ${eegStream.streamId}');
  // We can now send data to the streams
  // For example, sending random data to the game inputs stream
  final random = Random();
  Timer.periodic(Duration(milliseconds: 100), (timer) {
    final data = List.generate(5, (_) => random.nextDouble() * 100);
    dataStream.sendData(data);
    print('Sent data to ${dataStream.streamId}: $data');
  });

  // We can also listen to the data streams
  dataStream.incoming.listen((data) {
    print('Received data from ${dataStream.streamId}: $data');
  });
  eegStream.incoming.listen((data) {
    print('Received EEG data from ${eegStream.streamId}: $data');
  });
  // We can also listen to the session events
  session.events.listen((event) {
    print('Session event: ${event.eventId} at ${event.timestamp}');
  });

  // we can pause the session to stop all data streams and transport (except coordination)
  await session.pause();
  print('Session paused');
  // We can resume the session to start all data streams and transport again
  await session.resume();
  print('Session resumed');
  // or individual streams
  await dataStream.pause();
  print('Data stream ${dataStream.streamId} paused');
  await dataStream.resume();
  print('Data stream ${dataStream.streamId} resumed');


}
