// lib/transports/lsl/isolate/isolate_manager.dart

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:liblsl/lsl.dart';

import 'package:liblsl_coordinator/framework.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';
import 'outlet_buffer_pool.dart';
import 'time_correction_schedule.dart';

/// Enum defining all possible isolate message types
enum IsolateMessageType {
  start, // 0
  initialized, // 1
  requestResponse, // 2
  stop, // 3
  addInlet, // 4
  removeInlet, // 5
  sample, // 6
  recreateOutlet, // 7
  pause, // 8
  resume, // 9
  flush, // 10
  data, // 11
  bufferReleased, // 12
  consumerPresence, // 13
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
// sealed class MutableIsolateMessage implements IIMessage {
//   @override
//   final int type;

//   @override
//   final String? requestID;

//   const MutableIsolateMessage(this.type, {this.requestID});
// }

/// Message to send data through outlet - non-immutable thanks to List
@pragma('vm:deeply-immutable')
final class SampleMessage extends IsolateMessage {
  final LSLSamplePointer payload;

  const SampleMessage(this.payload, {super.requestID}) : super(6);
}

@pragma('vm:deeply-immutable')
final class DataMessage extends IsolateMessage {
  final Pointer<NativeType> payload;

  /// Index of the pooled buffer backing [payload]; echoed back via
  /// [BufferReleasedMessage] once the worker has pushed the sample.
  final int bufferIndex;

  const DataMessage(this.payload, {required this.bufferIndex, super.requestID})
    : super(11);
}

/// Sent from the outlet worker back to the main isolate once a pooled
/// send buffer may be reused.
@pragma('vm:deeply-immutable')
final class BufferReleasedMessage extends IsolateMessage {
  final int bufferIndex;

  const BufferReleasedMessage(this.bufferIndex) : super(12);
}

/// Sent from the outlet worker when its consumer count crosses zero.
///
/// The only signal there is. `stream_outlet_impl::push_sample` fans out over
/// the registered consumers and, with none registered, silently discards the
/// sample and reports success — so an outlet nobody is listening to is
/// indistinguishable from a working one at every layer above liblsl. That is
/// the shape of the 2026-08-31 failure: a participant's coordination
/// heartbeats stopped reaching the coordinator with no error anywhere, on any
/// device, while its other streams kept working.
@pragma('vm:deeply-immutable')
final class ConsumerPresenceMessage extends IsolateMessage {
  /// Whether at least one consumer is subscribed.
  final bool hasConsumers;

  const ConsumerPresenceMessage(this.hasConsumers) : super(13);
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
  final IList<int>? inletAddresses;

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
    IList<int>? inletAddresses,
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
  final DateTime timestamp;
  // Should be an immutable list (e.g. List.unmodifiable, and contain only immutable types)
  final IList<dynamic> data;
  final String? sourceId;
  final double? lslTimestamp;
  final double? lslTimeCorrection;

  /// Error bound on [lslTimeCorrection], in seconds: the full round-trip time
  /// of the probe liblsl derived the offset from, so the true offset lies
  /// within half of it. Null whenever [lslTimeCorrection] is.
  final double? lslTimeCorrectionUncertainty;

  /// `lsl_local_clock()` on *this* machine when the sample was pulled.
  ///
  /// Captured inside the inlet isolate so it excludes the isolate-port hop that
  /// follows, and shares a clock domain with [lslTimestamp] once
  /// [lslTimeCorrection] has been added to the latter.
  final double? localClock;

  const IsolateDataMessage({
    required this.streamId,
    required this.timestamp,
    required this.data,
    this.sourceId,
    this.lslTimestamp,
    this.lslTimeCorrection,
    this.lslTimeCorrectionUncertainty,
    this.localClock,
  });

  Map<String, dynamic> toMap() => {
    'streamId': streamId,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
    'sourceId': sourceId,
    'lslTimestamp': lslTimestamp,
    'lslTimeCorrection': lslTimeCorrection,
    'lslTimeCorrectionUncertainty': lslTimeCorrectionUncertainty,
    'localClock': localClock,
  };

  factory IsolateDataMessage.fromMap(Map<String, dynamic> map) {
    return IsolateDataMessage(
      streamId: map['streamId'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      data: map['data'],
      sourceId: map['sourceId'] as String?,
      lslTimestamp: map['lslTimestamp'] as double?,
      lslTimeCorrection: map['lslTimeCorrection'] as double?,
      lslTimeCorrectionUncertainty:
          map['lslTimeCorrectionUncertainty'] as double?,
      localClock: map['localClock'] as double?,
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

/// One inlet's clock-offset estimate, as measured inside the inlet isolate.
///
/// The isolate-side counterpart of `ClockSyncSample`; kept separate so the
/// isolate layer has no opinion about the public data model, exactly as
/// [IsolateDataMessage] is separate from `MessageTiming`.
///
/// Sent on the estimate's own cadence (at most every 5 s per inlet), not per
/// sample: [IsolateDataMessage] already carries the offset a sample was
/// stamped with, so repeating [remoteTime] and [clockReset] on every one of
/// several hundred samples per second would be pure duplication. What it adds
/// is that the estimates are reported *even when no data arrives*.
final class IsolateClockSync {
  final String? sourceId;
  final double? offset;
  final double? remoteTime;
  final double? uncertainty;
  final double localClock;

  /// Whether the source machine's clock may have been reset since the previous
  /// estimate. Reading liblsl's flag clears it, so this is true on exactly one
  /// estimate per reset.
  final bool clockReset;

  const IsolateClockSync({
    required this.localClock,
    this.sourceId,
    this.offset,
    this.remoteTime,
    this.uncertainty,
    this.clockReset = false,
  });

  Map<String, dynamic> toMap() => {
    'sourceId': sourceId,
    'offset': offset,
    'remoteTime': remoteTime,
    'uncertainty': uncertainty,
    'localClock': localClock,
    'clockReset': clockReset,
  };

  factory IsolateClockSync.fromMap(Map<String, dynamic> map) =>
      IsolateClockSync(
        sourceId: map['sourceId'] as String?,
        offset: map['offset'] as double?,
        remoteTime: map['remoteTime'] as double?,
        uncertainty: map['uncertainty'] as double?,
        localClock: map['localClock'] as double,
        clockReset: map['clockReset'] as bool? ?? false,
      );
}

/// A batch of [IsolateClockSync], one per inlet refreshed in the same pass.
final class IsolateClockSyncList {
  final List<IsolateClockSync> samples;

  const IsolateClockSyncList(this.samples);

  factory IsolateClockSyncList.from(Iterable<IsolateClockSync> samples) =>
      IsolateClockSyncList(samples.toList(growable: false));
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
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
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

  /// Clock-offset estimates from the inlet worker.
  ///
  /// Broadcast, unlike [incomingData]: these are low-rate and optional, so a
  /// stream with no interested consumer must not buffer them, and a consumer
  /// that comes and goes across a stop/start cycle must be able to resubscribe.
  final StreamController<IsolateClockSync> _incomingClockSyncController =
      StreamController<IsolateClockSync>.broadcast();

  Stream<IsolateClockSync> get incomingClockSyncs =>
      _incomingClockSyncController.stream;

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

    // A crashed or exited isolate must fail all in-flight requests,
    // otherwise their completers (and any awaiting sendData calls) hang
    // forever.
    _errorPort = ReceivePort();
    _errorPort!.listen((error) {
      logger.severe('[$isolateDebugName] Uncaught isolate error: $error');
      _failPendingRequests(
        StateError('Isolate for stream $streamId died: $error'),
      );
    });
    _exitPort = ReceivePort();
    _exitPort!.listen((_) {
      _failPendingRequests(StateError('Isolate for stream $streamId exited'));
    });

    final config = _createConfig();
    _isolate = await Isolate.spawn(
      _getWorkerFunction(),
      config,
      debugName: isolateDebugName,
      onError: _errorPort!.sendPort,
      onExit: _exitPort!.sendPort,
    );
    await _initialized.future;
  }

  /// Fails every in-flight request (and initialization, if still pending)
  /// so no caller is left awaiting a response that can never arrive.
  void _failPendingRequests(Object error) {
    if (!_initialized.isCompleted) {
      _initialized.completeError(error);
      // The completer may have no awaiter yet; don't surface an unhandled
      // async error for a failure that is already reported via completers.
      _initialized.future.ignore();
    }
    if (_responseCompleters.isEmpty) return;
    final pending = _responseCompleters.values.toList(growable: false);
    _responseCompleters.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  /// Overridden by the outlet manager; ignored elsewhere.
  void _handleConsumerPresence(ConsumerPresenceMessage message) {}

  /// Send a message to the isolate - now sends objects directly!
  Future<void> sendMessage(IsolateMessage message) async {
    await _initialized.future;
    _sendPort?.send(message); // Direct object sending - no serialization!
  }

  /// Send a mutable message to the isolate
  Future<void> sendDataMessage(DataMessage message) async {
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

    // Close notification ports before the kill so a normal stop doesn't
    // route through the crash path.
    _errorPort?.close();
    _errorPort = null;
    _exitPort?.close();
    _exitPort = null;

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    // Anything still awaiting a response (e.g. a timed-out stop request or
    // in-flight sends) must not hang forever.
    _failPendingRequests(StateError('Isolate for stream $streamId stopped'));

    // Don't await: close() completes when the (already cancelled) listener
    // is done, and teardown must not block on that.
    unawaited(_incomingDataController.close());
    unawaited(_incomingClockSyncController.close());
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
      Log.replayRecord(message);
    }
    if (message is IsolateDataMessage) {
      // Handle single data sample
      _incomingDataController.add(message);
    } else if (message is IsolateDataMessageList) {
      // Handle batch of data samples
      for (final msg in message.messages) {
        _incomingDataController.add(msg);
      }
    } else if (message is ConsumerPresenceMessage) {
      _handleConsumerPresence(message);
    } else if (message is InitializedMessage) {
      if (!_initialized.isCompleted) {
        logger.finer('Isolate for stream $streamId initialized');
        _initialized.complete();
      }
    } else if (message is ResponseMessage) {
      final completer = _responseCompleters.remove(message.requestID);
      completer?.complete();
    } else if (message is IsolateClockSyncList) {
      for (final sample in message.samples) {
        _incomingClockSyncController.add(sample);
      }
    } else if (message is BufferReleasedMessage) {
      _handleBufferReleased(message);
    } else if (message is Map<String, dynamic>) {
      // Handle status messages
      logger.warning('Unhandled isolate message: $message');
    }
  }

  /// Create worker configuration - implemented by subclasses
  IsolateWorkerConfig _createConfig();

  /// Buffer recycling - only meaningful for outlet isolates.
  void _handleBufferReleased(BufferReleasedMessage message) {}

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

  /// How long the main isolate waits for the worker to acknowledge an inlet
  /// add or remove before giving up on it.
  ///
  /// These waits used to be unbounded. A worker blocked inside a native call
  /// therefore hung its caller too, and since the caller is
  /// `CoordinationController`'s discovery path, the node stayed in
  /// `_pendingJoinNodeUIds` forever and could never be re-offered a join — the
  /// `Join already in progress ... skipping` loop. Worse, the eviction that
  /// should have cleaned the dead peer up queued its `removeInlet` behind the
  /// very `addInlet` that was stuck, so the wedge could not clear itself.
  ///
  /// Generous relative to [IsolateStreamManager.inletCreateTimeout] so that a
  /// worker doing its job is never abandoned; this fires only when the worker
  /// is genuinely wedged.
  static const Duration inletRequestTimeout = Duration(seconds: 5);

  /// Add an inlet to the running isolate
  Future<void> addInlet(int address) async {
    _inletAddresses.add(address);
    final requestRecord = _generateRequestID();
    await sendMessage(AddInletMessage(address, requestID: requestRecord.$1));
    await requestRecord.$2.future.timeout(
      inletRequestTimeout,
      onTimeout: () {
        // Thrown, not swallowed: the caller has to learn the inlet is not
        // usable so it can drop its pending-join bookkeeping and retry, rather
        // than believing the peer was admitted.
        _inletAddresses.remove(address);
        throw TimeoutException(
          'Timed out after $inletRequestTimeout waiting for the inlet worker '
          'on stream $streamId to add inlet $address; the worker is not '
          'responding',
        );
      },
    );
  }

  /// Remove an inlet from the running isolate
  Future<void> removeInlet(int address) async {
    _inletAddresses.remove(address);
    final requestRecord = _generateRequestID();
    await sendMessage(RemoveInletMessage(address, requestID: requestRecord.$1));
    await requestRecord.$2.future.timeout(
      inletRequestTimeout,
      onTimeout: () {
        // Logged rather than thrown: removal is cleanup, and the address is
        // already out of `_inletAddresses`, so callers have nothing useful to
        // do with the failure beyond knowing the worker is unhealthy.
        logger.warning(
          'Timed out after $inletRequestTimeout waiting for the inlet worker '
          'on stream $streamId to remove inlet $address',
        );
      },
    );
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
      inletAddresses: IList(_inletAddresses),
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
  /// Number of pooled native sample buffers. Sends only block when all
  /// buffers are in flight, giving bounded backpressure without a
  /// per-sample isolate round-trip.
  static const int bufferPoolSize = 8;

  final int _outletAddress;
  final int _channelCount;
  final double _sampleRate;
  late final LSLPushSample _pushFn;
  final Lock _bufferLock = Lock();
  late final List<LSLReusableBuffer<NativeType>> _buffers;

  final StreamController<bool> _consumerPresenceController =
      StreamController<bool>.broadcast();

  /// Emits whenever this outlet gains or loses all of its consumers.
  ///
  /// `false` means liblsl is silently discarding everything pushed here. There
  /// is no other way to find that out — see [ConsumerPresenceMessage].
  Stream<bool> get consumerPresence => _consumerPresenceController.stream;

  /// Latest known consumer presence, or null before the first push.
  bool? get hasConsumers => _hasConsumers;
  bool? _hasConsumers;

  @override
  void _handleConsumerPresence(ConsumerPresenceMessage message) {
    _hasConsumers = message.hasConsumers;
    if (!_consumerPresenceController.isClosed) {
      _consumerPresenceController.add(message.hasConsumers);
    }
  }

  /// Index bookkeeping and the bounded wait. See [OutletBufferPool] for why
  /// the wait is bounded at all.
  final OutletBufferPool _pool = OutletBufferPool(
    size: bufferPoolSize,
    timeout: const Duration(seconds: 5),
  );

  StreamOutletIsolate({
    required super.streamId,
    required super.dataType,
    required super.useBusyWaitInlets,
    required super.useBusyWaitOutlets,
    required super.pollingInterval,
    required this._outletAddress,
    required this._channelCount,
    required this._sampleRate,
    String? isolateDebugName,
  }) : super(
         isolateDebugName: isolateDebugName ?? 'StreamOutletIsolate-$streamId',
       ) {
    _pushFn = LSLMapper().pushSampleMap[_dataTypeToChannelFormat(dataType)]!;
    _buffers = List.generate(
      bufferPoolSize,
      (_) => _pushFn.createReusableBuffer(_channelCount),
      growable: false,
    );
  }

  static LSLChannelFormat _dataTypeToChannelFormat(StreamDataType dataType) {
    switch (dataType) {
      case StreamDataType.float32:
        return LSLChannelFormat.float32;
      case StreamDataType.double64:
        return LSLChannelFormat.double64;
      case StreamDataType.int8:
        return LSLChannelFormat.int8;
      case StreamDataType.int16:
        return LSLChannelFormat.int16;
      case StreamDataType.int32:
        return LSLChannelFormat.int32;
      case StreamDataType.int64:
        return LSLChannelFormat.int64;
      case StreamDataType.string:
        return LSLChannelFormat.string;
    }
  }

  /// How long a send waits for a pooled buffer before giving up.
  ///
  /// See [OutletBufferPool]: the wait used to be unbounded, and one stalled
  /// push then wedged every later send on that stream, permanently.
  Duration get sendTimeout => _pool.timeout;
  set sendTimeout(Duration value) => _pool.timeout = value;

  /// How many consecutive sends have timed out. Zero when healthy.
  int get consecutiveSendTimeouts => _pool.consecutiveTimeouts;

  /// Send data through outlet.
  ///
  /// Completes once the sample has been handed to the outlet isolate (not
  /// once LSL has pushed it). The backing buffer comes from a fixed pool of
  /// [bufferPoolSize]; when every buffer is in flight this blocks until the
  /// worker releases one, which bounds how far senders can run ahead.
  ///
  /// Throws [TimeoutException] if no buffer comes free within [sendTimeout],
  /// rather than blocking this stream's sends indefinitely.
  Future<void> sendData(IList<dynamic> data) async {
    if (stopped) {
      throw StateError('Cannot send data: isolate for $streamId is stopped');
    }
    // The lock preserves send ordering and serializes buffer acquisition.
    await _bufferLock.synchronized(() async {
      final int index;
      final wasTimingOut = _pool.consecutiveTimeouts > 0;
      try {
        index = await _pool.acquire(isStopped: () => stopped);
      } on TimeoutException {
        logger.severe(
          '[$isolateDebugName] Timed out after $sendTimeout waiting for an '
          'outlet buffer on stream $streamId '
          '(${_pool.consecutiveTimeouts} consecutive). The worker has not '
          'released a buffer, so the outlet is not draining — this sample is '
          'dropped.',
        );
        rethrow;
      }
      if (wasTimingOut) {
        logger.warning(
          '[$isolateDebugName] Outlet buffer pool recovered on stream '
          '$streamId',
        );
      }
      _pushFn.listToBuffer(data, _buffers[index].buffer);
      await sendDataMessage(
        DataMessage(_buffers[index].buffer, bufferIndex: index),
      );
    });
  }

  @override
  void _handleBufferReleased(BufferReleasedMessage message) {
    _pool.release(message.bufferIndex);
  }

  @override
  void _failPendingRequests(Object error) {
    super._failPendingRequests(error);
    // Senders parked on buffer acquisition must fail too - covers both
    // clean stop and isolate crash/exit.
    _pool.failAll(error);
  }

  Future<void> recreateOutlet(int address) async {
    final requestRecord = _generateRequestID();
    await sendMessage(
      RecreateOutletMessage(address, requestID: requestRecord.$1),
    );
    await requestRecord.$2.future;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _consumerPresenceController.close();
    for (final buffer in _buffers) {
      // String buffers hold a native UTF-8 allocation per element from the
      // last fill; release those before freeing the buffer itself.
      _pushFn.cleanupBuffer(buffer.buffer, _channelCount);
      buffer.free();
    }
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

  /// Builds the worker's initial inlets, skipping any that cannot be opened.
  ///
  /// One unreachable peer used to abort worker startup for the whole stream:
  /// `Future.wait` surfaces the first error and `InletWorker.initialize` does
  /// not catch it, so the worker never started and *no* peer on that stream was
  /// ever polled. That was masked while inlet creation waited forever instead
  /// of failing — with [inletCreateTimeout] bounding the wait it becomes
  /// reachable, so it has to be handled rather than merely made possible.
  ///
  /// Skipping is safe for the same reason it is in
  /// [InletWorker._handleAddInlet]: discovery re-emits its whole resolved set
  /// each cycle, so a peer that becomes reachable is added later.
  static Future<List<LSLInlet>> _createInlets(
    IsolateWorkerConfig config,
  ) async {
    final inlets = <LSLInlet>[];
    for (final addr in config.inletAddresses!) {
      try {
        inlets.add(await _createInletFromAddr(addr, config.dataType));
      } catch (e) {
        logger.severe(
          '[${config.debugName}] Failed to create initial inlet for address '
          '$addr on stream ${config.streamId}; starting without it: $e',
        );
      }
    }
    return inlets;
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

  /// How long `lsl_open_stream` may block while an inlet is being created.
  ///
  /// The default this replaces is [LSL_FOREVER] — 32000000.0 s, roughly 370
  /// days. These inlets are built with `useIsolates: false`, so `create()` runs
  /// `lsl_open_stream` as a synchronous FFI call on the inlet worker's own
  /// thread. All of a stream's inlets share that one worker, so a peer that has
  /// dropped off the network takes every *other* peer's sample delivery down
  /// with it for the duration of that call.
  ///
  /// That is not hypothetical: on 2026-09-02 a coordinator re-created an inlet
  /// for a participant whose Wi-Fi was in a ~34 s black hole, and stopped
  /// reading heartbeats from the five healthy participants until the OS gave up
  /// on the connect. It then evicted all of them. Against a host that answers
  /// ARP but not TCP there is no OS backstop and the worker never returns.
  ///
  /// Two seconds is chosen against measurement, not intuition. On the
  /// production rig (Raspberry Pi coordinator, iPads over Wi-Fi) a *successful*
  /// open costs a strikingly uniform ~654 ms — nine consecutive samples spanned
  /// 653-664 ms across two different streams. The cost is structural rather
  /// than round-trip-dependent, so the variance to leave headroom for is small;
  /// 2 s is roughly 3x the observed figure and still well under the node
  /// timeout this must not jeopardise.
  ///
  /// (That uniform ~654 ms is worth knowing in its own right: even the happy
  /// path stalls this worker for two thirds of a second per inlet, so admitting
  /// six peers at once costs about four seconds of polling.)
  ///
  /// On expiry `_createDirect` throws [LSLTimeout], which
  /// [InletWorker._handleAddInlet] turns into a skipped inlet that discovery
  /// retries on its next cycle.
  static const double inletCreateTimeout = 2.0;

  static Future<LSLInlet> _createTypedInlet(
    LSLStreamInfo streamInfo,
    StreamDataType dataType,
  ) async {
    switch (dataType) {
      case StreamDataType.float32:
      case StreamDataType.double64:
        return LSLInlet<double>(
          streamInfo,
          chunkSize: 1,
          createTimeout: inletCreateTimeout,
          useIsolates: false,
        );
      case StreamDataType.int8:
      case StreamDataType.int16:
      case StreamDataType.int32:
      case StreamDataType.int64:
        return LSLInlet<int>(
          streamInfo,
          chunkSize: 1,
          createTimeout: inletCreateTimeout,
          useIsolates: false,
        );
      case StreamDataType.string:
        return LSLInlet<String>(
          streamInfo,
          chunkSize: 1,
          createTimeout: inletCreateTimeout,
          useIsolates: false,
        );
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
    Log.forwardTo(config.mainSendPort.send);

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
  ///
  /// `null` means "no estimate yet" — a freshly added inlet has not completed
  /// its first `lsl_time_correction` round trip. That is deliberately distinct
  /// from a known offset of `0.0`: reporting zero would make a receiver compute
  /// a plausible-looking but wrong transit time for the first few seconds of
  /// every new peer.
  ///
  /// Holds the extended estimate (offset *and* its uncertainty) rather than a
  /// bare offset. liblsl's plain `lsl_time_correction` delegates to
  /// `lsl_time_correction_ex` internally, so the error bound comes free with
  /// the same round trip and keeping both in one list avoids a second
  /// index-parallel array to keep in sync with `inlets`.
  late final List<LSLTimeCorrection?> timeCorrections;

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
    timeCorrections = List<LSLTimeCorrection?>.filled(
      inlets.length,
      null,
      growable: true,
    );
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
          await _handleRemoveInlet(message as RemoveInletMessage);
          break;
        case IsolateMessageType.sample:
        case IsolateMessageType.data:
        case IsolateMessageType.recreateOutlet:
        case IsolateMessageType.initialized:
        case IsolateMessageType.requestResponse:
        case IsolateMessageType.bufferReleased:
        case IsolateMessageType.consumerPresence:
          // Not applicable for inlet workers
          break;
      }
      if (message.requestID != null) {
        // logger.finest(
        //   'Inlet worker for stream ${config.streamId} sending response for request ${message.requestID}',
        // );
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
    // Started here rather than at construction so the first pass is measured
    // against the worker actually running, not against isolate spawn.
    _sincePollCompleted
      ..reset()
      ..start();

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
        await inletsLock.synchronized(_pollInletsWorker);
        _notePollCompleted();
        if (buffer.isNotEmpty) {
          await bufferLock.synchronized(() {
            if (buffer.isNotEmpty) {
              config.mainSendPort.send(IsolateDataMessageList.from(buffer));
              buffer.clear();
            }
          });
        }
        // Rate-limited internally (only refreshes every few seconds).
        _updateTimeCorrections();
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
    // A paused worker is not polling by design; leaving the watchdog running
    // would report the pause itself as a stall on resume.
    _sincePollCompleted.stop();
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
    // Stop forwarding logs and release the port so the isolate can exit
    // naturally (the response below still goes out on mainSendPort).
    Log.forwardTo(null);
    receivePort.close();
  }

  Future<void> _handleAddInlet(AddInletMessage message) async {
    logger.finest(
      '[${config.debugName}] Adding inlet for address ${message.address} in stream ${config.streamId}',
    );
    final LSLInlet newInlet;
    try {
      newInlet = await IsolateStreamManager._createInletFromAddr(
        message.address,
        config.dataType,
      );
    } catch (e, st) {
      // Caught rather than rethrown, for two reasons. This isolate is spawned
      // with `errorsAreFatal: true`, so an escaping throw kills the worker and
      // takes every healthy inlet on this stream with it — strictly worse than
      // the unreachable peer we are already handling. And `handleMessage` sends
      // the caller's ResponseMessage only after this returns, so throwing would
      // leave the main isolate's `addInlet` future pending forever.
      //
      // Skipping the inlet is safe: discovery re-emits its whole resolved set
      // every cycle, so a peer that becomes reachable again is retried without
      // any bookkeeping here.
      logger.severe(
        '[${config.debugName}] Failed to create inlet for address '
        '${message.address} in stream ${config.streamId}; skipping it. The '
        'peer is unreachable or refusing the data connection: $e',
        e,
        st,
      );
      return;
    }
    await inletAddRemoveLock.synchronized(() {
      inlets.add(newInlet);
      // Null, not 0.0: this inlet has no clock-offset estimate yet.
      timeCorrections.add(null);
    });
    // Warm up only the inlet just added, not every inlet on the stream. See
    // [_warmTimeCorrectionForNewestInlet] for why the old full sweep here was
    // the expensive half of this bug.
    await _warmTimeCorrectionForNewestInlet();
  }

  Future<void> _handleRemoveInlet(RemoveInletMessage message) async {
    await inletAddRemoveLock.synchronized(() async {
      final index = inlets.indexWhere(
        (inlet) => inlet.streamInfo.streamInfo.address == message.address,
      );
      if (index == -1) {
        logger.warning(
          'No inlet found for address ${message.address} in stream ${config.streamId}',
        );
        return;
      }
      _timeCorrectionSchedule.forget(inlets[index].streamInfo.sourceId);
      try {
        await inlets[index].destroy();
      } catch (e) {
        logger.warning('Error destroying removed inlet: $e');
      }
      inlets.removeAt(index);
      timeCorrections.removeAt(index);
    });
  }

  // Member methods for time corrections and polling
  /// Time since the poll loop last completed a pass over the inlets.
  ///
  /// Restarted on every completed pass; read at the start of the next one, so
  /// what it measures is the gap the *previous* pass left behind.
  final Stopwatch _sincePollCompleted = Stopwatch();

  /// How far behind schedule a poll pass has to fall before it is reported.
  ///
  /// The poll interval is 1–10 ms, so any of these is a large multiple of it.
  /// The floor exists because a coordination stream polling at 1 ms would
  /// otherwise report on ordinary GC pauses and scheduler jitter.
  static const Duration pollStallThreshold = Duration(seconds: 1);

  /// Notes that a poll pass finished, and reports it if the gap was long
  /// enough to have starved the stream.
  ///
  /// This exists because the failure it watches for left no direct trace. When
  /// this worker blocked for 27.6 s inside a native call on 2026-09-02, nothing
  /// in any log said so — the stall had to be reconstructed afterwards from the
  /// *absence* of periodic lines and from heartbeat ages climbing on a peer.
  /// A blocked isolate cannot log while it is blocked, but it can say what
  /// happened the moment it comes back, and that is enough to identify this
  /// class of fault immediately rather than over an evening.
  void _notePollCompleted() {
    if (_sincePollCompleted.isRunning &&
        _sincePollCompleted.elapsed > pollStallThreshold) {
      logger.severe(
        'Inlet worker for stream ${config.streamId} did not poll for '
        '${_sincePollCompleted.elapsed.inMilliseconds}ms '
        '(poll interval ${config.pollingInterval.inMilliseconds}ms, '
        '${inlets.length} inlet(s)). No samples were read from ANY inlet on '
        'this stream during that window; peers will look silent to this node '
        'and may be evicted. This means something blocked the worker isolate '
        '— almost always a native call on an unreachable peer.',
      );
    }
    _sincePollCompleted
      ..reset()
      ..start();
  }

  /// Per-inlet time-correction timeout, in seconds.
  ///
  /// Left at 1.0 deliberately. Shortening it looks attractive - every one of
  /// these calls is paid serially on this worker's thread, so the number
  /// multiplies by the count of unresponsive peers - but an inlet's *first*
  /// correction has to complete a round trip that includes connection setup,
  /// and it does not reliably fit in 0.2 s even on loopback. Cutting it there
  /// makes new peers report "transit unknown" instead of an offset, which is a
  /// correctness regression in exchange for a bound that
  /// [timeCorrectionSweepBudget] and the backoff below already provide.
  static const double timeCorrectionTimeout = 1.0;

  /// Wall-clock budget for one sweep across all inlets.
  ///
  /// This, not the per-call timeout, is what bounds the stall. Without it the
  /// worst case is [timeCorrectionTimeout] times the number of dead peers - six
  /// seconds on a six-participant rig if they all drop at once - during which
  /// no inlet on this stream is polled and every peer looks silent. With it,
  /// a sweep gives up once it has spent long enough and finishes the remaining
  /// inlets on the next tick; corrections refresh every few seconds, so
  /// deferring some of them costs nothing that matters.
  ///
  /// Sits well under the shortest node timeout this must not jeopardise.
  static const Duration timeCorrectionSweepBudget = Duration(
    milliseconds: 1500,
  );

  /// Cap on the exponential backoff, in sweeps.
  ///
  /// At the 5 s sweep interval this is a retry every ~2.5 minutes for a peer
  /// that has never answered — often enough to pick it up again on its own,
  /// rare enough to cost nothing.
  static const int maxTimeCorrectionSkips = 32;

  /// Which inlets a sweep refreshes and when it gives up. See
  /// [TimeCorrectionSchedule] for why this is a separate, testable object.
  final TimeCorrectionSchedule _timeCorrectionSchedule = TimeCorrectionSchedule(
    maxSkips: maxTimeCorrectionSkips,
    sweepBudget: timeCorrectionSweepBudget,
  );

  /// Refreshes one inlet's clock offset, returning the sync to report or null.
  ///
  /// Factored out so the periodic sweep and the single-inlet warm-up in
  /// [_handleAddInlet] share exactly one implementation of the failure
  /// bookkeeping — the backoff below is the only thing keeping an unreachable
  /// peer from costing [timeCorrectionTimeout] out of every sweep forever.
  ///
  /// Returns null when the inlet is in backoff or the call failed. Runs
  /// synchronously despite the `Future`: these inlets are `useIsolates: false`,
  /// so `getTimeCorrectionEx` performs its FFI call before it returns a future
  /// at all, and a failure therefore throws here rather than completing the
  /// future with an error.
  Future<IsolateClockSync?> _refreshTimeCorrection(
    int index,
    double localClock,
  ) async {
    final inlet = inlets[index];
    final sourceId = inlet.streamInfo.sourceId;

    // An inlet in backoff keeps whatever correction it already had: a stale
    // offset is better than none, and staleness is already reported downstream.
    if (_timeCorrectionSchedule.shouldSkip(sourceId)) return null;

    final LSLTimeCorrection correction;
    try {
      // `await` costs a microtask, not a suspension of the FFI call: in direct
      // mode the native work has already finished by the time the future
      // exists. The try/catch has to wrap both anyway, because a failure throws
      // synchronously here rather than completing the future with an error.
      correction = await inlet.getTimeCorrectionEx(
        timeout: timeCorrectionTimeout,
      );
    } catch (e) {
      final backoff = _timeCorrectionSchedule.noteFailure(sourceId);
      logger.warning(
        'Error updating time correction for inlet $index ($sourceId) on '
        'stream ${config.streamId}: $e - '
        '${_timeCorrectionSchedule.failuresFor(sourceId)} consecutive '
        'failure(s), skipping the next $backoff sweep(s)',
      );
      return null;
    }

    if (_timeCorrectionSchedule.noteSuccess(sourceId)) {
      logger.info(
        'Time correction recovered for inlet $index ($sourceId) on stream '
        '${config.streamId}',
      );
    }
    timeCorrections[index] = correction;

    // Read once, here, and report what it said. liblsl clears the flag on read,
    // so polling it anywhere else would consume the one notification this
    // estimate gets and silently drop it.
    bool clockReset = false;
    try {
      clockReset = inlet.wasClockResetSync();
    } catch (e) {
      logger.warning('Error reading clock-reset flag for inlet $index: $e');
    }

    return IsolateClockSync(
      sourceId: sourceId,
      offset: correction.offset,
      remoteTime: correction.remoteTime,
      uncertainty: correction.uncertainty,
      localClock: localClock,
      clockReset: clockReset,
    );
  }

  Future<void> _updateTimeCorrections([
    int minTimeSinceLastUpdate = 5000,
  ]) async {
    await timeCorrectionsLock.synchronized(() async {
      if (!lastTimeCorrectionUpdate.isRunning ||
          lastTimeCorrectionUpdate.elapsedMilliseconds <
              minTimeSinceLastUpdate) {
        return; // Limit updates to every 5 seconds
      }
      // Reset in a `finally`. It used to run only on the success path, so a
      // throw anywhere below left the stopwatch un-reset and every subsequent
      // tick re-ran the full sweep - turning one unreachable peer into a
      // permanent, per-tick stall instead of a five-second one.
      try {
        final localClock = LSL.localClock();
        final syncs = <IsolateClockSync>[];
        final sweep = _timeCorrectionSchedule.beginSweep();
        for (int i = 0; i < inlets.length; i++) {
          final sync = await _refreshTimeCorrection(i, localClock);
          if (sync != null) syncs.add(sync);
          if (sweep.isExhausted && i + 1 < inlets.length) {
            logger.warning(
              'Time-correction sweep for stream ${config.streamId} used its '
              '${timeCorrectionSweepBudget.inMilliseconds}ms budget after '
              '${i + 1} of ${inlets.length} inlet(s) '
              '(${sweep.elapsed.inMilliseconds}ms); deferring the rest to the '
              'next sweep so polling is not starved',
            );
            break;
          }
        }
        if (syncs.isNotEmpty) {
          config.mainSendPort.send(IsolateClockSyncList.from(syncs));
        }
        logger.finer('Updated time corrections for stream ${config.streamId}');
      } finally {
        lastTimeCorrectionUpdate.reset();
      }
    });
  }

  /// Gives a freshly added inlet a clock offset without sweeping the others.
  ///
  /// The warm-up used to be `unawaited(_updateTimeCorrections(0))`: a full
  /// sweep, rate limit bypassed, on the peer-admission path. Because these
  /// calls are synchronous and serial, admitting one peer paid the timeout for
  /// every *other* unreachable peer too, and `unawaited` bought nothing because
  /// a blocking call cannot be made non-blocking by not awaiting it.
  ///
  /// Touching only the new inlet keeps the reason for the warm-up - a new peer
  /// should not spend the first refresh window reporting "transit unknown" -
  /// while bounding its cost to a single [timeCorrectionTimeout] against a peer
  /// whose `lsl_open_stream` has just succeeded, so it is known reachable.
  Future<void> _warmTimeCorrectionForNewestInlet() async {
    await timeCorrectionsLock.synchronized(() async {
      if (inlets.isEmpty) return;
      final sync = await _refreshTimeCorrection(
        inlets.length - 1,
        LSL.localClock(),
      );
      if (sync != null) {
        config.mainSendPort.send(IsolateClockSyncList.from([sync]));
      }
    });
  }

  /// Upper bound of samples drained per inlet per tick so one noisy inlet
  /// can't starve the others or the flush.
  static const int _maxSamplesPerInletPerTick = 100;

  // Inlet-specific polling using member variables instead of parameters.
  // Fully synchronous: runs to completion without yielding, so buffer access
  // needs no lock here (flush sites still serialize via bufferLock).
  void _pollInletsWorker() {
    // Both clock reads are hoisted out of the drain loop: this method runs to
    // completion without yielding, so every sample it takes belongs to the same
    // tick, and one reading per tick describes them all. Previously
    // `DateTime.now()` ran once per sample, so this is a net reduction in
    // syscalls on the hot path, not an addition.
    final tickWallClock = DateTime.now();
    final tickLocalClock = LSL.localClock();

    for (int i = 0; i < inlets.length; i++) {
      final inlet = inlets[i];
      final correction = timeCorrections[i];
      try {
        // Drain the inlet instead of taking a single sample, otherwise a
        // producer faster than the poll rate builds an ever-growing backlog.
        for (int n = 0; n < _maxSamplesPerInletPerTick; n++) {
          final sample = inlet.pullSampleSync(timeout: 0.0);
          if (sample.isEmpty) break;

          buffer.add(
            IsolateDataMessage(
              streamId: config.streamId,
              timestamp: tickWallClock,
              data: sample.data,
              sourceId: inlet.streamInfo.sourceId,
              lslTimestamp: sample.timestamp,
              lslTimeCorrection: correction?.offset,
              lslTimeCorrectionUncertainty: correction?.uncertainty,
              localClock: tickLocalClock,
            ),
          );
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

        await inletsLock.synchronized(_pollInletsWorker);
        _notePollCompleted();

        await bufferLock.synchronized(() {
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
        case IsolateMessageType.sample:
        case IsolateMessageType.addInlet:
        case IsolateMessageType.removeInlet:
        case IsolateMessageType.initialized:
        case IsolateMessageType.requestResponse:
        case IsolateMessageType.bufferReleased:
        case IsolateMessageType.consumerPresence:
          // Not applicable for outlet workers
          break;
      }
      if (message.requestID != null) {
        // logger.finest(
        //   'Outlet worker for stream ${config.streamId} sending response for request ${message.requestID}',
        // );
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
    // A fresh outlet starts with no subscribers, and comparing against the old
    // one's state would either report a loss that is just the rebuild, or
    // suppress the first real report. `destroy()` nulls the handle, so a check
    // landing mid-rebuild throws and is swallowed rather than touching freed
    // memory.
    _lastConsumerPresence = null;
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
    _startConsumerChecks();
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
    // A paused outlet is not expected to have traffic, so consumer loss while
    // paused is neither surprising nor actionable.
    _stopConsumerChecks();
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
    // Cleared so the first check after resuming reports the current state
    // rather than comparing against what was true before the pause.
    _lastConsumerPresence = null;
    _startConsumerChecks();
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
    // Before the outlet is destroyed below: a check that fired afterwards would
    // touch a freed handle.
    _stopConsumerChecks();
    if (completer != null && !completer!.isCompleted) {
      completer?.complete();
    }
    // We own the streaminfo (see _recreateOutlet) - the main isolate only
    // passed its address, so it must be freed here or it leaks.
    outlet.streamInfo.destroy();
    await outlet.destroy();
    logger.info('Destroyed outlet for stream ${config.streamId}');
    // Stop forwarding logs and release the port so the isolate can exit
    // naturally (the response below still goes out on mainSendPort).
    Log.forwardTo(null);
    receivePort.close();
  }

  /// Consumer presence as of the last push, or null before the first one.
  ///
  /// Only transitions are reported: an outlet is legitimately consumer-less
  /// between creation and the first subscriber, and saying so once per sample
  /// would be noise rather than signal.
  bool? _lastConsumerPresence;

  void _handleData(DataMessage message) {
    try {
      if (running && !paused) {
        outlet.pushSamplePointerSync(message.payload);
      }
    } catch (e, st) {
      // Logged rather than rethrown. `handleMessage` is async and its future is
      // dropped by `receivePort.listen`, so a throw here would surface only as
      // an uncaught async error — and with errorsAreFatal it would take the
      // whole worker down, turning one bad sample into a dead stream.
      logger.severe(
        'Outlet worker for stream ${config.streamId} failed to push a '
        'sample: $e',
        e,
        st,
      );
    } finally {
      // Always recycle the buffer, even when the sample was dropped
      // (paused/stopped) or the push threw, or the pool on the main isolate
      // drains permanently. The comment used to say "always" while the code
      // only managed it on the success path.
      config.mainSendPort.send(BufferReleasedMessage(message.bufferIndex));
    }
  }

  /// How often consumer presence is sampled.
  ///
  /// Deliberately time-based rather than per-push. `lsl_have_consumers` takes
  /// `send_buffer::consumers_mut_` — the *same* mutex `push_sample` takes — so
  /// checking on every sample doubles lock traffic on the send hot path, and
  /// contends it hardest exactly when connections are churning. It would also
  /// scale with sample rate for no benefit: a 1000 Hz EEG outlet would pay a
  /// thousand times over per second to detect a condition that persists for
  /// seconds at minimum, and permanently in the case this was built for.
  ///
  /// One second is far finer than the [CoordinationSessionConfig.nodeTimeout]
  /// it needs to beat, and costs one leaf FFI call and one uncontended mutex
  /// per outlet per second.
  ///
  /// A timer also covers what per-push checking could not: an outlet that has
  /// gone quiet still reports that nobody is listening.
  static const Duration consumerCheckInterval = Duration(seconds: 1);

  Timer? _consumerCheckTimer;

  void _startConsumerChecks() {
    _consumerCheckTimer?.cancel();
    _consumerCheckTimer = Timer.periodic(consumerCheckInterval, (_) {
      if (running && !paused) _reportConsumerPresence();
    });
  }

  void _stopConsumerChecks() {
    _consumerCheckTimer?.cancel();
    _consumerCheckTimer = null;
  }

  /// Tells the main isolate when this outlet gains or loses its consumers.
  void _reportConsumerPresence() {
    final bool present;
    try {
      present = outlet.hasConsumersSync();
    } catch (_) {
      // Never let diagnostics break the send path.
      return;
    }
    if (present == _lastConsumerPresence) return;
    _lastConsumerPresence = present;
    if (!present) {
      logger.severe(
        'Outlet for stream ${config.streamId} has NO consumers; samples '
        'pushed now are silently discarded by liblsl',
      );
    } else {
      logger.info('Outlet for stream ${config.streamId} has consumers again');
    }
    config.mainSendPort.send(ConsumerPresenceMessage(present));
  }
}
