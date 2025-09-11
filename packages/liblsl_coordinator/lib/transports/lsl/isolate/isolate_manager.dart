// lib/transports/lsl/isolate/isolate_manager.dart

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:collection/collection.dart';
import 'package:liblsl/lsl.dart';

import 'package:liblsl_coordinator/framework.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

/// Enum defining all possible isolate message types
enum IsolateMessageType {
  start, // 0
  initialized, // 1
  requestResponse, // 2
  stop, // 3
  addInlet, // 4
  removeInlet, // 5
  data, // 6
  recreateOutlet, // 7
  pause, // 8
  resume, // 9
  flush, // 10
}

/// This is dumb, but despite Enum being immutable, it doesn't work
/// with 'vm:deeply-immutable' pragma, so this just wraps the conversion
/// from int to enum value. The enum is only used in this file anyway.
extension IsolateMessageTypeInt on IsolateMessageType {
  /// Convert int [value] to IsolateMessageType
  static IsolateMessageType fromInt(int value) {
    return IsolateMessageType.values[value];
  }
}

/// Interface for all isolate messages
abstract interface class IIMessage {
  /// The enum index, Enum breaks deeply immutable, despite being immutable
  int get type;

  /// An optional [requestID] for matching requests and responses
  /// If set, the isolate will respond with a [ResponseMessage] with the same ID
  /// allowing the sender to await completion
  String? get requestID;
}

/// Base class for all isolate messages - immutable for efficient message passing
@pragma('vm:deeply-immutable')
sealed class IsolateMessage implements IIMessage {
  @override
  final int type;

  @override
  final String? requestID;

  const IsolateMessage(this.type, {this.requestID});
}

/// Base class for mutable isolate messages - will be copied when sent
/// (probably?)
/// This is probably more accurately `NonImmutableIsolateMessage`
sealed class MutableIsolateMessage implements IIMessage {
  @override
  final int type;

  @override
  final String? requestID;

  const MutableIsolateMessage(this.type, {this.requestID});
}

/// Message to send data through outlet - non-immutable thanks to List
final class DataMessage extends MutableIsolateMessage {
  /// This is always List of ImmutableType, but dart doesnt care
  final List<dynamic> payload;

  const DataMessage(this.payload, {super.requestID}) : super(6);
}

/// Message to start isolate processing - immutable
@pragma('vm:deeply-immutable')
final class StartMessage extends IsolateMessage {
  const StartMessage({super.requestID}) : super(0);
}

/// Message to stop isolate processing - immutable
@pragma('vm:deeply-immutable')
final class StopMessage extends IsolateMessage {
  const StopMessage({super.requestID}) : super(3);
}

/// Message to add an inlet to running isolate - immutable
@pragma('vm:deeply-immutable')
final class AddInletMessage extends IsolateMessage {
  final int address;

  const AddInletMessage(this.address, {super.requestID}) : super(4);
}

/// Message to remove an inlet from running isolate - immutable
@pragma('vm:deeply-immutable')
final class RemoveInletMessage extends IsolateMessage {
  final int address;

  const RemoveInletMessage(this.address, {super.requestID}) : super(5);
}

/// Message to recreate outlet - immutable
@pragma('vm:deeply-immutable')
final class RecreateOutletMessage extends IsolateMessage {
  final int address; // stream info address
  const RecreateOutletMessage(this.address, {super.requestID}) : super(7);
}

/// Message to pause isolate processing - immutable
@pragma('vm:deeply-immutable')
final class PauseMessage extends IsolateMessage {
  const PauseMessage({super.requestID}) : super(8);
}

/// Message to resume isolate processing - immutable
@pragma('vm:deeply-immutable')
final class ResumeMessage extends IsolateMessage {
  final bool flushBeforeResume;
  const ResumeMessage({this.flushBeforeResume = true, super.requestID})
    : super(9);
}

/// Message to flush inlet streams - immutable
@pragma('vm:deeply-immutable')
final class FlushMessage extends IsolateMessage {
  const FlushMessage({super.requestID}) : super(10);
}

/// Message to notify main thread that the isolate is initialized
@pragma('vm:deeply-immutable')
final class InitializedMessage extends IsolateMessage {
  const InitializedMessage({super.requestID}) : super(1);
}

/// Message to notify main thread of request response
@pragma('vm:deeply-immutable')
final class ResponseMessage extends IsolateMessage {
  const ResponseMessage({required super.requestID}) : super(2);
}

/// Configuration for isolate workers
final class IsolateWorkerConfig {
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

  const IsolateWorkerConfig({
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
final class IsolateDataMessage {
  final String streamId;
  final String messageId;
  final DateTime timestamp;
  // Should be an immutable list (e.g. List.unmodifiable, and contain only immutable types)
  final List<dynamic> data;
  final String? sourceId;
  final double? lslTimestamp;
  final double? lslTimeCorrection;

  const IsolateDataMessage({
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
      data: List.unmodifiable(map['data']),
      sourceId: map['sourceId'] as String?,
      lslTimestamp: map['lslTimestamp'] as double?,
      lslTimeCorrection: map['lslTimeCorrection'] as double?,
    );
  }
}

final class IsolateDataMessageList {
  final List<IsolateDataMessage> messages;

  const IsolateDataMessageList(this.messages);

  Map<String, dynamic> toMap() => {
    'messages': messages.map((m) => m.toMap()).toList(),
  };

  factory IsolateDataMessageList.fromMap(Map<String, dynamic> map) {
    return IsolateDataMessageList(
      (map['messages'] as List)
          .map((m) => IsolateDataMessage.fromMap(m as Map<String, dynamic>))
          .toList(),
    );
  }

  factory IsolateDataMessageList.from(Iterable<IsolateDataMessage> messages) {
    return IsolateDataMessageList(messages.toList(growable: false));
  }
}

/// Base class for stream isolates with shared functionality
sealed class StreamIsolate {
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
  bool stopped = false;
  bool paused = false;

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

  /// Send a mutable message to the isolate - will be copied :(
  Future<void> sendDataMessage(MutableIsolateMessage message) async {
    await _initialized.future;
    _sendPort?.send(message);
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
    stopped = false;
    paused = false;
    final requestRecord = _generateRequestID();
    logger.finest(
      '[$isolateDebugName] Starting isolate for stream $streamId with request ID ${requestRecord.$1}',
    );
    await sendMessage(StartMessage(requestID: requestRecord.$1));
    await requestRecord.$2.future;
  }

  /// Pause isolate processing (keeps streams alive but stops polling)
  Future<void> pause() async {
    if (paused || stopped) return;
    paused = true;
    final requestRecord = _generateRequestID();
    logger.finest(
      '[$isolateDebugName] Pausing isolate for stream $streamId with request ID ${requestRecord.$1}',
    );
    await sendMessage(PauseMessage(requestID: requestRecord.$1));
    await requestRecord.$2.future;
  }

  /// Resume isolate processing
  Future<void> resume({bool flushBeforeResume = true}) async {
    if (!paused || stopped) return;
    paused = false;
    final requestRecord = _generateRequestID();
    logger.finest(
      '[$isolateDebugName] Resuming isolate for stream $streamId with request ID ${requestRecord.$1}, flush: $flushBeforeResume',
    );
    await sendMessage(
      ResumeMessage(
        flushBeforeResume: flushBeforeResume,
        requestID: requestRecord.$1,
      ),
    );
    await requestRecord.$2.future;
  }

  /// Flush inlet streams to clear pending messages
  Future<void> flush() async {
    if (stopped) return;
    final requestRecord = _generateRequestID();
    logger.finest(
      '[$isolateDebugName] Flushing streams for stream $streamId with request ID ${requestRecord.$1}',
    );
    await sendMessage(FlushMessage(requestID: requestRecord.$1));
    await requestRecord.$2.future;
  }

  /// Stop isolate processing
  Future<void> stop() async {
    stopped = true;
    paused = false;
    final requestRecord = _generateRequestID();
    logger.finest(
      '[$isolateDebugName] Stopping isolate for stream $streamId with request ID ${requestRecord.$1}',
    );
    await sendMessage(StopMessage(requestID: requestRecord.$1));
    await requestRecord.$2.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        logger.warning(
          'Timeout waiting for isolate to stop for stream $streamId',
        );
      },
    );
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;

    _isolate?.kill(priority: Isolate.immediate);
    // await incomingData.drain();
    // await _incomingDataController.close().timeout(
    //   const Duration(seconds: 2),
    //   onTimeout: () {
    //     logger.warning(
    //       'Timeout waiting for incoming data controller to close for stream $streamId',
    //     );
    //   },
    // );
  }

  /// Clean up resources
  Future<void> dispose() async {
    /// @TODO: Instead of killing isolate in stop, do it here,
    /// needs to be changed in the isolate worker as well
    if (!stopped) {
      await stop();
    }
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
    }
    if (message is IsolateDataMessage) {
      // Handle single data sample
      _incomingDataController.add(message);
    } else if (message is IsolateDataMessageList) {
      // Handle batch of data samples
      for (final msg in message.messages) {
        _incomingDataController.add(msg);
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
final class StreamInletIsolate extends StreamIsolate {
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
      inletAddresses: List.unmodifiable(_inletAddresses),
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
final class StreamOutletIsolate extends StreamIsolate {
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
    await sendDataMessage(DataMessage(data));
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

/// Factory container for creating LSL stream isolates
final class IsolateStreamManager {
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
sealed class IsolateWorker {
  /// Configuration for the worker
  IsolateWorkerConfig config;

  /// The isolate's receive port
  late final ReceivePort receivePort;

  IsolateWorker(this.config);

  /// Start the worker
  Future<void> start() async {
    receivePort = ReceivePort();
    config.mainSendPort.send(receivePort.sendPort);
    Log.sendPort = config.mainSendPort;

    logger.info('${_getWorkerName()} for stream ${config.streamId} started');

    receivePort.listen(handleMessage);
    await initialize();
    config.mainSendPort.send(const InitializedMessage());
  }

  /// Get the worker name for logging
  @mustBeOverridden
  String _getWorkerName();

  /// Initialize the worker - to be implemented by subclasses
  @mustBeOverridden
  Future<void> initialize();

  /// Handle incoming messages - to be implemented by subclasses
  @mustBeOverridden
  FutureOr<void> handleMessage(dynamic message);
}

/// Worker class for handling inlet operations in isolate
final class InletWorker extends IsolateWorker {
  /// List of active inlets
  late final List<LSLInlet> inlets;

  /// List of time corrections for each inlet (fragile, needs to be exactly
  /// the same length as inlets)
  late final List<double> timeCorrections;

  /// Lock for inlet operations
  late final Lock inletsLock;

  /// Lock for time correction operations
  late final Lock timeCorrectionsLock;

  /// Combined lock for adding/removing inlets and updating time corrections
  late final MultiLock inletAddRemoveLock;

  /// Lock for buffer operations
  late final Lock bufferLock;

  /// Buffer for incoming data messages
  late final ListQueue<IsolateDataMessage> buffer;

  /// Stopwatch for tracking time since last time correction update
  late final Stopwatch lastTimeCorrectionUpdate;

  /// Whether the worker is currently running, technically public but isn't used
  /// outside this class/subclasses anyway
  @protected
  bool running = false;

  /// Whether the worker is currently paused (running but not polling)
  @protected
  bool paused = false;

  /// Timer for periodic polling (if not using busy-wait)
  Timer? timer;

  /// Completer for polling loops
  Completer<void>? completer;

  /// Completer for resuming from pause
  Completer<void>? resumeCompleter;

  /// Constructor
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
    buffer = ListQueue<IsolateDataMessage>();
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
    if (message is IIMessage) {
      final IsolateMessageType messageType =
          IsolateMessageType.values[message.type];
      switch (messageType) {
        case IsolateMessageType.start:
          _handleStart();
          break;
        case IsolateMessageType.stop:
          logger.info(
            'Stopping inlet worker for stream ${config.streamId} on stop request',
          );
          await _handleStop();
        // Isolate.exit(
        //   config.mainSendPort,
        //   ResponseMessage(requestID: message.requestID),
        // );
        case IsolateMessageType.pause:
          await _handlePause();
          break;
        case IsolateMessageType.resume:
          await _handleResume(message as ResumeMessage);
          break;
        case IsolateMessageType.flush:
          await _handleFlush();
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
    paused = false;

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
        if (!running || paused) {
          if (!running) timer?.cancel();
          if (paused && resumeCompleter != null) {
            await resumeCompleter!.future;
            resumeCompleter = null;
          }
          return;
        }
        await inletsLock.synchronized(() async {
          _pollInletsWorker();
        });
        if (buffer.isNotEmpty) {
          await bufferLock.synchronized(() {
            if (buffer.isNotEmpty) {
              config.mainSendPort.send(IsolateDataMessageList.from(buffer));
              buffer.clear();
            }
          });
        }
      });
    }
  }

  Future<void> _handlePause() async {
    if (!running || paused) {
      logger.fine(
        'Inlet worker for stream ${config.streamId} is not running or already paused, ignoring pause request',
      );
      return;
    }
    logger.info('Pausing inlet worker for stream ${config.streamId}');
    paused = true;
    resumeCompleter = Completer<void>();
    // Note: we don't cancel timer or complete completer - just set paused flag
    // Timer-based polling will check paused flag, busy-wait will be handled in the loop
  }

  Future<void> _handleResume(ResumeMessage message) async {
    if (!running || !paused) {
      logger.fine(
        'Inlet worker for stream ${config.streamId} is not running or not paused, ignoring resume request',
      );
      return;
    }
    logger.info(
      'Resuming inlet worker for stream ${config.streamId}, flush: ${message.flushBeforeResume}',
    );

    if (message.flushBeforeResume) {
      await _flushInlets();
    }
    resumeCompleter?.complete();
    paused = false;
    // Polling will automatically resume as paused flag is now false
  }

  Future<void> _handleFlush() async {
    if (!running) {
      logger.fine(
        'Inlet worker for stream ${config.streamId} is not running, ignoring flush request',
      );
      return;
    }
    logger.info('Flushing inlet streams for stream ${config.streamId}');
    await _flushInlets();
  }

  /// Flush all inlet streams to clear pending messages
  Future<void> _flushInlets() async {
    await inletsLock.synchronized(() async {
      for (final inlet in inlets) {
        try {
          await inlet.flush();
        } catch (e) {
          logger.warning('Error flushing inlet: $e');
        }
      }
    });

    // Clear internal buffer as well
    await bufferLock.synchronized(() {
      buffer.clear();
    });

    logger.finest('Flushed all inlet streams for ${config.streamId}');
  }

  Future<void> _handleStop() async {
    if (!running) {
      logger.fine(
        'Inlet worker for stream ${config.streamId} is not running, ignoring stop request',
      );
      return;
    }
    logger.info('Stopping inlet worker for stream ${config.streamId}');
    running = false;
    resumeCompleter?.complete();
    paused = false;
    timer?.cancel();
    if (completer != null && !completer!.isCompleted) {
      completer?.complete();
    }
    lastTimeCorrectionUpdate.stop();
    try {
      await inletAddRemoveLock.synchronized(() async {
        for (final inlet in inlets) {
          await inlet.destroy();
        }
        logger.info('Destroyed all inlets for stream ${config.streamId}');
        inlets.clear();
        timeCorrections.clear();
      });
      await bufferLock.synchronized(() {
        if (buffer.isNotEmpty) {
          config.mainSendPort.send(IsolateDataMessageList.from(buffer));
          buffer.clear();
        }
        logger.fine('Cleared FINAL buffer for stream ${config.streamId}');
      });
    } catch (e) {
      logger.severe('Error destroying inlets: $e');
    }
    // receivePort.close();
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
            buffer.add(message);
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
        if (!running || paused) {
          if (paused && resumeCompleter != null) {
            // hang out here until we resume
            await resumeCompleter!.future;
            resumeCompleter = null;
          }
          return state; // Skip polling if not running
        }

        inletsLock.synchronized(() async {
          await _pollInletsWorker();
        });

        bufferLock.synchronized(() {
          if (buffer.isNotEmpty) {
            config.mainSendPort.send(IsolateDataMessageList.from(buffer));
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
final class OutletWorker extends IsolateWorker {
  /// The outlet instance
  late LSLOutlet outlet;

  /// Whether the worker is currently running, technically public but isn't used
  /// outside this class/subclasses anyway
  @protected
  bool running = false;

  /// Whether the worker is currently paused (running but not sending data)
  @protected
  bool paused = false;

  /// Timer for periodic tasks (if needed)
  Timer? timer;

  /// Completer for polling loops
  Completer<void>? completer;

  /// Constructor
  OutletWorker(super.config);

  @override
  String _getWorkerName() => 'Outlet isolate';

  @override
  Future<void> initialize() async {
    outlet = IsolateStreamManager._createOutlet(config);
  }

  @override
  Future<void> handleMessage(dynamic message) async {
    if (message is IIMessage) {
      final IsolateMessageType messageType =
          IsolateMessageType.values[message.type];
      switch (messageType) {
        case IsolateMessageType.start:
          _handleStart();
          break;
        case IsolateMessageType.stop:
          logger.info(
            'Stopping outlet worker for stream ${config.streamId} on stop request',
          );
          await _handleStop();
        // Isolate.exit(
        //   config.mainSendPort,
        //   ResponseMessage(requestID: message.requestID),
        // );
        case IsolateMessageType.pause:
          await _handlePause();
          break;
        case IsolateMessageType.resume:
          await _handleResume(message as ResumeMessage);
          break;
        case IsolateMessageType.flush:
          // Outlets don't need flushing - they don't buffer input
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
    paused = false;
    // For coordination streams and on-demand data streams, just wait for data messages
    // No automatic sample generation needed
  }

  Future<void> _handlePause() async {
    if (!running || paused) {
      logger.fine(
        'Outlet worker for stream ${config.streamId} is not running or already paused, ignoring pause request',
      );
      return;
    }
    logger.info('Pausing outlet worker for stream ${config.streamId}');
    paused = true;
    // Outlet just sets paused flag - data messages will be ignored
  }

  Future<void> _handleResume(ResumeMessage message) async {
    if (!running || !paused) {
      logger.fine(
        'Outlet worker for stream ${config.streamId} is not running or not paused, ignoring resume request',
      );
      return;
    }
    logger.info('Resuming outlet worker for stream ${config.streamId}');
    paused = false;
    // flushBeforeResume doesn't apply to outlets - they don't buffer data
  }

  Future<void> _handleStop() async {
    if (!running) {
      logger.fine(
        'Outlet worker for stream ${config.streamId} is not running, ignoring stop request',
      );
      return;
    }
    logger.info('Stopping outlet worker for stream ${config.streamId}');
    running = false;
    paused = false;
    timer?.cancel();
    if (completer != null && !completer!.isCompleted) {
      completer?.complete();
    }
    await outlet.destroy();
    // receivePort.close();
    logger.info('Destroyed outlet for stream ${config.streamId}');
  }

  void _handleData(DataMessage message) {
    if (running && !paused) {
      outlet.pushSampleSync(message.payload);
    }
  }
}
