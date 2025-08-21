import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../session/coordination_session.dart';
import '../../../session/data_stream.dart';
import '../../../session/stream_config.dart';
import '../../../session_config.dart';
import '../../../network/network_event.dart';
import 'coordinator_resource_manager.dart';
import '../config/lsl_channel_format.dart';
import '../connection/lsl_network_state.dart';
import '../protocol/lsl_coordination_protocol.dart';
import '../protocol/lsl_election_protocol.dart';
import '../../../utils/logging.dart';
import 'lsl_api_manager.dart';
import '../connection/lsl_connection_manager.dart';
import 'lsl_coordination_session.dart';
import '../config/lsl_stream_config.dart';
import 'lsl_data_stream.dart';

/// High-level factory for creating and managing LSL coordination networks
///
/// This provides the end-to-end workflow you described:
/// 1. Create a network, configure it, join
/// 2. Wait for a number of nodes
/// 3. Start a data stream
/// 4. Pause/resume
/// 5. Stop/destroy stream layer
class LSLNetworkFactory {
  static LSLNetworkFactory? _instance;
  static LSLNetworkFactory get instance => _instance ??= LSLNetworkFactory._();

  LSLNetworkFactory._();

  bool _isInitialized = false;
  final Map<String, LSLCoordinationSession> _activeSessions = {};
  CoordinatorResourceManager? _resourceManager;

  /// Initialize the LSL API and factory
  /// This must be called before any other operations
  Future<void> initialize({LSLApiConfig? config}) async {
    if (_isInitialized) {
      logger.warning('LSLNetworkFactory already initialized');
      return;
    }

    logger.info('Initializing LSL Network Factory');

    // Initialize LSL API - this must be done first
    await LSLApiManager.initialize(
      config ?? LSLApiManager.createDefaultConfig(),
    );

    // Initialize resource manager
    _resourceManager = CoordinatorResourceManager(
      managerId: 'lsl_network_factory',
    );
    await _resourceManager!.initialize();
    await _resourceManager!.start();

    _isInitialized = true;
    logger.info('LSL Network Factory initialized successfully');
  }

  /// Create a new coordination network session
  ///
  /// Returns a [LSLNetworkSession] that provides the complete end-to-end workflow
  Future<LSLNetworkSession> createNetwork({
    required String sessionId,
    required String nodeId,
    required String nodeName,
    required NetworkTopology topology,
    Map<String, dynamic> sessionMetadata = const {},
    Duration? heartbeatInterval,
  }) async {
    _ensureInitialized();

    if (_activeSessions.containsKey(sessionId)) {
      throw LSLNetworkException('Session $sessionId already exists');
    }

    logger.info(
      'Creating LSL coordination network: $sessionId (topology: $topology)',
    );

    // Create all the necessary components
    final connectionManager = LSLConnectionManager(
      managerId: sessionId,
      nodeId: nodeId,
    );
    final networkState = LSLNetworkState(
      nodeId: nodeId,
      nodeName: nodeName,
      sessionId: sessionId,
      coordinationPrefix: 'coord', // Default coordination prefix
      connectionManager: connectionManager,
    );
    // Create LSL-based protocol implementations
    final coordinationProtocol = LSLCoordinationProtocol(
      nodeId: nodeId,
      sessionId: sessionId,
      coordinationPrefix: 'coord', // Use same prefix as network state
    );
    final electionProtocol = LSLElectionProtocol(
      nodeId: nodeId,
      sessionId: sessionId,
    );

    // Create the coordination session
    final session = LSLCoordinationSession(
      sessionId: sessionId,
      nodeId: nodeId,
      nodeName: nodeName,
      expectedTopology: topology,
      sessionMetadata: sessionMetadata,
      connectionManager: connectionManager,
      networkState: networkState,
      coordinationProtocol: coordinationProtocol,
      electionProtocol: electionProtocol,
      heartbeatInterval: heartbeatInterval,
    );

    _activeSessions[sessionId] = session;

    // Add to resource management
    if (_resourceManager != null) {
      _resourceManager!.addConnectionManager(connectionManager);
      await _resourceManager!.addResource(session);
    }

    // Create and return the network session wrapper
    final networkSession = LSLNetworkSession._(session, this);

    logger.info('Created LSL coordination network: $sessionId');
    return networkSession;
  }

  /// Get an existing network session
  LSLNetworkSession? getNetworkSession(String sessionId) {
    final session = _activeSessions[sessionId];
    if (session == null) return null;
    return LSLNetworkSession._(session, this);
  }

  /// List all active network sessions
  List<String> get activeSessionIds => _activeSessions.keys.toList();

  /// Cleanup and shutdown the factory
  Future<void> dispose() async {
    logger.info('Disposing LSL Network Factory');

    // Stop all active sessions
    final futures = _activeSessions.values.map((session) async {
      try {
        logger.info('Leaving session ${session.sessionId}');
        await session.leave();
      } catch (e) {
        logger.warning('Error leaving session ${session.sessionId}: $e');
      }
    });

    await Future.wait(futures);
    _activeSessions.clear();

    // Cleanup resource manager
    if (_resourceManager != null) {
      await _resourceManager!.dispose();
      _resourceManager = null;
    }

    _isInitialized = false;
    logger.info('LSL Network Factory disposed');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw LSLNetworkException(
        'LSLNetworkFactory not initialized. Call initialize() first.',
      );
    }
  }

  Future<void> _removeSession(String sessionId) async {
    final session = _activeSessions.remove(sessionId);
    if (session != null && _resourceManager != null) {
      // Remove session and connection manager from resource management
      await _resourceManager!.removeResource(sessionId);
      await _resourceManager!.removeConnectionManager(sessionId);
    }
  }
}

/// High-level wrapper for a coordination network session
///
/// Provides the complete end-to-end workflow for LSL coordination networks
class LSLNetworkSession implements NetworkSession {
  final LSLCoordinationSession _session;
  final LSLNetworkFactory _factory;

  LSLNetworkSession._(this._session, this._factory);

  /// Session identifier
  @override
  String get sessionId => _session.sessionId;

  /// Current session state
  @override
  SessionState get state => _session.state;

  /// Current network topology
  @override
  NetworkTopology get topology => _session.topology;

  /// Current node role
  @override
  NodeRole get role => _session.role;

  /// List of nodes in the network
  @override
  List<NetworkNode> get nodes => _session.nodes;

  /// Stream of session events
  @override
  Stream<SessionEvent> get events => _session.events;

  /// Join the coordination network
  ///
  /// This handles the complete discovery and join flow:
  /// 1. Discover existing networks or create new one
  /// 2. Set up role-based connections
  /// 3. Start heartbeat and discovery
  @override
  Future<void> join() async {
    logger.info('Joining coordination network: $sessionId');
    await _session.join();
    logger.info('Successfully joined coordination network: $sessionId');
  }

  /// Wait for a specific number of nodes to join the network
  ///
  /// [targetCount] - Number of nodes to wait for (including this node)
  /// [timeout] - Optional timeout for waiting
  Future<void> waitForNodes(int targetCount, {Duration? timeout}) async {
    logger.info('Waiting for $targetCount nodes in network $sessionId');
    await _session.waitForNodes(targetCount, timeout: timeout);
    logger.info(
      'Target node count ($targetCount) reached in network $sessionId',
    );
  }

  /// Create and start a data stream
  ///
  /// Example configurations:
  /// ```dart
  /// // High-frequency EEG producer
  /// final eegConfig = LSLStreamConfig(
  ///   id: 'eeg_data',
  ///   maxSampleRate: 1000.0,
  ///   pollingFrequency: 1000.0,
  ///   channelCount: 64,
  ///   channelFormat: CoordinatorLSLChannelFormat.float32,
  ///   protocol: StreamProtocol.producer,
  ///   sourceId: 'eeg_headset_001',
  ///   pollingConfig: LSLPollingConfig.highFrequency(),
  /// );
  ///
  /// // Low-frequency consumer
  /// final consumerConfig = LSLStreamConfig(
  ///   id: 'data_consumer',
  ///   maxSampleRate: 100.0,
  ///   pollingFrequency: 100.0,
  ///   channelCount: 1,
  ///   channelFormat: CoordinatorLSLChannelFormat.float32,
  ///   protocol: StreamProtocol.consumer,
  ///   sourceId: 'analysis_node_001',
  ///   pollingConfig: LSLPollingConfig.testing(),
  /// );
  /// ```
  Future<ManagedDataStream> createDataStream(LSLStreamConfig config) async {
    logger.info('Creating data stream ${config.id} in network $sessionId');

    logger.info('Step 1: Creating LSLDataStream via session...');
    final dataStream = await _session.createDataStream(config) as LSLDataStream;
    logger.info('Step 1: LSLDataStream created successfully');

    // Initialize and start the stream
    logger.info('Step 2: Initializing data stream...');
    await dataStream.initialize();
    logger.info('Step 2: Data stream initialized');

    logger.info('Step 3: Starting data stream...');
    await dataStream.start();
    logger.info('Step 3: Data stream started');

    logger.info('Created and started data stream ${config.id}');
    return ManagedDataStream._(dataStream);
  }

  /// Get an existing data stream
  ManagedDataStream? getDataStream(String streamId) {
    final stream = _session.getDataStream(streamId);
    if (stream == null) return null;
    return ManagedDataStream._(stream as LSLDataStream);
  }

  /// Request all nodes in the network to create a specific data stream
  /// (Only available for coordinators - server or leader roles)
  Future<void> requestNetworkDataStream(LSLStreamConfig config) async {
    logger.info('Requesting network-wide data stream ${config.id}');
    await _session.requestNetworkDataStream(config);
  }

  /// Leave the coordination network and cleanup
  @override
  Future<void> leave() async {
    logger.info('Leaving coordination network: $sessionId');

    try {
      await _session.leave();
      await _factory._removeSession(sessionId);
      logger.info('Successfully left coordination network: $sessionId');
    } catch (e) {
      logger.severe('Error leaving network $sessionId: $e');
      rethrow;
    }
  }
}

/// High-level wrapper for managing data streams with pause/resume functionality
class ManagedDataStream {
  final LSLDataStream _stream;

  ManagedDataStream._(this._stream);

  /// Stream identifier
  String get streamId => _stream.streamId;

  /// Stream configuration
  LSLStreamConfig get config => _stream.config;

  /// Whether the stream is currently active
  bool get isActive => _stream.isActive;

  /// Stream of events for this data stream
  Stream<DataStreamEvent> get events => _stream.events;

  /// Producer side: get a sink for sending data
  ///
  /// Usage:
  /// ```dart
  /// final sink = stream.dataSink<List<double>>();
  /// if (sink != null) {
  ///   sink.add([1.0, 2.0, 3.0, 4.0]); // Send a sample
  /// }
  /// ```
  StreamSink<T>? dataSink<T>() => _stream.dataSink<T>();

  /// Consumer side: get a stream for receiving data
  ///
  /// Usage:
  /// ```dart
  /// final dataStream = stream.dataStream<List<double>>();
  /// if (dataStream != null) {
  ///   await for (final sample in dataStream) {
  ///     print('Received: $sample');
  ///   }
  /// }
  /// ```
  Stream<T>? dataStream<T>() => _stream.dataStream<T>();

  /// Pause the data stream
  ///
  /// Temporarily stops data processing while maintaining connections
  Future<void> pause() async {
    logger.info('Pausing data stream $streamId');
    await _stream.pause();
  }

  /// Resume the data stream
  ///
  /// Resumes data processing after being paused
  Future<void> resume() async {
    logger.info('Resuming data stream $streamId');
    await _stream.resume();
  }

  /// Stop the data stream
  ///
  /// Stops data processing and closes connections
  Future<void> stop() async {
    logger.info('Stopping data stream $streamId');
    await _stream.stop();
  }

  /// Permanently destroy the data stream
  ///
  /// Cleans up all resources - stream cannot be reused after this
  Future<void> destroy() async {
    logger.info('Destroying data stream $streamId');
    await _stream.dispose();
  }

  /// Wait for consumers to connect to this producer stream
  ///
  /// This is useful for ensuring data consumers are ready before starting production
  /// Usage:
  /// ```dart
  /// final producerStream = await session.createDataStream(producerConfig);
  /// await producerStream.waitForConsumer(timeout: 10.0);
  /// // Now safe to start sending data
  /// ```
  Future<bool> waitForConsumer({double timeout = 60.0}) async {
    logger.info('Waiting for consumers on data stream $streamId');
    return await _stream.waitForConsumer(timeout: timeout);
  }

  /// Check if consumers are currently connected to this producer stream
  ///
  /// Usage:
  /// ```dart
  /// if (await producerStream.hasConsumers()) {
  ///   // Send data knowing consumers are listening
  /// }
  /// ```
  Future<bool> hasConsumers() async {
    return await _stream.hasConsumers();
  }
}

/// Exception for network factory operations
class LSLNetworkException implements Exception {
  final String message;

  const LSLNetworkException(this.message);

  @override
  String toString() => 'LSLNetworkException: $message';
}

/// Utility class for creating common stream configurations
class StreamConfigs {
  /// High-frequency EEG producer configuration
  static LSLStreamConfig eegProducer({
    required String streamId,
    required String sourceId,
    int channelCount = 64,
    double sampleRate = 1000.0,
    Map<String, dynamic> metadata = const {},
  }) {
    return LSLStreamConfig(
      id: streamId,
      maxSampleRate: sampleRate,
      pollingFrequency: sampleRate,
      channelCount: channelCount,
      channelFormat: CoordinatorLSLChannelFormat.float32,
      protocol: const ProducerOnlyProtocol(),
      sourceId: sourceId,
      streamType: 'EEG',
      contentType: LSLContentType.eeg,
      metadata: metadata,
      pollingConfig: LSLPollingConfig.highFrequency(
        targetFrequency: sampleRate,
      ),
    );
  }

  /// General data consumer configuration
  static LSLStreamConfig dataConsumer({
    required String streamId,
    required String sourceId,
    int channelCount = 1,
    double sampleRate = 100.0,
    String streamType = 'data',
    Map<String, dynamic> metadata = const {},
  }) {
    return LSLStreamConfig(
      id: streamId,
      maxSampleRate: sampleRate,
      pollingFrequency: sampleRate,
      channelCount: channelCount,
      channelFormat: CoordinatorLSLChannelFormat.float32,
      protocol: const ConsumerOnlyProtocol(),
      sourceId: sourceId,
      streamType: streamType,
      metadata: metadata,
      pollingConfig: LSLPollingConfig.standard(), // More relaxed for consumers
    );
  }

  static LSLStreamConfig bidirectional({
    required String streamId,
    required String sourceId,
    int channelCount = 1,
    double sampleRate = 250.0,
    String streamType = 'data',
    Map<String, dynamic> metadata = const {},
  }) {
    return LSLStreamConfig(
      id: streamId,
      maxSampleRate: sampleRate,
      pollingFrequency: sampleRate,
      channelCount: channelCount,
      channelFormat: CoordinatorLSLChannelFormat.float32,
      protocol: const ProducerConsumerProtocol(),
      sourceId: sourceId,
      streamType: streamType,
      metadata: metadata,
      pollingConfig: LSLPollingConfig.standard(),
    );
  }

  /// Relay configuration (both producer and consumer)
  static LSLStreamConfig relay({
    required String streamId,
    required String sourceId,
    int channelCount = 1,
    double sampleRate = 500.0,
    String streamType = 'data',
    Map<String, dynamic> metadata = const {},
  }) {
    return LSLStreamConfig(
      id: streamId,
      maxSampleRate: sampleRate,
      pollingFrequency: sampleRate,
      channelCount: channelCount,
      channelFormat: CoordinatorLSLChannelFormat.float32,
      protocol: const RelayProtocol(),
      sourceId: sourceId,
      streamType: streamType,
      metadata: metadata,
      pollingConfig: LSLPollingConfig(
        targetIntervalMicroseconds: (1000000 / sampleRate).round(),
      ),
    );
  }
}
