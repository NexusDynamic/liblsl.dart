import 'dart:async';

import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

extension LSLType on StreamDataType {
  /// Converts a [StreamDataType] to the corresponding LSL channel format.
  LSLChannelFormat toLSLChannelFormat() {
    switch (this) {
      case StreamDataType.int8:
        return LSLChannelFormat.int8;
      case StreamDataType.int16:
        return LSLChannelFormat.int16;
      case StreamDataType.int32:
        return LSLChannelFormat.int32;
      case StreamDataType.int64:
        return LSLChannelFormat.int64;
      case StreamDataType.float32:
        return LSLChannelFormat.float32;
      case StreamDataType.double64:
        return LSLChannelFormat.double64;
      case StreamDataType.string:
        return LSLChannelFormat.string;
    }
  }
}

/// Helper class with static methods for working with LSL StreamInfo
/// Especially a unified way of working with the metadata, or standardized
/// stream names for discovery.
class LSLStreamInfoHelper {
  static const String streamNameKey = 'stream_name';
  static const String sessionNameKey = 'session';
  static const String nodeIdKey = 'node_id';
  static const String nodeRoleKey = 'node_role';
  static const String nodeCapabilitiesKey = 'node_capabilities';
  static const String randomRollKey = 'random_roll';
  static const String nodeStartedAtKey = 'node_started_at';

  /// Generates a standardized stream name for a given stream configuration
  /// and node information.
  static String generateStreamName(
    NetworkStreamConfig config, {
    required Node node,
  }) {
    return '${config.name}-${node.id}-${node.getMetadata('role', defaultValue: 'none')}';
  }

  static Map<String, String> parseStreamName(String name) {
    final parts = name.split('-');
    if (parts.length < 3) {
      throw FormatException('Invalid stream name format: $name');
    }
    return {
      streamNameKey: parts.sublist(0, parts.length - 2).join('-'),
      nodeIdKey: parts[parts.length - 2],
      nodeRoleKey: parts[parts.length - 1],
    };
  }

  /// Create a stream info (for use in an outlet) from the given parameters.
  static Future<LSLStreamInfo> createStreamInfo({
    required NetworkStreamConfig config,
    required CoordinationSessionConfig sessionConfig,
    required Node node,
  }) async {
    final streamName = generateStreamName(config, node: node);

    final LSLStreamInfoWithMetadata info = await LSL.createStreamInfo(
      streamName: streamName,
      streamType: LSLContentType.markers,
      channelCount: config.channels,
      channelFormat: config.dataType.toLSLChannelFormat(),
      sampleRate: config.sampleRate,
    );

    // Add standard metadata
    final LSLDescription infoMetadata = info.description;
    final LSLXmlNode rootElement = infoMetadata.value;
    rootElement.addChildValue(sessionNameKey, sessionConfig.name);
    rootElement.addChildValue(nodeIdKey, node.id);
    rootElement.addChildValue(
      nodeRoleKey,
      node.getMetadata('role', defaultValue: 'none'),
    );
    rootElement.addChildValue(
      nodeCapabilitiesKey,
      (node.capabilities.join(',')),
    );

    // Add random roll if available
    final randomRoll = node.getMetadata('randomRoll');
    if (randomRoll != null) {
      rootElement.addChildValue(randomRollKey, randomRoll);
    }

    // Add node started time if available
    final nodeStartedAt = node.getMetadata('nodeStartedAt');
    if (nodeStartedAt != null) {
      rootElement.addChildValue(nodeStartedAtKey, nodeStartedAt);
    }

    return info;
  }

  /// Parses standard metadata from the given [LSLStreamInfoWithMetadata].
  static Map<String, String> parseMetadata(LSLStreamInfoWithMetadata info) {
    final Map<String, String> metadata = {};
    final LSLDescription description = info.description;
    final LSLXmlNode rootElement = description.value;
    for (final child in rootElement.children) {
      if (!child.isText()) continue;
      try {
        metadata[child.name] = child.textValue;
      } catch (e) {
        // ignore malformed metadata entries
        logger.warning('Failed to parse metadata entry ${child.name}: $e');
        continue;
      }
    }
    return metadata;
  }

  /// Generates an LSL stream resolver predicate based on the given parameters.
  /// Any parameter that is null is ignored in the predicate.
  /// For example, to find streams with a specific name prefix and session name:
  /// ```dart
  /// final predicate = LSLStreamInfoHelper.generatePredicate(
  ///   streamNamePrefix: 'mystream',
  ///   sessionName: 'mysession',
  /// );```
  /// This would generate a predicate like:
  /// "starts-with(name, 'mystream') and //info/desc/session='mysession'"
  ///
  /// For metadata filtering (promotion strategy):
  /// ```dart
  /// final predicate = LSLStreamInfoHelper.generatePredicate(
  ///   streamNamePrefix: 'coordination',
  ///   sessionName: 'mysession',
  ///   randomRollLessThan: myRandomRoll,
  /// );```
  ///
  /// which can be used with [LSLStreamResolverContinuousByPredicate].
  static String generatePredicate({
    String? streamNamePrefix,
    String? streamNameSuffix,
    String? sessionName,
    String? nodeId,
    String? nodeRole,
    String? nodeCapabilities,
    String? sourceIdPrefix,
    String? sourceIdSuffix,
    // Metadata filtering options for promotion strategy
    double? randomRollLessThan,
    double? randomRollGreaterThan,
    String? nodeStartedBefore,
    String? nodeStartedAfter,
  }) {
    final List<String> conditions = [];
    if (streamNamePrefix != null) {
      conditions.add("starts-with(name, '$streamNamePrefix')");
    }
    if (streamNameSuffix != null) {
      conditions.add("ends-with(name, '$streamNameSuffix')");
    }
    if (sourceIdPrefix != null) {
      conditions.add("starts-with(source_id, '$sourceIdPrefix')");
    }
    if (sourceIdSuffix != null) {
      conditions.add("ends-with(source_id, '$sourceIdSuffix')");
    }
    if (sessionName != null) {
      conditions.add("//info/desc/$sessionNameKey='$sessionName'");
    }
    if (nodeId != null) {
      conditions.add("//info/desc/$nodeIdKey='$nodeId'");
    }
    if (nodeRole != null) {
      conditions.add("//info/desc/$nodeRoleKey='$nodeRole'");
    }
    if (nodeCapabilities != null) {
      conditions.add("//info/desc/$nodeCapabilitiesKey='$nodeCapabilities'");
    }
    // Metadata filtering for promotion strategy
    if (randomRollLessThan != null) {
      conditions.add("//info/desc/$randomRollKey < $randomRollLessThan");
    }
    if (randomRollGreaterThan != null) {
      conditions.add("//info/desc/$randomRollKey > $randomRollGreaterThan");
    }
    if (nodeStartedBefore != null) {
      conditions.add("//info/desc/$nodeStartedAtKey < '$nodeStartedBefore'");
    }
    if (nodeStartedAfter != null) {
      conditions.add("//info/desc/$nodeStartedAtKey > '$nodeStartedAfter'");
    }

    if (conditions.isEmpty) {
      throw ArgumentError('At least one parameter must be provided');
    }
    return conditions.join(' and ');
  }

  /// f
}

/// Mixin providing shared LSL functionality for both coordination and data streams
mixin LSLStreamMixin<T extends NetworkStreamConfig, M extends IMessage>
    on NetworkStream<T, M> {
  /// The node associated with this stream
  Node get streamNode;

  /// Session configuration for metadata
  CoordinationSessionConfig get streamSessionConfig;

  /// LSL transport for creating managed resources
  LSLTransport get lslTransport;

  // LSL managed resources
  OutletResource? _outletResource;
  final List<InletResource> _inletResources = <InletResource>[];

  // Internal message handling
  final StreamController<M> _incomingController =
      StreamController<M>.broadcast();
  final StreamController<M> _outgoingController = StreamController<M>();

  Timer? _messagePollingTimer;
  Timer? _outboxProcessingTimer;

  // Resource management
  bool _created = false;
  bool _disposed = false;
  bool _started = false;
  IResourceManager? _manager;

  @override
  bool get created => _created;

  @override
  bool get disposed => _disposed;

  @override
  IResourceManager? get manager => _manager;

  bool get started => _started;

  @override
  Future<void> create() async {
    if (_created) return;
    if (_disposed) throw StateError('Cannot create disposed stream');

    // Create outlet for sending messages via transport
    final streamInfo = await LSLStreamInfoHelper.createStreamInfo(
      config: config,
      sessionConfig: streamSessionConfig,
      node: streamNode,
    );

    _outletResource = await lslTransport.createOutlet(streamInfo: streamInfo);
    _created = true;

    // Start processing outbox messages
    _startOutboxProcessing();
  }

  @override
  Future<void> updateManager(IResourceManager? newManager) async {
    if (_manager == newManager) return;
    _manager?.releaseResource(uId);
    _manager = newManager;
  }

  /// Adds an inlet for receiving messages from another node
  Future<void> addInlet(LSLStreamInfo streamInfo) async {
    if (!_created) throw StateError('Stream not created');

    final inletResource = await lslTransport.createInlet(
      streamInfo: streamInfo,
      includeMetadata: true,
    );
    _inletResources.add(inletResource);

    // Start message polling if not already started
    if (!_started) {
      await start();
    }
  }

  /// Starts internal message polling
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _startMessagePolling();
  }

  /// Stops message polling
  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    _messagePollingTimer?.cancel();
    _outboxProcessingTimer?.cancel();
  }

  void _startMessagePolling() {
    _messagePollingTimer?.cancel();
    _messagePollingTimer = Timer.periodic(
      Duration(milliseconds: 10), // High frequency polling
      (timer) async {
        if (!_started || paused || _inletResources.isEmpty) return;

        for (final inletResource in _inletResources) {
          try {
            final sample = await inletResource.inlet.pullSample(timeout: 0.0);
            if (sample.isNotEmpty) {
              final message = _createMessageFromSample(sample);
              if (message != null) {
                _incomingController.add(message);
              }
            }
          } catch (e) {
            // Handle errors gracefully - inlet might be disposed
          }
        }
      },
    );
  }

  void _startOutboxProcessing() {
    _outboxProcessingTimer?.cancel();
    _outgoingController.stream.listen((message) {
      if (_outletResource != null && _started && !paused) {
        try {
          final sampleData = _createSampleFromMessage(message);
          _outletResource!.outlet.pushSample(sampleData);
        } catch (e) {
          logger.warning('Failed to send message: $e');
        }
      }
    });
  }

  /// Override this method to convert LSL sample to message type
  M? _createMessageFromSample(LSLSample sample) {
    // Default implementation - subclasses should override
    return null;
  }

  /// Override this method to convert message to LSL sample data
  List<dynamic> _createSampleFromMessage(M message) {
    // Default implementation - subclasses should override
    return [message.toString()];
  }

  @override
  Future<void> sendMessage(M message) async {
    if (!_started) throw StateError('Stream not started');
    _outgoingController.add(message);
  }

  @override
  Stream<M> get inbox => _incomingController.stream;

  @override
  StreamSink<M> get outbox => _outgoingController.sink;

  @override
  Future<void> pause() async {
    if (paused) return;
    _messagePollingTimer?.cancel();
    super.pause();
  }

  @override
  Future<void> resume() async {
    if (!paused) return;
    _startMessagePolling();
    super.resume();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    await stop();

    // Dispose managed resources - they will handle their own cleanup
    _outletResource?.dispose();
    for (final inletResource in _inletResources) {
      inletResource.dispose();
    }
    _inletResources.clear();

    await _incomingController.close();
    await _outgoingController.close();

    _disposed = true;
    try {
      await _manager?.releaseResource(uId);
    } catch (e) {
      logger.warning('Failed to release resource $uId: $e');
    }
  }
}

/// LSL-based data stream implementation
// ignore: missing_override_of_must_be_overridden
class LSLDataStream extends DataStream<DataStreamConfig, IMessage>
    with RuntimeTypeUID, LSLStreamMixin<DataStreamConfig, IMessage> {
  @override
  final Node streamNode;
  @override
  final CoordinationSessionConfig streamSessionConfig;
  @override
  final LSLTransport lslTransport;

  // Additional data stream specific functionality
  final StreamController<List<double>> _dataController =
      StreamController<List<double>>.broadcast();

  Stream<List<double>> get incoming => _dataController.stream;

  LSLDataStream({
    required DataStreamConfig config,
    required this.streamNode,
    required this.streamSessionConfig,
    required this.lslTransport,
  }) : super(config);

  @override
  String get name => 'LSL Data Stream ${config.name}';

  @override
  String get description => 'LSL data stream for ${config.name}';

  /// Sends numerical data directly (for high-frequency data streams)
  void sendData(List<double> data) {
    if (!started) return;

    if (data.length != config.channels) {
      throw ArgumentError(
        'Data length ${data.length} does not match channels ${config.channels}',
      );
    }

    // Send via LSL outlet directly for performance
    if (_outletResource != null) {
      _outletResource!.outlet.pushSample(data);
    }
  }

  @override
  IMessage? _createMessageFromSample(LSLSample sample) {
    // For data streams, we emit both raw data and message
    final data = sample.data as List<double>;
    if (data.isNotEmpty) {
      // Emit to data stream
      _dataController.add(data);
    }

    // For now, data streams don't use message-based communication
    // This could be extended later for control messages
    return null;
  }

  @override
  List<dynamic> _createSampleFromMessage(IMessage message) {
    // For data streams, messages are rare - mostly used for control
    // Actual data goes through sendData() method for performance
    if (message is StringMessage) {
      return [message.data];
    }
    return [message.toString()];
  }

  @override
  Future<void> dispose() async {
    await _dataController.close();
    await super.dispose();
  }
}

/// Factory for creating LSL-based network streams.
class LSLNetworkStreamFactory
    extends NetworkStreamFactory<LSLCoordinationSession> {
  @override
  Future<LSLDataStream> createDataStream(
    DataStreamConfig config,
    LSLCoordinationSession session,
  ) async {
    return LSLDataStream(
      config: config,
      streamNode: session.thisNode,
      streamSessionConfig: session.config,
      lslTransport: session.transport,
    );
  }

  @override
  Future<LSLCoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config,
    LSLCoordinationSession session,
  ) async {
    return LSLCoordinationStream(
      config: config,
      streamNode: session.thisNode,
      streamSessionConfig: session.config,
      lslTransport: session.transport,
    );
  }
}

/// LSL-based coordination stream with internal message polling
// ignore: missing_override_of_must_be_overridden
class LSLCoordinationStream
    extends CoordinationStream<CoordinationStreamConfig, StringMessage>
    with
        RuntimeTypeUID,
        LSLStreamMixin<CoordinationStreamConfig, StringMessage> {
  @override
  final Node streamNode;
  @override
  final CoordinationSessionConfig streamSessionConfig;
  @override
  final LSLTransport lslTransport;

  LSLCoordinationStream({
    required CoordinationStreamConfig config,
    required this.streamNode,
    required this.streamSessionConfig,
    required this.lslTransport,
  }) : super(config);

  @override
  String get description => 'LSL coordination stream for ${config.name}';

  @override
  StringMessage? _createMessageFromSample(LSLSample sample) {
    final messageJson = sample.data[0] as String;
    final timestamp =
        sample.timestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(
              (sample.timestamp * 1000).round(),
            )
            : DateTime.now();

    return MessageFactory.stringMessage(
      data: [messageJson],
      timestamp: timestamp,
      channels: 1,
    );
  }

  @override
  List<dynamic> _createSampleFromMessage(StringMessage message) {
    return [message.data];
  }

  // The LSLStreamMixin provides inbox, outbox, and sendMessage implementations
  // But the compiler may need explicit confirmation for @mustBeOverridden methods
}
