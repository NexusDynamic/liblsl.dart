import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../session/data_stream.dart';
import '../../../session/stream_config.dart';
import '../../../network/connection_manager.dart';
import '../../../utils/logging.dart';
import '../config/lsl_stream_config.dart';
import '../connection/lsl_connection_manager.dart';
import '../isolate/lsl_isolate_controller.dart';
import '../isolate/lsl_polling_isolates.dart';
import 'lsl_stream_manager.dart';

/// LSL implementation of DataStream with isolate integration
class LSLDataStream extends LSLStreamManager implements DataStream {
  @override
  final String streamId;

  final LSLConnectionManager _connectionManager;

  // Isolate controllers for producer/consumer operations
  LSLIsolateController? _inletController;
  LSLIsolateController? _outletController;

  // Stream controllers for data flow
  final StreamController<LSLSample> _dataStreamController =
      StreamController<LSLSample>.broadcast();
  final StreamController<DataStreamEvent> _dataEventController =
      StreamController<DataStreamEvent>.broadcast();

  // Data sinks for producers
  StreamSink<List<dynamic>>? _dataSink;

  // State management
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
    required super.config,
    required LSLConnectionManager connectionManager,
    required super.nodeId,
  }) : _connectionManager = connectionManager,
       super(resourceId: streamId);

  @override
  bool get isActive => _isActive;

  @override
  Map<String, dynamic> get metadata => {
    ...super.metadata,
    'streamId': streamId,
    'protocol': config.protocol.runtimeType.toString(),
    'sampleRate': config.maxSampleRate,
    'channelCount': config.channelCount,
  };

  /// DataStream events (filtered from base class stream events)
  @override
  Stream<DataStreamEvent> get events =>
      super.events
          .where((event) => event is DataStreamEvent)
          .cast<DataStreamEvent>();

  // === LIFECYCLE METHODS ===

  @override
  Future<void> onInitialize() async {
    try {
      logger.info('Initializing LSL data stream $streamId (node: $nodeId)');

      // Note: No automatic discovery setup - coordinator will direct connections
      // This makes the data stream coordinator-directed as per architecture

      logger.info(
        'LSL data stream $streamId initialized (waiting for coordinator direction)',
      );
    } catch (e) {
      emitEvent(DataStreamError(streamId, 'Initialization failed: $e', e));
      rethrow;
    }
  }

  @override
  Future<void> onActivate() async {
    await start();
  }

  @override
  Future<void> onDeactivate() async {
    await stop();
  }

  @override
  Future<void> start() async {
    if (_isActive) return;

    try {
      logger.info('Starting LSL data stream $streamId');

      // Start producer (outlet) if needed
      if (config.protocol.isProducer || config.protocol.isRelay) {
        await _startProducer();
      }

      // Start consumer (inlet) if needed
      if (config.protocol.isConsumer || config.protocol.isRelay) {
        await _startConsumer();
      }

      _isActive = true;
      emitEvent(DataStreamStarted(streamId));
    } catch (e) {
      emitEvent(DataStreamError(streamId, 'Start failed: $e', e));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isActive) return;

    try {
      logger.info('Stopping LSL data stream $streamId');

      // Stop isolate controllers
      await _inletController?.stop();
      await _outletController?.stop();

      // Close data sink
      await _dataSink?.close();
      _dataSink = null;

      _isActive = false;
      _isPaused = false;
      emitEvent(DataStreamStopped(streamId));
    } catch (e) {
      emitEvent(DataStreamError(streamId, 'Stop failed: $e', e));
      rethrow;
    }
  }

  @override
  Future<void> onDispose() async {
    await stop();

    try {
      logger.info('Disposing LSL data stream $streamId');

      // Cancel discovery timer
      _discoveryTimer?.cancel();

      // Cancel stream subscriptions
      await _inletMessageSubscription?.cancel();
      await _outletMessageSubscription?.cancel();

      // Cleanup resolver
      _streamResolver?.destroy();

      // Close stream controllers
      await _dataStreamController.close();
      await _dataEventController.close();

      // Clear discovered streams
      _discoveredStreams.values.toList().destroy();
      _discoveredStreams.clear();
    } catch (e) {
      // Don't add events during disposal as controller may be closed
      rethrow;
    }
  }

  @override
  Future<bool> healthCheck() async {
    // Use base class health check and add data stream specific checks
    final baseHealthy = await super.healthCheck();
    if (!baseHealthy) return false;

    return _isActive && resourceState == ResourceState.active;
  }

  // === DATA STREAM INTERFACE ===

  @override
  StreamSink<T>? dataSink<T>() {
    if (!config.protocol.isProducer) return null;
    if (!_isActive) return null;

    // Create typed sink that converts to LSLSample
    return _DataStreamSink<T>(_sendData, _handleSinkError);
  }

  @override
  Stream<T>? dataStream<T>() {
    if (!config.protocol.isConsumer) return null;

    // Return typed stream that converts from LSLSample
    return _dataStreamController.stream.map((sample) => sample.data as T);
  }

  // === COORDINATOR-DIRECTED CONNECTION METHODS ===

  /// Connect to a specific stream as directed by the coordinator
  /// This replaces self-managed discovery with coordinator direction
  Future<void> connectToStream(LSLStreamInfo streamInfo) async {
    if (!_isActive) {
      throw StateError(
        'Data stream must be active before connecting to streams',
      );
    }

    if (!config.protocol.isConsumer && !config.protocol.isRelay) {
      logger.warning(
        'Ignoring connect request - stream $streamId is not a consumer',
      );
      return;
    }

    try {
      logger.info(
        'Coordinator directing connection to stream: ${streamInfo.sourceId}',
      );

      // Store the stream info for inlet creation
      final address = streamInfo.streamInfo.address;
      _discoveredStreams[address] = streamInfo;

      // If inlet controller is running, add the stream immediately
      if (_inletController != null) {
        await _inletController!.sendCommand(IsolateCommand.addInlets, {
          'streamAddresses': [address],
        });
        logger.info(
          'Added inlet for coordinator-directed stream: ${streamInfo.sourceId}',
        );
      } else {
        logger.info(
          'Stored stream for later inlet creation: ${streamInfo.sourceId}',
        );
      }

      emitEvent(DataStreamConnected(streamId, streamInfo.sourceId));
    } catch (e) {
      logger.severe('Failed to connect to coordinator-directed stream: $e');
      emitEvent(DataStreamError(streamId, 'Connection failed: $e', e));
      rethrow;
    }
  }

  /// Disconnect from a specific stream as directed by the coordinator
  Future<void> disconnectFromStream(String streamAddress) async {
    try {
      logger.info(
        'Coordinator directing disconnection from stream address: $streamAddress',
      );

      // Remove from discovered streams
      final streamInfo = _discoveredStreams.remove(streamAddress);
      if (streamInfo != null) {
        streamInfo.destroy();
      }

      // If inlet controller is running, remove the stream
      if (_inletController != null) {
        await _inletController!.sendCommand(IsolateCommand.removeInlet, {
          'streamAddress': streamAddress,
        });
        logger.info(
          'Removed inlet for coordinator-directed disconnection: $streamAddress',
        );
      }

      emitEvent(DataStreamDisconnected(streamId, streamAddress));
    } catch (e) {
      logger.warning(
        'Failed to disconnect from coordinator-directed stream: $e',
      );
      emitEvent(DataStreamError(streamId, 'Disconnection failed: $e', e));
    }
  }

  /// Get current connection status for coordinator monitoring
  List<String> getConnectedStreams() {
    return _discoveredStreams.keys.map((k) => k.toString()).toList();
  }

  /// Check if connected to a specific stream
  bool isConnectedTo(String streamAddress) {
    // Convert string address to int for comparison if needed
    try {
      final addressKey = int.tryParse(streamAddress) ?? streamAddress;
      return _discoveredStreams.containsKey(addressKey) ||
          _discoveredStreams.keys.any((k) => k.toString() == streamAddress);
    } catch (e) {
      return _discoveredStreams.keys.any((k) => k.toString() == streamAddress);
    }
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
      emitEvent(DataStreamError(streamId, 'Pause failed: $e', e));
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
      emitEvent(DataStreamError(streamId, 'Resume failed: $e', e));
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
  // Note: _setupStreamDiscovery and _discoverStreams methods removed
  // Data streams are now coordinator-directed, not self-discovering

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
      config: config.pollingConfig,
      nodeId: nodeId,
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
    _dataSink = _DataStreamSink<List<dynamic>>(_sendToOutlet, _handleSinkError);
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
      nodeId: nodeId,
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

    // Add any coordinator-directed streams to inlet controller
    if (_discoveredStreams.isNotEmpty) {
      await _inletController!.sendCommand(IsolateCommand.addInlets, {
        'streamAddresses': _discoveredStreams.keys.toList(),
      });
      logger.info(
        'Added ${_discoveredStreams.length} coordinator-directed streams to inlet',
      );
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
        emitEvent(
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
        emitEvent(
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

  /// Handle errors from data sink
  void _handleSinkError(Object error, [StackTrace? stackTrace]) {
    logger.warning('Data sink error for stream $streamId: $error');
    emitEvent(DataStreamError(streamId, 'Sink error: $error', error));

    // Update resource state to error if it's a critical error
    if (resourceState == ResourceState.active) {
      updateResourceState(ResourceState.error, 'Data sink error: $error');
    }
  }

  Future<void> _sendData(dynamic data) async {
    if (_isPaused) return;

    await (data is List
        ? _sendToOutlet(data)
        : _sendToOutlet([data])); // Ensure we always send a list
  }

  Future<void> _sendToOutlet(List<dynamic> sample) async {
    if (_isPaused) return;

    try {
      if (_outletController != null) {
        // Send via isolate controller
        await _outletController!.sendCommand(IsolateCommand.sendData, {
          'outletId': streamId,
          'samples': [sample],
        });
      } else {
        // Send via direct outlet
        final outlet = getOutlet(streamId);
        if (outlet != null) {
          await outlet.pushSample(sample);
        }
      }
    } catch (e) {
      logger.warning('Send failed for LSL data stream $streamId: $e');
      emitEvent(DataStreamError(streamId, 'Send failed: $e', e));
    }
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
  final void Function(Object, StackTrace?) _errorFunction;
  bool _isClosed = false;

  _DataStreamSink(this._sendFunction, this._errorFunction);

  @override
  void add(T data) {
    if (_isClosed) throw StateError('StreamSink is closed');
    _sendFunction(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_isClosed) throw StateError('StreamSink is closed');
    _errorFunction(error, stackTrace);
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
