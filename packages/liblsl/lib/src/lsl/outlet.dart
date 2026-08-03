import 'dart:async';
import 'dart:ffi';

import 'package:liblsl/lsl.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
import 'package:liblsl/src/lsl/lsl_io_mixin.dart';
import 'dart:typed_data';

import 'package:liblsl/src/lsl/push_sample.dart';
import 'package:liblsl/src/ffi/bindings_ex.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/util/chunk_buffer.dart';

/// A unified LSL outlet that supports both isolated and direct execution modes.
///
/// **Execution Modes:**
/// - `useIsolates: true` (default): Thread-safe, async-only operations
/// - `useIsolates: false`: Direct FFI calls, supports both sync and async
///    This will run in whichever isolate it is created in, and may perform
///    blocking operations.
///   ! You must ensure thread safety yourself when using this mode.
///
/// **Sync Methods:**
/// Sync methods (ending in `Sync`) are only available when `useIsolates: false`.
/// They provide maximum timing precision by eliminating async scheduling overhead.
///
/// ```dart
/// // For thread safety (default)
/// final outlet = await LSL.createOutlet(streamInfo: info);
/// await outlet.pushSample([1.0, 2.0]);
///
/// // For timing precision
/// final outlet = await LSL.createOutlet(streamInfo: info, useIsolates: false);
/// outlet.pushSampleSync([1.0, 2.0]); // Zero async overhead
/// ```
class LSLOutlet extends LSLObj with LSLIOMixin, LSLExecutionMixin {
  /// The [LSLStreamInfo] stream information for this outlet.
  @override
  final LSLStreamInfo streamInfo;

  /// Whether to use isolates for thread safety.
  /// Default is true, which means it will use isolates for thread safety.
  final bool _useIsolates;

  late final bool _managed;

  /// Chunk size in samples for transmission.
  /// 0 creates a chunk for each push operation.
  @override
  final int chunkSize;

  /// Maximum buffer size in seconds.
  /// This is how many seconds of samples are stored in the outlet's buffer.
  /// Default is 360 seconds (6 minutes).
  /// The unit changes when [transportOptions] contains
  /// [LSLTransportOptions.bufsizeInSamples] (samples) or
  /// [LSLTransportOptions.bufsizeInThousandths] (value * 0.001).
  @override
  final int maxBuffer;

  /// Transport flags applied at creation via `lsl_create_outlet_ex`.
  ///
  /// An empty set (the default) uses the legacy `lsl_create_outlet` call and
  /// changes no behavior.
  ///
  /// [LSLTransportOptions.syncBlocking] makes every push write the sample
  /// buffer directly to all connected consumers, blocking until the data has
  /// been handed to the OS for each of them. This lowers CPU usage for
  /// high-bandwidth streams but pushes block for as long as the slowest
  /// consumer's socket needs — in direct mode that stalls the calling
  /// isolate. It is incompatible with string-format streams, only one thread
  /// may push at a time, and pushthrough/chunking flags are ignored.
  final Set<LSLTransportOptions> transportOptions;

  /// Push function for converting Dart types to raw data.
  /// This is initialized based on the [streamInfo] type.
  /// It provides methods to allocate buffers and push samples.
  late final LSLPushSample _pushFn;

  LSLPushSample get nativePush => _pushFn;

  /// Chunk push function; resolved lazily on first chunk push so that
  /// string-format outlets (which have no chunk push) keep working for
  /// single-sample use.
  LSLPushChunk? _pushChunkFn;

  /// Reusable native chunk buffer; lazily allocated on first chunk push.
  LSLChunkBuffer? _chunkBuffer;

  /// Guards the shared chunk buffer against concurrent isolated chunk ops.
  bool _chunkOpInFlight = false;

  /// Buffer for storing sample data before pushing.
  /// Null until [create]/[createFromPointer] has set up the push buffer, so
  /// [destroy] stays safe when creation failed part-way.
  Pointer<NativeType>? _buffer;

  Pointer<NativeType> get _bufferBang =>
      _buffer ?? (throw LSLException('Outlet buffer not initialized'));

  /// Whether the outlet is created using isolates or direct FFI calls.
  @override
  bool get useIsolates => _useIsolates;

  /// The underlying lsl_outlet pointer.
  lsl_outlet? _outlet;

  lsl_outlet get outlet => _outletBang;

  // Force-unwrap getters (avoiding ! everywhere)
  // These throw LSLException if the resource hasn't been initialized

  /// The underlying lsl_outlet pointer.
  lsl_outlet get _outletBang =>
      _outlet ?? (throw LSLException('Outlet not initialized'));

  // Isolate resources (when using isolates)

  /// The isolate manager for handling async operations.
  LSLOutletIsolateManager? _isolateManager;

  /// The isolate manager for handling async operations.
  LSLOutletIsolateManager get _isolateManagerBang =>
      _isolateManager ??
      (throw LSLException('Isolate manager not initialized'));

  /// Creates a new LSLOutlet instance.
  /// **Parameters:**
  /// - [streamInfo]: The stream information to create the outlet for.
  /// - [chunkSize]: Chunk size in samples for transmission (default: 0).
  /// - [maxBuffer]: Maximum buffer size in seconds (default: 360).
  /// - [useIsolates]: Whether to use isolates for thread safety (default: true)
  ///   This is recommended for most use cases to ensure thread safety,
  ///   if you choose to use direct mode (`useIsolates: false`), you most likely
  ///   will want to still run this in an isolate to avoid blocking the main
  ///   isolate.
  LSLOutlet(
    this.streamInfo, {
    this.chunkSize = 0,
    this.maxBuffer = 360,
    this.transportOptions = const {},
    bool useIsolates = true,
  }) : _useIsolates = useIsolates;

  // Method delegates

  /// Creates the outlet based on the execution mode
  /// This method must be called before using the outlet.
  /// It initializes the outlet and prepares it for pushing samples.
  /// **Execution:**
  /// - Isolated mode: Uses [LSLOutletIsolateManager] for async operations
  ///   [_createIsolated]
  /// - Direct mode: Uses FFI calls directly
  ///   [_createDirect]
  /// **Returns:** A [LSLOutlet] instance ready for fluid interface
  /// **See also:** [destroy] to clean up resources
  @override
  Future<LSLOutlet> create() async {
    validateTransportOptions(transportOptions, streamInfo);
    _managed = true;
    super.create();
    // Create the outlet based on the execution mode
    return _useIsolates ? _createIsolated() : _createDirect();
  }

  /// Validates a transport-option set against a stream's channel format.
  ///
  /// **Throws:** [ArgumentError] for combinations liblsl does not support.
  static void validateTransportOptions(
    Set<LSLTransportOptions> options,
    LSLStreamInfo streamInfo,
  ) {
    if (options.contains(LSLTransportOptions.syncBlocking) &&
        streamInfo.channelFormat == LSLChannelFormat.string) {
      throw ArgumentError(
        'LSLTransportOptions.syncBlocking is incompatible with '
        'string/variable-length channel formats',
      );
    }
    if (options.contains(LSLTransportOptions.bufsizeInSamples) &&
        options.contains(LSLTransportOptions.bufsizeInThousandths)) {
      throw ArgumentError(
        'bufsizeInSamples and bufsizeInThousandths are mutually exclusive '
        'interpretations of maxBuffer',
      );
    }
  }

  /// Creates an outlet from an existing lsl_outlet pointer.
  /// **Parameters:**
  /// - [pointer]: The existing lsl_outlet pointer.
  /// **Returns:** A [LSLOutlet] instance wrapping the existing pointer.
  /// **Throws:** [LSLException] if outlet creation fails or if
  /// `useIsolates: true`.
  Future<LSLOutlet> createFromPointer(lsl_outlet pointer) async {
    if (created) {
      throw LSLException('Outlet already created');
    }
    if (useIsolates) {
      throw LSLException('Cannot create from pointer in isolated mode');
    }
    _managed = false;
    _outlet = pointer;
    super.create();
    _setupPushBuffer();
    return this;
  }

  /// Destroys the outlet and cleans up resources.
  /// You can no longer use the outlet after calling this method.
  @override
  Future<void> destroy() async {
    if (destroyed || !created) {
      return; // Already destroyed
    }
    super.destroy();
    // Clean up resources
    if (_useIsolates) {
      await _isolateManagerBang.sendMessage(
        LSLMessage(LSLMessageType.destroy, {}),
      );
      _isolateManagerBang.dispose();
    } else if (_outlet != null && _managed) {
      try {
        lsl_destroy_outlet(_outletBang);
      } catch (e) {
        // Ignore errors during destroy, as the outlet may already be destroyed
      }
    }
    _outlet = null;
    _isolateManager = null;
    final buffer = _buffer;
    _buffer = null;
    if (buffer != null && !buffer.isNullPointer) {
      // Release any per-element allocations (string samples) still held.
      _pushFn.cleanupBuffer(buffer, streamInfo.channelCount);
      buffer.free();
    }
    _chunkBuffer?.free();
    _chunkBuffer = null;
  }

  /// Waits for a consumer (e.g. LabRecorder, another inlet) to connect to the
  /// outlet.
  ///
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 60.0)
  ///
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///
  /// **Returns:** `true` if a consumer is found, `false` if timeout occurs.
  ///
  /// **See also:** [waitForConsumerSync] for zero-overhead direct calls
  Future<bool> waitForConsumer({double timeout = 60.0}) => _useIsolates
      ? _waitForConsumerIsolated(timeout)
      : Future.value(_waitForConsumerDirect(timeout));

  /// Synchronously waits for a consumer to connect to the outlet.
  ///
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  ///
  /// This provides maximum timing precision by eliminating all async overhead.
  ///
  /// **Example:**
  /// ```dart
  /// final outlet = await LSL.createOutlet(streamInfo: info, useIsolates: false);
  ///
  /// // High-precision consumer detection
  /// if (outlet.waitForConsumerSync(timeout: 1.0)) {
  ///   outlet.pushSampleSync([1.0, 2.0]);
  /// }
  /// ```
  /// **Returns:** `true` if a consumer is found, `false` if timeout occurs.
  /// **See also:** [waitForConsumer] for async operations
  /// **Throws:** [LSLException] if `useIsolates: true`.
  bool waitForConsumerSync({double timeout = 60.0}) =>
      requireDirect(() => _waitForConsumerDirect(timeout));

  /// Pushes a sample to the outlet.
  ///
  /// **Parameters:**
  /// - [data]: List of values that will be used to initialize the sample.
  ///   The type should match the channel format and length should match
  ///   the channel count.
  ///
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///
  /// **Returns:** Error code (0 = success).
  ///
  /// **See also:** [pushSampleSync] for zero-overhead direct calls
  Future<int> pushSample(Iterable<dynamic> data) => _useIsolates
      ? _pushSampleIsolated(data)
      : Future.value(_pushSampleDirect(data));

  /// Synchronously pushes a sample to the outlet.
  ///
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  ///
  /// This provides maximum timing precision by eliminating all async overhead.
  /// Ideal for high-frequency data streaming or when precise timing is critical.
  ///
  /// **Example:**
  /// ```dart
  /// final outlet = await LSL.createOutlet(streamInfo: info, useIsolates: false);
  ///
  /// // High-precision sampling loop
  /// while (streaming) {
  ///   final data = generateSample();
  ///   outlet.pushSampleSync(data); // Zero async overhead
  /// }
  /// ```
  /// **Returns:** Error code (0 = success).
  /// **See also:** [pushSample] for async operations
  /// **Throws:** [LSLException] if `useIsolates: true` or data validation fails.
  int pushSampleSync(Iterable<dynamic> data) =>
      requireDirect(() => _pushSampleDirect(data));

  /// Pushes a chunk of samples to the outlet.
  ///
  /// **Parameters:**
  /// - [samples]: One list of `channelCount` values per sample.
  /// - [timestamp]: Optional capture time of the *last* sample (0.0/null =
  ///   now); earlier samples are spaced backwards by the sampling rate.
  /// - [timestamps]: Optional per-sample timestamps (length must equal
  ///   `samples.length`); mutually exclusive with [timestamp].
  ///
  /// Chunk transfer trades per-sample latency for throughput: one native
  /// call (and, with a matching `chunkSize`, one network write) moves the
  /// whole block. Not available for string streams.
  ///
  /// **Returns:** Error code (0 = success).
  ///
  /// **See also:** [pushChunkSync], [pushChunkTyped]
  Future<int> pushChunk(
    List<List<dynamic>> samples, {
    double? timestamp,
    List<double>? timestamps,
  }) => _useIsolates
      ? _pushChunkIsolated(samples, timestamp, timestamps)
      : Future.value(_pushChunkDirect(samples, timestamp, timestamps));

  /// Synchronously pushes a chunk of samples to the outlet.
  ///
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [pushChunk] for parameter semantics.
  int pushChunkSync(
    List<List<dynamic>> samples, {
    double? timestamp,
    List<double>? timestamps,
  }) => requireDirect(() => _pushChunkDirect(samples, timestamp, timestamps));

  /// Pushes a chunk from a flat [TypedData] buffer (fast path).
  ///
  /// [data] must be the typed list matching the stream's channel format
  /// (e.g. [Float32List] for float32) holding `sampleCount * channelCount`
  /// values in sample-major order. This copies with a single memmove instead
  /// of per-element conversion. See [pushChunk] for timestamp semantics.
  ///
  /// **Returns:** Error code (0 = success).
  Future<int> pushChunkTyped(
    TypedData data, {
    double? timestamp,
    Float64List? timestamps,
  }) => _useIsolates
      ? _pushChunkTypedIsolated(data, timestamp, timestamps)
      : Future.value(_pushChunkTypedDirect(data, timestamp, timestamps));

  /// Synchronously pushes a chunk from a flat [TypedData] buffer.
  ///
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [pushChunkTyped].
  int pushChunkTypedSync(
    TypedData data, {
    double? timestamp,
    Float64List? timestamps,
  }) => requireDirect(() => _pushChunkTypedDirect(data, timestamp, timestamps));

  /// Checks if consumers are currently connected to the outlet.
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  /// - Direct mode: Immediate FFI call wrapped in Future
  /// **Returns:** `true` if consumers are connected, `false` otherwise.
  Future<bool> hasConsumers() => _useIsolates
      ? _hasConsumersIsolated()
      : Future.value(lslHaveConsumersFast(_outletBang) != 0);

  /// Synchronously checks if consumers are currently connected to the outlet.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// **Returns:** `true` if consumers are connected, `false` otherwise.
  bool hasConsumersSync() =>
      requireDirect(() => lslHaveConsumersFast(_outletBang) != 0);

  /// Sets up the push buffer for sample data.
  /// This allocates memory based on the channel count and initializes the push
  /// function.
  /// **Throws:** [LSLException] if buffer allocation fails.
  void _setupPushBuffer() {
    // Initialize the push function and buffer
    _pushFn = LSLMapper().streamPush(streamInfo);
    final buffer = _pushFn.allocBuffer(streamInfo.channelCount);
    if (buffer.isNullPointer && _pushFn is! LSLPushSampleVoid) {
      throw LSLException('Failed to allocate memory for buffer');
    }
    _buffer = buffer;
  }

  /// Creates the outlet directly using FFI calls.
  /// This is used when `useIsolates: false`.
  /// **Returns:** A [LSLOutlet] instance ready for fluid interface
  /// **Throws:** [LSLException] if outlet creation fails.
  Future<LSLOutlet> _createDirect() async {
    _setupPushBuffer();
    // Create the outlet using FFI; the legacy call is kept for an empty
    // option set so default behavior is byte-for-byte unchanged.
    _outlet = transportOptions.isEmpty
        ? lsl_create_outlet(streamInfo.streamInfo, chunkSize, maxBuffer)
        : lslCreateOutletFlags(
            streamInfo.streamInfo,
            chunkSize,
            maxBuffer,
            transportOptions.nativeFlags,
          );
    if (_outlet == null || _outletBang.isNullPointer) {
      throw LSLException('Failed to create outlet');
    }

    return this;
  }

  /// Creates the outlet in an isolated environment.
  /// This is used when `useIsolates: true`.
  /// **Returns:** A [LSLOutlet] instance ready for fluid interface
  /// **Throws:** [LSLException] if outlet creation fails.
  Future<LSLOutlet> _createIsolated() async {
    // Initialize the isolate manager
    _isolateManager = LSLOutletIsolateManager();
    await _isolateManagerBang.init();

    _setupPushBuffer();

    // Send message to create outlet in the isolate
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.createOutlet, {
        'streamInfo': LSLSerializer.serializeStreamInfo(streamInfo),
        'chunkSize': chunkSize,
        'maxBuffer': maxBuffer,
        'transportFlags': transportOptions.nativeFlags,
      }),
    );

    if (!response.success) {
      throw LSLException('Error creating outlet: ${response.error}');
    }

    return this;
  }

  /// Waits for a consumer in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds
  /// **Returns:** `true` if a consumer is found, `false` if timeout occurs.
  /// **Throws:** [LSLException] if waiting for consumer fails.
  Future<bool> _waitForConsumerIsolated(double timeout) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.waitForConsumer, {'timeout': timeout}),
    );

    if (!response.success) {
      throw LSLTimeout('No consumer found within $timeout seconds');
    }

    return response.result as bool;
  }

  /// Waits for a consumer directly using FFI calls.
  /// This is used when `useIsolates: false`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds
  /// **Returns:** `true` if a consumer is found, `false` if timeout occurs.
  bool _waitForConsumerDirect(double timeout) {
    final result = lsl_wait_for_consumers(_outletBang, timeout);
    return result != 0;
  }

  /// Pushes a sample in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Parameters:**
  /// - [data]: List of values to push
  /// **Returns:** Error code (0 = success).
  /// **Throws:** [LSLException] if pushing the sample fails.
  Future<int> _pushSampleIsolated(Iterable<dynamic> data) async {
    _validateSampleData(data);

    final buffer = _bufferBang;
    // Set the sample data in the buffer
    _pushFn.listToBuffer(data, buffer);

    try {
      final response = await _isolateManagerBang.sendMessage(
        LSLMessage(LSLMessageType.pushSample, {'pointerAddr': buffer.address}),
      );

      if (!response.success) {
        throw LSLException('Error pushing sample: ${response.error}');
      }

      return response.result as int;
    } finally {
      // The worker has finished reading the buffer once the response arrives,
      // so per-element allocations (string samples) can be released here.
      _pushFn.cleanupBuffer(buffer, streamInfo.channelCount);
    }
  }

  /// Pushes a sample directly using FFI calls.
  /// This is used when `useIsolates: false`.
  /// **Parameters:**
  /// - [data]: List of values to push
  /// **Returns:** Error code (0 = success).
  /// **Throws:** [LSLException] if pushing the sample fails.
  int _pushSampleDirect(Iterable<dynamic> data) {
    _validateSampleData(data);

    final buffer = _bufferBang;
    // Set the sample data in the buffer
    _pushFn.listToBuffer(data, buffer);

    try {
      // Push the sample (liblsl copies the data before returning)
      final result = _pushFn(_outletBang, buffer);
      if (LSLObj.error(result)) {
        throw LSLException('Error pushing sample: $result');
      }
      return result;
    } finally {
      _pushFn.cleanupBuffer(buffer, streamInfo.channelCount);
    }
  }

  /// Writes [data] into the outlet's push buffer and returns the pointer.
  ///
  /// **Note:** for string streams the per-element allocations made here are
  /// only released on the next push/cleanup or in [destroy]; prefer
  /// [pushSample]/[pushSampleSync] for string data.
  Pointer<NativeType> dataToBufferPointer(Iterable<dynamic> data) {
    _validateSampleData(data);
    // Set the sample data in the buffer
    _pushFn.listToBuffer(data, _bufferBang);
    return _bufferBang;
  }

  int pushSamplePointerSync(Pointer<NativeType> pointer) {
    return _pushFn(_outletBang, pointer);
  }

  /// Resolves the chunk push function (throws [LSLException] for string
  /// streams, which have no fixed-size chunk representation).
  LSLPushChunk _ensurePushChunkFn() =>
      _pushChunkFn ??= LSLMapper().streamPushChunk(streamInfo);

  /// Lazily allocates/grows the reusable chunk buffer.
  LSLChunkBuffer _ensureChunkBuffer(int samples) {
    final pushFn = _ensurePushChunkFn();
    final buf = _chunkBuffer ??= LSLChunkBuffer(
      streamInfo.channelCount,
      pushFn.allocBuffer,
    );
    buf.ensureCapacity(samples);
    return buf;
  }

  /// Validates list-form chunk data; returns the sample count.
  int _validateChunkLists(
    List<List<dynamic>> samples,
    double? timestamp,
    List<double>? timestamps,
  ) {
    if (samples.isEmpty) {
      throw ArgumentError('Chunk must contain at least one sample');
    }
    if (timestamp != null && timestamps != null) {
      throw ArgumentError('timestamp and timestamps are mutually exclusive');
    }
    final channels = streamInfo.channelCount;
    for (final sample in samples) {
      if (sample.length != channels) {
        throw ArgumentError(
          'Each sample must have $channels values (got ${sample.length})',
        );
      }
    }
    if (timestamps != null && timestamps.length != samples.length) {
      throw ArgumentError(
        'timestamps length (${timestamps.length}) must equal sample count '
        '(${samples.length})',
      );
    }
    return samples.length;
  }

  /// Validates typed-data chunk input; returns the sample count.
  int _validateChunkTyped(
    TypedData data,
    double? timestamp,
    Float64List? timestamps,
  ) {
    final pushFn = _ensurePushChunkFn();
    if (!pushFn.typedDataMatches(data)) {
      throw ArgumentError(
        'Expected ${pushFn.typedDataName} for '
        '${streamInfo.channelFormat} streams, got ${data.runtimeType}',
      );
    }
    if (timestamp != null && timestamps != null) {
      throw ArgumentError('timestamp and timestamps are mutually exclusive');
    }
    final channels = streamInfo.channelCount;
    final elements = data.lengthInBytes ~/ data.elementSizeInBytes;
    if (elements == 0 || elements % channels != 0) {
      throw ArgumentError(
        'Data length ($elements) must be a non-zero multiple of the channel '
        'count ($channels)',
      );
    }
    final sampleCount = elements ~/ channels;
    if (timestamps != null && timestamps.length != sampleCount) {
      throw ArgumentError(
        'timestamps length (${timestamps.length}) must equal sample count '
        '($sampleCount)',
      );
    }
    return sampleCount;
  }

  /// Pushes the filled chunk buffer via the appropriate native call.
  int _pushChunkBuffer(
    LSLPushChunk pushFn,
    LSLChunkBuffer buf,
    int sampleCount,
    double? timestamp,
    List<double>? timestamps,
  ) {
    final elements = sampleCount * streamInfo.channelCount;
    int result;
    if (timestamps != null) {
      final ts = buf.timestamps;
      for (int i = 0; i < sampleCount; i++) {
        ts[i] = timestamps[i];
      }
      result = pushFn.pushWithTimestamps(_outletBang, buf.data, elements, ts);
    } else {
      result = pushFn.pushWithTimestamp(
        _outletBang,
        buf.data,
        elements,
        timestamp ?? 0.0,
      );
    }
    if (LSLObj.error(result)) {
      throw LSLException('Error pushing chunk: $result');
    }
    return result;
  }

  int _pushChunkDirect(
    List<List<dynamic>> samples,
    double? timestamp,
    List<double>? timestamps,
  ) {
    final sampleCount = _validateChunkLists(samples, timestamp, timestamps);
    final pushFn = _ensurePushChunkFn();
    final buf = _ensureChunkBuffer(sampleCount);
    pushFn.flatListToBuffer(samples.expand((s) => s), buf.data);
    return _pushChunkBuffer(pushFn, buf, sampleCount, timestamp, timestamps);
  }

  int _pushChunkTypedDirect(
    TypedData data,
    double? timestamp,
    Float64List? timestamps,
  ) {
    final sampleCount = _validateChunkTyped(data, timestamp, timestamps);
    final pushFn = _ensurePushChunkFn();
    final buf = _ensureChunkBuffer(sampleCount);
    pushFn.typedDataToBuffer(
      data,
      buf.data,
      sampleCount * streamInfo.channelCount,
    );
    return _pushChunkBuffer(pushFn, buf, sampleCount, timestamp, timestamps);
  }

  Future<int> _pushChunkIsolated(
    List<List<dynamic>> samples,
    double? timestamp,
    List<double>? timestamps,
  ) async {
    final sampleCount = _validateChunkLists(samples, timestamp, timestamps);
    final pushFn = _ensurePushChunkFn();
    final buf = _ensureChunkBuffer(sampleCount);
    pushFn.flatListToBuffer(samples.expand((s) => s), buf.data);
    return _sendPushChunkMessage(buf, sampleCount, timestamp, timestamps);
  }

  Future<int> _pushChunkTypedIsolated(
    TypedData data,
    double? timestamp,
    Float64List? timestamps,
  ) async {
    final sampleCount = _validateChunkTyped(data, timestamp, timestamps);
    final pushFn = _ensurePushChunkFn();
    final buf = _ensureChunkBuffer(sampleCount);
    pushFn.typedDataToBuffer(
      data,
      buf.data,
      sampleCount * streamInfo.channelCount,
    );
    return _sendPushChunkMessage(buf, sampleCount, timestamp, timestamps);
  }

  /// Sends the filled chunk buffer's addresses to the worker isolate.
  ///
  /// The buffer is shared memory: the request/response protocol guarantees
  /// the worker has finished reading before the buffer is reused, and
  /// [_chunkOpInFlight] converts concurrent misuse into an error instead of
  /// silent data corruption.
  Future<int> _sendPushChunkMessage(
    LSLChunkBuffer buf,
    int sampleCount,
    double? timestamp,
    List<double>? timestamps,
  ) async {
    if (_chunkOpInFlight) {
      throw LSLException('Concurrent chunk operation on the same outlet');
    }
    _chunkOpInFlight = true;
    try {
      int? tsAddr;
      if (timestamps != null) {
        final ts = buf.timestamps;
        for (int i = 0; i < sampleCount; i++) {
          ts[i] = timestamps[i];
        }
        tsAddr = ts.address;
      }
      final response = await _isolateManagerBang.sendMessage(
        LSLMessage(LSLMessageType.pushChunk, {
          'pointerAddr': buf.data.address,
          'dataElements': sampleCount * streamInfo.channelCount,
          'timestamp': timestamp ?? 0.0,
          'tsPointerAddr': tsAddr,
        }),
      );
      if (!response.success) {
        throw LSLException('Error pushing chunk: ${response.error}');
      }
      return response.result as int;
    } finally {
      _chunkOpInFlight = false;
    }
  }

  /// Checks if consumers are connected in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Returns:** `true` if consumers are connected, `false` otherwise.
  /// **Throws:** [LSLException] if checking for consumers fails.
  Future<bool> _hasConsumersIsolated() async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.waitForConsumer, {
        'timeout': 0.0, // Non-blocking check
      }),
    );

    if (!response.success) {
      throw LSLException('Error checking for consumers: ${response.error}');
    }

    return response.result as bool;
  }

  /// Validates sample data before pushing.
  /// **Parameters:**
  /// - [data]: List of values to validate
  /// **Throws:** [LSLException] if validation fails.
  @pragma('vm:prefer-inline')
  void _validateSampleData(Iterable<dynamic> data) {
    if (data.length != streamInfo.channelCount) {
      throw LSLException(
        'Data length (${data.length}) does not match channel count (${streamInfo.channelCount})',
      );
    }
  }

  @override
  String toString() {
    return 'LSLOutlet{streamInfo: $streamInfo, chunkSize: $chunkSize, maxBuffer: $maxBuffer, useIsolates: $_useIsolates}';
  }
}
