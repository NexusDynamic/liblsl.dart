// lib/transports/lsl/isolate/isolate_manager.dart

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:collection/collection.dart';
import 'package:liblsl/lsl.dart';

import 'package:liblsl_coordinator/framework.dart';
import 'package:synchronized/synchronized.dart';

/// Enum defining all possible isolate message types
enum IsolateMessageType {
  start,
  initialized,
  requestResponse,
  stop,
  addInlet,
  removeInlet,
  data,
  recreateOutlet,
}

/// Base class for all isolate messages - immutable for efficient message passing
abstract class IsolateMessage {
  final IsolateMessageType type;
  final String? requestID;

  const IsolateMessage(this.type, {this.requestID});
}

/// Message to start isolate processing - immutable
class StartMessage extends IsolateMessage {
  const StartMessage({super.requestID}) : super(IsolateMessageType.start);
}

/// Message to stop isolate processing - immutable
class StopMessage extends IsolateMessage {
  const StopMessage({super.requestID}) : super(IsolateMessageType.stop);
}

/// Message to add an inlet to running isolate - immutable
class AddInletMessage extends IsolateMessage {
  final int address;

  const AddInletMessage(this.address, {super.requestID})
    : super(IsolateMessageType.addInlet);
}

/// Message to remove an inlet from running isolate - immutable
class RemoveInletMessage extends IsolateMessage {
  final int address;

  const RemoveInletMessage(this.address, {super.requestID})
    : super(IsolateMessageType.removeInlet);
}

/// Message to send data through outlet - immutable
class DataMessage extends IsolateMessage {
  final List<dynamic> payload;

  const DataMessage(this.payload, {super.requestID})
    : super(IsolateMessageType.data);
}

/// Message to recreate outlet - immutable
class RecreateOutletMessage extends IsolateMessage {
  final int address; // stream info address
  const RecreateOutletMessage(this.address, {super.requestID})
    : super(IsolateMessageType.recreateOutlet);
}

/// Message to notify main thread that the isolate is initialized
class InitializedMessage extends IsolateMessage {
  const InitializedMessage({super.requestID})
    : super(IsolateMessageType.initialized);
}

class ResponseMessage extends IsolateMessage {
  const ResponseMessage({required super.requestID})
    : super(IsolateMessageType.requestResponse);
}

/// Configuration for isolate workers
class IsolateWorkerConfig {
  final String streamId;
  final StreamDataType dataType;
  final int channelCount;
  final double sampleRate;
  final bool useBusyWaitInlets;
  final bool useBusyWaitOutlets;
  final Duration pollingInterval;
  final SendPort mainSendPort;
  final String? debugName;

  // For outlets
  final int? outletAddress;

  // For inlets
  final List<int>? inletAddresses;

  IsolateWorkerConfig({
    required this.streamId,
    required this.dataType,
    required this.channelCount,
    required this.sampleRate,
    required this.useBusyWaitInlets,
    required this.useBusyWaitOutlets,
    required this.pollingInterval,
    required this.mainSendPort,
    this.outletAddress,
    this.inletAddresses,
    this.debugName,
  });

  IsolateWorkerConfig copyWith({
    String? streamId,
    StreamDataType? dataType,
    int? channelCount,
    double? sampleRate,
    bool? useBusyWaitInlets,
    bool? useBusyWaitOutlets,
    Duration? pollingInterval,
    SendPort? mainSendPort,
    int? outletAddress,
    List<int>? inletAddresses,
    String? debugName,
  }) {
    return IsolateWorkerConfig(
      streamId: streamId ?? this.streamId,
      dataType: dataType ?? this.dataType,
      channelCount: channelCount ?? this.channelCount,
      sampleRate: sampleRate ?? this.sampleRate,
      useBusyWaitInlets: useBusyWaitInlets ?? this.useBusyWaitInlets,
      useBusyWaitOutlets: useBusyWaitOutlets ?? this.useBusyWaitOutlets,
      pollingInterval: pollingInterval ?? this.pollingInterval,
      mainSendPort: mainSendPort ?? this.mainSendPort,
      outletAddress: outletAddress ?? this.outletAddress,
      inletAddresses: inletAddresses ?? this.inletAddresses,
      debugName: debugName ?? this.debugName,
    );
  }
}

/// Message sent from isolate to main
class IsolateDataMessage {
  final String streamId;
  final String messageId;
  final DateTime timestamp;
  final List<dynamic> data;
  final String? sourceId;
  final double? lslTimestamp;
  final double? lslTimeCorrection;

  IsolateDataMessage({
    required this.streamId,
    required this.messageId,
    required this.timestamp,
    required this.data,
    this.sourceId,
    this.lslTimestamp,
    this.lslTimeCorrection,
  });

  Map<String, dynamic> toMap() => {
    'streamId': streamId,
    'messageId': messageId,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
    'sourceId': sourceId,
    'lslTimestamp': lslTimestamp,
    'lslTimeCorrection': lslTimeCorrection,
  };

  factory IsolateDataMessage.fromMap(Map<String, dynamic> map) {
    return IsolateDataMessage(
      streamId: map['streamId'] as String,
      messageId: map['messageId'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      data: map['data'] as List<dynamic>,
      sourceId: map['sourceId'] as String?,
      lslTimestamp: map['lslTimestamp'] as double?,
      lslTimeCorrection: map['lslTimeCorrection'] as double?,
    );
  }
}

/// Base class for stream isolates with shared functionality
abstract class StreamIsolate {
  final String streamId;
  final StreamDataType dataType;
  final bool useBusyWaitInlets;
  final bool useBusyWaitOutlets;
  final Duration pollingInterval;
  final String isolateDebugName;

  // Communication ports - managed by this instance
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Isolate? _isolate;

  // Ready completer for synchronization
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _initialized = Completer<void>();
  final Map<String, Completer<void>> _responseCompleters = {};

  // Data stream for incoming messages
  final StreamController<IsolateDataMessage> _incomingDataController =
      StreamController<IsolateDataMessage>();

  Stream<IsolateDataMessage> get incomingData => _incomingDataController.stream;

  StreamIsolate({
    required this.streamId,
    required this.dataType,
    required this.useBusyWaitInlets,
    required this.useBusyWaitOutlets,
    required this.pollingInterval,
    String? isolateDebugName,
  }) : isolateDebugName = isolateDebugName ?? 'StreamIsolate-$streamId';

  /// Create and start the isolate
  Future<void> create() async {
    if (_isolate != null) return; // Already created

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage);

    final config = _createConfig();
    _isolate = await Isolate.spawn(
      _getWorkerFunction(),
      config,
      debugName: isolateDebugName,
    );
    await _initialized.future;
  }

  /// Send a message to the isolate - now sends objects directly!
  Future<void> sendMessage(IsolateMessage message) async {
    await _initialized.future;
    _sendPort?.send(message); // Direct object sending - no serialization!
  }

  /// Generate a requestID and completer.
  (String, Completer<void>) _generateRequestID() {
    final requestID = generateUid();
    final completer = Completer<void>();
    _responseCompleters[requestID] = completer;
    return (requestID, completer);
  }

  /// Start isolate processing
  Future<void> start() async {
    final requestRecord = _generateRequestID();
    logger.finest(
      '[$isolateDebugName] Starting isolate for stream $streamId with request ID ${requestRecord.$1}',
    );
    await sendMessage(StartMessage(requestID: requestRecord.$1));
    await requestRecord.$2.future;
  }

  /// Stop isolate processing
  Future<void> stop() async {
    final requestRecord = _generateRequestID();
    logger.finest(
      '[$isolateDebugName] Stopping isolate for stream $streamId with request ID ${requestRecord.$1}',
    );
    await sendMessage(StopMessage(requestID: requestRecord.$1));
    await requestRecord.$2.future;
  }

  /// Clean up resources
  Future<void> dispose() async {
    stop();

    // Give isolate time to process stop message
    await Future.delayed(Duration(seconds: 1));

    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();

    await _incomingDataController.close();
  }

  /// Handle incoming messages from isolate
  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      if (!_ready.isCompleted) {
        _ready.complete();
      }
    } else if (message is LogRecord) {
      Log.logIsolateMessage(message);
    } else if (message is List) {
      // Handle batch of data samples
      for (final item in message) {
        if (item is Map<String, dynamic>) {
          final dataMessage = IsolateDataMessage.fromMap(item);
          _incomingDataController.add(dataMessage);
        }
      }
    } else if (message is InitializedMessage) {
      if (!_initialized.isCompleted) {
        logger.finer('Isolate for stream $streamId initialized');
        _initialized.complete();
      }
    } else if (message is ResponseMessage) {
      final completer = _responseCompleters.remove(message.requestID);
      completer?.complete();
    } else if (message is Map<String, dynamic>) {
      // Handle status messages
      logger.warning('Unhandled isolate message: $message');
    }
  }

  /// Create worker configuration - implemented by subclasses
  IsolateWorkerConfig _createConfig();

  /// Get worker function - implemented by subclasses
  Future<void> Function(IsolateWorkerConfig) _getWorkerFunction();
}

/// Inlet isolate for receiving data from multiple sources
class StreamInletIsolate extends StreamIsolate {
  final List<int> _inletAddresses = [];

  StreamInletIsolate({
    required super.streamId,
    required super.dataType,
    required super.useBusyWaitInlets,
    required super.useBusyWaitOutlets,
    required super.pollingInterval,
    List<int>? initialInletAddresses,
    String? isolateDebugName,
  }) : super(
         isolateDebugName: isolateDebugName ?? 'StreamInletIsolate-$streamId',
       ) {
    if (initialInletAddresses != null) {
      _inletAddresses.addAll(initialInletAddresses);
    }
  }

  /// Add an inlet to the running isolate
  Future<void> addInlet(int address) async {
    _inletAddresses.add(address);
    final requestRecord = _generateRequestID();
    await sendMessage(AddInletMessage(address, requestID: requestRecord.$1));
    await requestRecord.$2.future;
  }

  /// Remove an inlet from the running isolate
  Future<void> removeInlet(int address) async {
    _inletAddresses.remove(address);
    final requestRecord = _generateRequestID();
    await sendMessage(RemoveInletMessage(address, requestID: requestRecord.$1));
    await requestRecord.$2.future;
  }

  @override
  IsolateWorkerConfig _createConfig() {
    return IsolateWorkerConfig(
      streamId: streamId,
      dataType: dataType,
      channelCount: 1, // Will be updated by inlet creation
      sampleRate: 0, // Will be updated by inlet creation
      useBusyWaitInlets: useBusyWaitInlets,
      useBusyWaitOutlets: useBusyWaitOutlets,
      pollingInterval: pollingInterval,
      mainSendPort: _receivePort!.sendPort,
      inletAddresses: List.from(_inletAddresses),
      debugName: isolateDebugName,
    );
  }

  @override
  Future<void> Function(IsolateWorkerConfig) _getWorkerFunction() =>
      _inletWorker;

  // Static worker function for inlet isolates
  static Future<void> _inletWorker(IsolateWorkerConfig config) async {
    await InletWorker(config).start();
  }
}

/// Outlet isolate for sending data
class StreamOutletIsolate extends StreamIsolate {
  final int _outletAddress;
  final int _channelCount;
  final double _sampleRate;

  StreamOutletIsolate({
    required super.streamId,
    required super.dataType,
    required super.useBusyWaitInlets,
    required super.useBusyWaitOutlets,
    required super.pollingInterval,
    required int outletAddress,
    required int channelCount,
    required double sampleRate,
    String? isolateDebugName,
  }) : _outletAddress = outletAddress,
       _channelCount = channelCount,
       _sampleRate = sampleRate,
       super(
         isolateDebugName: isolateDebugName ?? 'StreamOutletIsolate-$streamId',
       );

  /// Send data through outlet
  Future<void> sendData(List<dynamic> data) async {
    await sendMessage(DataMessage(data));
  }

  Future<void> recreateOutlet(int address) async {
    final requestRecord = _generateRequestID();
    await sendMessage(
      RecreateOutletMessage(address, requestID: requestRecord.$1),
    );
    await requestRecord.$2.future;
  }

  @override
  IsolateWorkerConfig _createConfig() {
    return IsolateWorkerConfig(
      streamId: streamId,
      dataType: dataType,
      channelCount: _channelCount,
      sampleRate: _sampleRate,
      useBusyWaitInlets: useBusyWaitInlets,
      useBusyWaitOutlets: useBusyWaitOutlets,
      pollingInterval: pollingInterval,
      mainSendPort: _receivePort!.sendPort,
      outletAddress: _outletAddress,
      debugName: isolateDebugName,
    );
  }

  @override
  Future<void> Function(IsolateWorkerConfig) _getWorkerFunction() =>
      _outletWorker;

  // Static worker function for outlet isolates
  static Future<void> _outletWorker(IsolateWorkerConfig config) async {
    await OutletWorker(config).start();
  }
}

/// Factory for creating LSL stream isolates
class IsolateStreamManager {
  /// Creates an inlet isolate instance
  static StreamInletIsolate createInletIsolate({
    required String streamId,
    required StreamDataType dataType,
    required bool useBusyWaitInlets,
    required bool useBusyWaitOutlets,
    required Duration pollingInterval,
    List<int>? initialInletAddresses,
    String? isolateDebugName,
  }) {
    return StreamInletIsolate(
      streamId: streamId,
      dataType: dataType,
      useBusyWaitInlets: useBusyWaitInlets,
      useBusyWaitOutlets: useBusyWaitOutlets,
      pollingInterval: pollingInterval,
      initialInletAddresses: initialInletAddresses,
      isolateDebugName: isolateDebugName,
    );
  }

  /// Creates an outlet isolate instance
  static StreamOutletIsolate createOutletIsolate({
    required String streamId,
    required StreamDataType dataType,
    required bool useBusyWaitInlets,
    required bool useBusyWaitOutlets,
    required Duration pollingInterval,
    required int outletAddress,
    required int channelCount,
    required double sampleRate,
  }) {
    return StreamOutletIsolate(
      streamId: streamId,
      dataType: dataType,
      useBusyWaitInlets: useBusyWaitInlets,
      useBusyWaitOutlets: useBusyWaitOutlets,
      pollingInterval: pollingInterval,
      outletAddress: outletAddress,
      channelCount: channelCount,
      sampleRate: sampleRate,
    );
  }

  /// Performs one-time stream discovery in an isolate to avoid blocking main thread
  static Future<List<LSLStreamInfo>> discoverOnceIsolated({
    required String predicate,
    Duration timeout = const Duration(seconds: 2),
    int minStreams = 0,
    int maxStreams = 10,
  }) async {
    final List<int> streamAddrs = await Isolate.run(() async {
      try {
        final streams = await LSL.resolveStreamsByPredicate(
          predicate: predicate,
          waitTime: timeout.inMilliseconds / 1000.0,
          minStreamCount: minStreams,
          maxStreams: maxStreams,
        );

        return streams.map((s) => s.streamInfo.address).toList();
      } catch (e) {
        // Return empty list on error
        return <int>[];
      }
    }, debugName: 'resolver:$predicate');
    return streamAddrs
        .map((addr) => LSLStreamInfo.fromStreamInfoAddr(addr))
        .toList();
  }

  // Static helper methods for creating LSL resources
  static LSLOutlet _createOutlet(IsolateWorkerConfig config) {
    final streamInfo = LSLStreamInfoWithMetadata.fromStreamInfoAddr(
      config.outletAddress!,
    );
    return LSLOutlet(streamInfo, useIsolates: false, chunkSize: 1)..create();
  }

  static Future<List<LSLInlet>> _createInlets(
    IsolateWorkerConfig config,
  ) async {
    final inletFutures =
        config.inletAddresses!.map((addr) async {
          return _createInletFromAddr(addr, config.dataType);
        }).toList();

    return await Future.wait(inletFutures);
  }

  static Future<LSLInlet> _createInletFromAddr(
    int streamInfoAddr,
    StreamDataType dataType,
  ) async {
    final streamInfo = LSLStreamInfo.fromStreamInfoAddr(streamInfoAddr);
    logger.finer(
      'Creating inlet for stream ${streamInfo.sourceId} at address $streamInfoAddr',
    );
    final inlet = await _createTypedInlet(streamInfo, dataType);
    await inlet.create();
    return inlet;
  }

  static Future<LSLInlet> _createTypedInlet(
    LSLStreamInfo streamInfo,
    StreamDataType dataType,
  ) async {
    switch (dataType) {
      case StreamDataType.float32:
      case StreamDataType.double64:
        return LSLInlet<double>(streamInfo, chunkSize: 1, useIsolates: false);
      case StreamDataType.int8:
      case StreamDataType.int16:
      case StreamDataType.int32:
      case StreamDataType.int64:
        return LSLInlet<int>(streamInfo, chunkSize: 1, useIsolates: false);
      case StreamDataType.string:
        return LSLInlet<String>(streamInfo, chunkSize: 1, useIsolates: false);
    }
  }
}

/// Base class for isolate workers with shared functionality
abstract class IsolateWorker {
  IsolateWorkerConfig config;
  late final ReceivePort receivePort;

  IsolateWorker(this.config);

  Future<void> start() async {
    receivePort = ReceivePort();
    config.mainSendPort.send(receivePort.sendPort);
    Log.sendPort = config.mainSendPort;

    logger.info('${_getWorkerName()} for stream ${config.streamId} started');

    receivePort.listen(handleMessage);
    await initialize();
    config.mainSendPort.send(const InitializedMessage());
  }

  String _getWorkerName();
  Future<void> initialize();
  FutureOr<void> handleMessage(dynamic message);
}

/// Worker class for handling inlet operations in isolate
class InletWorker extends IsolateWorker {
  // Member variables to replace excessive parameters
  late final List<LSLInlet> inlets;
  late final List<double> timeCorrections;
  late final Lock inletsLock;
  late final Lock timeCorrectionsLock;
  late final MultiLock inletAddRemoveLock;
  late final Lock bufferLock;
  late final ListQueue<Map<String, dynamic>> buffer;
  late final Stopwatch lastTimeCorrectionUpdate;

  bool running = false;
  Timer? timer;
  Completer<void>? completer;

  InletWorker(super.config);

  @override
  String _getWorkerName() => 'Inlet isolate';

  @override
  Future<void> initialize() async {
    logger.fine(
      '[${config.debugName}] Initializing inlet worker for stream ${config.streamId}',
    );
    inlets = await IsolateStreamManager._createInlets(config);
    timeCorrections = List<double>.filled(inlets.length, 0.0, growable: true);
    inletsLock = Lock();
    timeCorrectionsLock = Lock();
    inletAddRemoveLock = MultiLock(locks: [inletsLock, timeCorrectionsLock]);
    bufferLock = Lock();
    buffer = ListQueue<Map<String, dynamic>>();
    lastTimeCorrectionUpdate = Stopwatch();

    lastTimeCorrectionUpdate.start();
    await _updateTimeCorrections(0).then((_) {
      logger.finest(
        'Initial time corrections updated for stream ${config.streamId}',
      );
    });
  }

  @override
  Future<void> handleMessage(dynamic message) async {
    if (message is IsolateMessage) {
      switch (message.type) {
        case IsolateMessageType.start:
          _handleStart();
          break;
        case IsolateMessageType.stop:
          _handleStop();
          break;
        case IsolateMessageType.addInlet:
          await _handleAddInlet(message as AddInletMessage);
          break;
        case IsolateMessageType.removeInlet:
          _handleRemoveInlet(message as RemoveInletMessage);
          break;
        case IsolateMessageType.data:
        case IsolateMessageType.recreateOutlet:
        case IsolateMessageType.initialized:
        case IsolateMessageType.requestResponse:
          // Not applicable for inlet workers
          break;
      }
      if (message.requestID != null) {
        logger.finest(
          'Inlet worker for stream ${config.streamId} sending response for request ${message.requestID}',
        );
        config.mainSendPort.send(ResponseMessage(requestID: message.requestID));
      }
    }
  }

  void _handleStart() {
    if (running) {
      logger.info(
        'Inlet worker for stream ${config.streamId} is already running, ignoring start request',
      );
      return;
    }
    running = true;

    if (completer == null || completer!.isCompleted) {
      completer = Completer<void>();
    }

    if (config.useBusyWaitInlets) {
      logger.info(
        'Starting busy-wait inlet worker for stream ${config.streamId}',
      );
      _startBusyWaitInletsWorker();
    } else {
      logger.info(
        'Starting timer-based inlet worker for stream ${config.streamId}',
      );
      timer = Timer.periodic(config.pollingInterval, (_) async {
        if (!running) {
          timer?.cancel();
          return;
        }
        await inletsLock.synchronized(() async {
          _pollInletsWorker();
        });
        if (buffer.isNotEmpty) {
          await bufferLock.synchronized(() {
            if (buffer.isNotEmpty) {
              config.mainSendPort.send(List.from(buffer));
              buffer.clear();
            }
          });
        }
      });
    }
  }

  void _handleStop() {
    if (!running) {
      logger.fine(
        'Inlet worker for stream ${config.streamId} is not running, ignoring stop request',
      );
      return;
    }
    logger.info('Stopping inlet worker for stream ${config.streamId}');
    running = false;
    timer?.cancel();
    if (completer != null && !completer!.isCompleted) {
      completer?.complete();
    }
    lastTimeCorrectionUpdate.stop();
    bufferLock.synchronized(() {
      if (buffer.isNotEmpty) {
        config.mainSendPort.send(List.from(buffer));
        buffer.clear();
      }
    });
  }

  Future<void> _handleAddInlet(AddInletMessage message) async {
    logger.finest(
      '[${config.debugName}] Adding inlet for address ${message.address} in stream ${config.streamId}',
    );
    final newInlet = await IsolateStreamManager._createInletFromAddr(
      message.address,
      config.dataType,
    );
    inletAddRemoveLock.synchronized(() {
      inlets.add(newInlet);
      timeCorrections.add(0.0);
    });
  }

  void _handleRemoveInlet(RemoveInletMessage message) {
    inletAddRemoveLock.synchronized(() {
      int? index;
      inlets.whereIndexed((i, inlet) {
        if (inlet.streamInfo.streamInfo.address == message.address) {
          index = i;
          return true;
        }
        return false;
      });
      if (index != null) {
        inlets[index!].destroy();
        inlets.removeAt(index!);
        timeCorrections.removeAt(index!);
      }
    });
  }

  // Member methods for time corrections and polling
  Future<void> _updateTimeCorrections([
    int minTimeSinceLastUpdate = 5000,
  ]) async {
    await timeCorrectionsLock.synchronized(() async {
      if (!lastTimeCorrectionUpdate.isRunning ||
          lastTimeCorrectionUpdate.elapsedMilliseconds <
              minTimeSinceLastUpdate) {
        return; // Limit updates to every 5 seconds
      }
      final List<Future<double>> futures = [];
      for (int i = 0; i < inlets.length; i++) {
        try {
          futures.add(inlets[i].getTimeCorrection(timeout: 1.0));
        } catch (e) {
          logger.warning('Error updating time correction: $e');
        }
      }
      final results = await Future.wait(futures);
      for (int i = 0; i < results.length; i++) {
        timeCorrections[i] = results[i];
      }
      logger.finer('Updated time corrections for stream ${config.streamId}');
      lastTimeCorrectionUpdate.reset();
    });
  }

  // Inlet-specific polling using member variables instead of parameters
  Future<void> _pollInletsWorker() async {
    int index = 0;
    for (final inlet in inlets) {
      try {
        final sample = inlet.pullSampleSync(timeout: 0.0);

        if (sample.isNotEmpty) {
          final message = IsolateDataMessage(
            streamId: config.streamId,
            messageId: generateUid(),
            timestamp: DateTime.now(),
            data: sample.data,
            sourceId: inlet.streamInfo.sourceId,
            lslTimestamp: sample.timestamp,
            lslTimeCorrection: timeCorrections[index++],
          );

          await bufferLock.synchronized(() {
            buffer.add(message.toMap());
          });
        }
      } catch (e) {
        logger.severe('Error polling inlet: $e');
      }
    }
  }

  void _startBusyWaitInletsWorker() {
    runPreciseIntervalAsync(
      config.pollingInterval,
      (state) async {
        inletsLock.synchronized(() async {
          await _pollInletsWorker();
        });

        bufferLock.synchronized(() {
          if (buffer.isNotEmpty) {
            config.mainSendPort.send(List.from(buffer));
            buffer.clear();
          }
        });
        _updateTimeCorrections();

        return state;
      },
      completer: completer!,
      state: null,
      startBusyAt: Duration(
        microseconds: (config.pollingInterval.inMicroseconds * 0.99).round(),
      ),
    );
  }
}

/// Worker class for handling outlet operations in isolate
class OutletWorker extends IsolateWorker {
  // Member variables instead of excessive parameters
  late LSLOutlet outlet;
  bool running = false;
  Timer? timer;
  Completer<void>? completer;

  OutletWorker(super.config);

  @override
  String _getWorkerName() => 'Outlet isolate';

  @override
  Future<void> initialize() async {
    outlet = IsolateStreamManager._createOutlet(config);
  }

  @override
  void handleMessage(dynamic message) {
    if (message is IsolateMessage) {
      switch (message.type) {
        case IsolateMessageType.start:
          _handleStart();
          break;
        case IsolateMessageType.stop:
          _handleStop();
          break;
        case IsolateMessageType.data:
          _handleData(message as DataMessage);
          break;
        case IsolateMessageType.recreateOutlet:
          _recreateOutlet(message as RecreateOutletMessage);
          break;
        case IsolateMessageType.addInlet:
        case IsolateMessageType.removeInlet:
        case IsolateMessageType.initialized:
        case IsolateMessageType.requestResponse:
          // Not applicable for outlet workers
          break;
      }
      if (message.requestID != null) {
        logger.finest(
          'Outlet worker for stream ${config.streamId} sending response for request ${message.requestID}',
        );
        config.mainSendPort.send(ResponseMessage(requestID: message.requestID));
      }
    }
  }

  void _recreateOutlet(RecreateOutletMessage message) {
    // We own the streaminfo.
    outlet.streamInfo.destroy();
    outlet.destroy();
    config = config.copyWith(outletAddress: message.address);
    outlet = IsolateStreamManager._createOutlet(config);
  }

  void _handleStart() {
    if (running) {
      logger.fine(
        'Outlet worker for stream ${config.streamId} is already running, ignoring start request',
      );
      return;
    }
    running = true;
    // For coordination streams and on-demand data streams, just wait for data messages
    // No automatic sample generation needed
  }

  void _handleStop() {
    if (!running) {
      logger.fine(
        'Outlet worker for stream ${config.streamId} is not running, ignoring stop request',
      );
      return;
    }
    logger.info('Stopping outlet worker for stream ${config.streamId}');
    running = false;
    timer?.cancel();
    if (completer != null && !completer!.isCompleted) {
      completer?.complete();
    }
  }

  void _handleData(DataMessage message) {
    if (running) {
      outlet.pushSampleSync(message.payload);
    }
  }
}
