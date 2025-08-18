import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../session/data_stream.dart';
import '../../../session/stream_config.dart';
import '../../../management/resource_manager.dart';
import '../../../utils/logging.dart';
import '../config/lsl_stream_config.dart';
import '../connection/lsl_connection_manager.dart';
import '../isolate/lsl_isolate_controller.dart';
import '../isolate/lsl_polling_isolates.dart';

/// LSL implementation of DataStream with isolate integration
class LSLDataStream implements DataStream, ManagedResource {
  @override
  final String streamId;

  @override
  final LSLStreamConfig config;

  final LSLConnectionManager _connectionManager;
  final String _nodeId;

  // Isolate controllers for producer/consumer operations
  LSLIsolateController? _inletController;
  LSLIsolateController? _outletController;

  // Stream controllers for data flow
  final StreamController<LSLSample> _dataStreamController =
      StreamController<LSLSample>.broadcast();
  final StreamController<DataStreamEvent> _eventController =
      StreamController<DataStreamEvent>.broadcast();

  // Data sinks for producers
  StreamSink<LSLSample>? _dataSink;

  // State management
  ResourceState _resourceState = ResourceState.created;
  bool _isActive = false;
  bool _isPaused = false;

  // Stream resolution tracking
  final Map<int, LSLStreamInfo> _discoveredStreams = {};
  LSLStreamResolverContinuous? _streamResolver;
  Timer? _discoveryTimer;

  // Stream subscriptions for proper cleanup
  StreamSubscription<IsolateMessage>? _inletMessageSubscription;
  StreamSubscription<IsolateMessage>? _outletMessageSubscription;

  LSLDataStream({
    required this.streamId,
    required this.config,
    required LSLConnectionManager connectionManager,
    required String nodeId,
  }) : _connectionManager = connectionManager,
       _nodeId = nodeId;

  @override
  bool get isActive => _isActive;

  @override
  ResourceState get state => _resourceState;

  @override
  Map<String, dynamic> get metadata => {
    'streamId': streamId,
    'protocol': config.protocol.runtimeType.toString(),
    'sampleRate': config.maxSampleRate,
    'channelCount': config.channelCount,
    'nodeId': _nodeId,
  };

  @override
  Stream<DataStreamEvent> get events => _eventController.stream;

  @override
  Stream<ResourceStateEvent> get stateChanges {
    // For now, return empty stream - internal state changes are logged
    // External consumers should listen to the main events stream
    return const Stream.empty();
  }

  @override
  String get resourceId => streamId;

  // === LIFECYCLE METHODS ===

  @override
  Future<void> initialize() async {
    if (_resourceState != ResourceState.created) {
      throw DataStreamException('Stream $streamId is not in created state');
    }

    try {
      logger.info('Initializing LSL data stream $streamId (node: $_nodeId)');
      _updateState(ResourceState.initializing);

      // Setup stream resolver for discovery
      if (config.protocol.isConsumer || config.protocol.isRelay) {
        await _setupStreamDiscovery();
      }

      _updateState(ResourceState.idle);
      logger.info('LSL data stream $streamId initialized successfully');
    } catch (e) {
      _updateState(ResourceState.error);
      _eventController.add(
        DataStreamError(streamId, 'Initialization failed: $e', e),
      );
      rethrow;
    }
  }

  @override
  Future<void> activate() async {
    await start();
  }

  @override
  Future<void> deactivate() async {
    await stop();
  }

  @override
  Future<void> start() async {
    if (_isActive) return;

    try {
      logger.info('Starting LSL data stream $streamId');
      _updateState(ResourceState.active);

      // Start producer (outlet) if needed
      if (config.protocol.isProducer || config.protocol.isRelay) {
        await _startProducer();
      }

      // Start consumer (inlet) if needed
      if (config.protocol.isConsumer || config.protocol.isRelay) {
        await _startConsumer();
      }

      _isActive = true;
      _eventController.add(DataStreamStarted(streamId));
    } catch (e) {
      _updateState(ResourceState.error);
      _eventController.add(DataStreamError(streamId, 'Start failed: $e', e));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isActive) return;

    try {
      logger.info('Stopping LSL data stream $streamId');
      _updateState(ResourceState.stopping);

      // Stop isolate controllers
      await _inletController?.stop();

      // clear stream infos
      await _outletController?.stop();

      // Close data sink
      await _dataSink?.close();
      _dataSink = null;

      _isActive = false;
      _isPaused = false;
      _updateState(ResourceState.stopped);
      _eventController.add(DataStreamStopped(streamId));
    } catch (e) {
      _updateState(ResourceState.error);
      _eventController.add(DataStreamError(streamId, 'Stop failed: $e', e));
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await stop();

    try {
      logger.info('Disposing LSL data stream $streamId');
      _updateState(ResourceState.disposed);

      // Cancel discovery timer
      _discoveryTimer?.cancel();

      // Cancel stream subscriptions
      await _inletMessageSubscription?.cancel();
      await _outletMessageSubscription?.cancel();

      // Cleanup resolver
      _streamResolver?.destroy();

      // Close stream controllers
      await _dataStreamController.close();
      await _eventController.close();

      // Clear discovered streams
      _discoveredStreams.values.toList().destroy();
      _discoveredStreams.clear();
    } catch (e) {
      _eventController.add(DataStreamError(streamId, 'Dispose failed: $e', e));
      rethrow;
    }
  }

  @override
  Future<bool> healthCheck() async {
    return _isActive && _resourceState == ResourceState.active;
  }

  // === DATA STREAM INTERFACE ===

  @override
  StreamSink<T>? dataSink<T>() {
    if (!config.protocol.isProducer) return null;
    if (!_isActive) return null;

    // Create typed sink that converts to LSLSample
    return _DataStreamSink<T>(_sendData);
  }

  @override
  Stream<T>? dataStream<T>() {
    if (!config.protocol.isConsumer) return null;

    // Return typed stream that converts from LSLSample
    return _dataStreamController.stream.map((sample) => sample.data as T);
  }

  // === PAUSE/RESUME FUNCTIONALITY ===

  Future<void> pause() async {
    if (!_isActive || _isPaused) return;

    try {
      // Pause inlet controller
      if (_inletController != null) {
        await _inletController!.sendCommand(IsolateCommand.pause);
      }

      // Pause outlet controller
      if (_outletController != null) {
        await _outletController!.sendCommand(IsolateCommand.pause);
      }

      _isPaused = true;
      logger.info('LSL data stream $streamId paused');
    } catch (e) {
      _eventController.add(DataStreamError(streamId, 'Pause failed: $e', e));
      rethrow;
    }
  }

  Future<void> resume() async {
    if (!_isActive || !_isPaused) return;

    try {
      // Resume inlet controller
      if (_inletController != null) {
        await _inletController!.sendCommand(IsolateCommand.resume);
      }

      // Resume outlet controller
      if (_outletController != null) {
        await _outletController!.sendCommand(IsolateCommand.resume);
      }

      _isPaused = false;
      logger.info('LSL data stream $streamId resumed');
    } catch (e) {
      _eventController.add(DataStreamError(streamId, 'Resume failed: $e', e));
      rethrow;
    }
  }

  /// Wait for consumers to connect to this stream's outlets
  Future<bool> waitForConsumer({double timeout = 60.0}) async {
    if (_outletController == null) {
      logger.warning('No outlet controller available for stream $streamId');
      return false;
    }

    try {
      final responseCompleter = Completer<bool>();
      StreamSubscription<IsolateMessage>? subscription;

      // Listen for response
      subscription = _outletController!.messages.listen((message) {
        if (message.type == IsolateMessageType.response &&
            message.data['outletId'] == streamId) {
          subscription?.cancel();
          responseCompleter.complete(message.data['result'] as bool);
        }
      });

      // Send command
      await _outletController!.sendCommand(IsolateCommand.waitForConsumer, {
        'outletId': streamId,
        'timeout': timeout,
        'sendPort': _outletController!.responseSendPort,
      });

      // Wait for response with timeout
      return await responseCompleter.future.timeout(
        Duration(seconds: (timeout + 5).toInt()),
        onTimeout: () {
          subscription?.cancel();
          logger.warning(
            'Timeout waiting for consumer response on stream $streamId',
          );
          return false;
        },
      );
    } catch (e) {
      logger.warning('Error waiting for consumers on stream $streamId: $e');
      return false;
    }
  }

  /// Check if consumers are currently connected to this stream's outlets
  Future<bool> hasConsumers() async {
    if (_outletController == null) {
      logger.warning('No outlet controller available for stream $streamId');
      return false;
    }

    try {
      final responseCompleter = Completer<bool>();
      StreamSubscription<IsolateMessage>? subscription;

      // Listen for response
      subscription = _outletController!.messages.listen((message) {
        if (message.type == IsolateMessageType.response &&
            message.data['outletId'] == streamId) {
          subscription?.cancel();
          responseCompleter.complete(message.data['result'] as bool);
        }
      });

      // Send command
      await _outletController!.sendCommand(IsolateCommand.hasConsumers, {
        'outletId': streamId,
        'sendPort': _outletController!.responseSendPort,
      });

      // Wait for response with timeout
      return await responseCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          subscription?.cancel();
          logger.warning('Timeout checking consumers on stream $streamId');
          return false;
        },
      );
    } catch (e) {
      logger.warning('Error checking consumers on stream $streamId: $e');
      return false;
    }
  }

  // === PRIVATE IMPLEMENTATION ===

  Future<void> _setupStreamDiscovery() async {
    // Create resolver for discovering streams to consume
    final predicate = config.transportConfig.resolverConfig.dataPredicate(
      config.id,
      metadataFilters: {
        'nodeId': _nodeId, // Or other filtering criteria
      },
    );

    _streamResolver = _connectionManager.createContinuousResolver(
      predicate: predicate,
      resolverId: '${streamId}_resolver',
    );

    // Start periodic discovery
    _discoveryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isActive && !_isPaused) {
        await _discoverStreams();
      }
    });
  }

  Future<void> _discoverStreams() async {
    if (_streamResolver == null) return;

    try {
      final streams = await _streamResolver!.resolve();
      logger.finest('Discovered ${streams.length} streams for $streamId');

      // Process newly discovered streams
      _discoveredStreams.values.toList().destroy();
      _discoveredStreams.clear();
      for (final stream in streams) {
        final address =
            stream.streamInfo.address; // Use actual stream info address
        if (!_discoveredStreams.containsKey(address)) {
          _discoveredStreams[address] = stream;

          // Add to inlet controller if running
          if (_inletController != null) {
            await _inletController!.sendCommand(IsolateCommand.addInlets, {
              'streamAddresses': [address],
            });
          }
        }
      }
    } catch (e) {
      logger.warning('Stream discovery failed for $streamId: $e');
      _eventController.add(
        DataStreamError(streamId, 'Stream discovery failed: $e', e),
      );
    }
  }

  Future<void> _startProducer() async {
    if (_outletController != null) return; // Already started

    logger.info('DEBUG: Starting producer for stream $streamId');

    // Create outlet controller
    logger.info('DEBUG: Creating outlet controller');
    _outletController = LSLIsolateController(
      controllerId: '${streamId}_outlet',
      pollingConfig: config.pollingConfig,
    );

    // Listen for outlet events
    logger.info('DEBUG: Setting up outlet event listener');
    _outletMessageSubscription = _outletController!.messages.listen(
      _handleOutletMessage,
    );

    // Start outlet isolate
    logger.info('DEBUG: Creating isolate params');
    final params = LSLOutletIsolateParams(
      streamConfig: config,
      nodeId: _nodeId,
      // sendPort will be set by controller
    );

    logger.info(
      'DEBUG: Starting outlet isolate with lslOutletProducerIsolate function',
    );
    await _outletController!.start(lslOutletProducerIsolate, params);
    logger.info('DEBUG: Isolate started, waiting for ready signal');
    await _outletController!.ready;
    logger.info('DEBUG: Outlet controller ready');

    // Create the outlet in the isolate
    await _outletController!.sendCommand(IsolateCommand.addOutlet, {
      'outletId': streamId,
      'streamConfig': _configToMap(config),
    });

    // Setup data sink
    _dataSink = _DataStreamSink<LSLSample>(_sendToOutlet);
  }

  Future<void> _startConsumer() async {
    if (_inletController != null) return; // Already started

    logger.info('DEBUG: Starting consumer for stream $streamId');

    // Create inlet controller
    logger.info('DEBUG: Creating inlet controller');
    _inletController = LSLIsolateController(
      controllerId: '${streamId}_inlet',
      pollingConfig: config.pollingConfig,
    );

    // Listen for inlet data and events
    logger.info('DEBUG: Setting up inlet event listener');
    _inletMessageSubscription = _inletController!.messages.listen(
      _handleInletMessage,
    );

    // Start inlet isolate - use same pattern as outlet
    logger.info('DEBUG: Creating inlet isolate params');
    final params = LSLInletIsolateParams(
      nodeId: _nodeId,
      config: config.pollingConfig,
      sendPort: null, // Will be set by controller like outlet
      receiveOwnMessages: true, // Usually don't want to receive our own data
    );

    logger.info(
      'DEBUG: Starting inlet isolate with lslInletConsumerIsolate function',
    );
    await _inletController!.start(lslInletConsumerIsolate, params);
    logger.info('DEBUG: Isolate started, waiting for ready signal');
    await _inletController!.ready;
    logger.info('DEBUG: Inlet controller ready');

    // Add discovered streams to inlet controller
    if (_discoveredStreams.isNotEmpty) {
      await _inletController!.sendCommand(IsolateCommand.addInlets, {
        'streamAddresses': _discoveredStreams.keys.toList(),
      });
    }
  }

  void _handleInletMessage(IsolateMessage message) {
    switch (message.type) {
      case IsolateMessageType.data:
        // Received data from inlet
        final sample = message.data['sample'] as LSLSample;
        logger.finest(
          'DEBUG: Main thread received data sample from ${message.data['sourceId']}: ${sample.data.take(4).toList()}...',
        );
        if (!_isPaused) {
          _dataStreamController.add(sample);
        }
        break;

      case IsolateMessageType.metrics:
        // Handle performance metrics
        logger.finest('LSL data stream $streamId metrics: ${message.data}');
        break;

      case IsolateMessageType.error:
        _eventController.add(
          DataStreamError(
            streamId,
            message.data['error'] as String,
            message.data['cause'],
          ),
        );
        break;

      default:
        // Ignore other message types
        break;
    }
  }

  void _handleOutletMessage(IsolateMessage message) {
    switch (message.type) {
      case IsolateMessageType.error:
        _eventController.add(
          DataStreamError(
            streamId,
            message.data['error'] as String,
            message.data['cause'],
          ),
        );
        break;

      default:
        // Ignore other message types
        break;
    }
  }

  Future<void> _sendData(dynamic data) async {
    if (_isPaused) return;

    // Convert data to LSLSample if needed
    LSLSample sample;
    if (data is LSLSample) {
      sample = data;
    } else if (data is List) {
      sample = LSLSample(
        data,
        DateTime.now().microsecondsSinceEpoch.toDouble(),
        0,
      );
    } else {
      sample = LSLSample(
        [data],
        DateTime.now().microsecondsSinceEpoch.toDouble(),
        0,
      );
    }

    await _sendToOutlet(sample);
  }

  Future<void> _sendToOutlet(LSLSample sample) async {
    if (_outletController == null || _isPaused) return;

    try {
      await _outletController!.sendCommand(IsolateCommand.sendData, {
        'outletId': streamId,
        'samples': [sample],
      });
    } catch (e) {
      logger.warning('Send failed for LSL data stream $streamId: $e');
      _eventController.add(DataStreamError(streamId, 'Send failed: $e', e));
    }
  }

  void _updateState(ResourceState newState) {
    final oldState = _resourceState;
    _resourceState = newState;

    logger.fine(
      'LSL data stream $streamId state changed: $oldState -> $newState',
    );
  }

  /// Helper method to convert config to map
  Map<String, dynamic> _configToMap(LSLStreamConfig config) {
    return {
      'id': config.id,
      'maxSampleRate': config.maxSampleRate,
      'pollingFrequency': config.pollingFrequency,
      'channelCount': config.channelCount,
      'channelFormat': config.channelFormat.toString(),
      'protocol': _serializeProtocol(config.protocol),
      'metadata': config.metadata,
      'streamType': config.streamType,
      'sourceId': config.sourceId,
      'contentType': config.contentType.toString(),
      'pollingConfig': _serializePollingConfig(config.pollingConfig),
      'transportConfig': _serializeTransportConfig(config.transportConfig),
    };
  }

  /// Helper method to serialize protocol to map
  Map<String, dynamic> _serializeProtocol(StreamProtocol protocol) {
    return {'type': protocol.runtimeType.toString()};
  }

  /// Helper method to serialize polling config to map
  Map<String, dynamic> _serializePollingConfig(LSLPollingConfig config) {
    return {
      'useBusyWait': config.useBusyWait,
      'usePollingIsolate': config.usePollingIsolate,
      'useIsolatedInlets': config.useIsolatedInlets,
      'useIsolatedOutlets': config.useIsolatedOutlets,
      'targetIntervalMicroseconds': config.targetIntervalMicroseconds,
      'bufferSize': config.bufferSize,
      'pullTimeout': config.pullTimeout,
      'busyWaitThresholdMicroseconds': config.busyWaitThresholdMicroseconds,
    };
  }

  /// Helper method to serialize transport config to map
  Map<String, dynamic> _serializeTransportConfig(LSLTransportConfig config) {
    return {
      'maxOutletBuffer': config.maxOutletBuffer,
      'outletChunkSize': config.outletChunkSize,
      'maxInletBuffer': config.maxInletBuffer,
      'inletChunkSize': config.inletChunkSize,
      'enableRecovery': config.enableRecovery,
    };
  }
}

/// Custom StreamSink that converts data to LSLSample format
class _DataStreamSink<T> implements StreamSink<T> {
  final Future<void> Function(T) _sendFunction;
  bool _isClosed = false;

  _DataStreamSink(this._sendFunction);

  @override
  void add(T data) {
    if (_isClosed) throw StateError('StreamSink is closed');
    _sendFunction(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_isClosed) throw StateError('StreamSink is closed');
    // TODO: Handle errors properly
  }

  @override
  Future<void> addStream(Stream<T> stream) async {
    if (_isClosed) throw StateError('StreamSink is closed');
    await for (final data in stream) {
      await _sendFunction(data);
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  @override
  Future<void> get done => Future.value();
}

/// Exception for data stream operations
class DataStreamException implements Exception {
  final String message;

  const DataStreamException(this.message);

  @override
  String toString() => 'DataStreamException: $message';
}
