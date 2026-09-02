import 'dart:ffi';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/bindings_ex.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
import 'package:liblsl/src/lsl/lsl_io_mixin.dart';
import 'package:liblsl/src/util/chunk_buffer.dart';

/// A unified LSL inlet that supports both isolated and direct execution modes.
///
/// **Execution Modes:**
/// - useIsolates: true` (default): Thread-safe, async-only operations
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
/// final inlet = await LSL.createInlet<double>(streamInfo: info);
/// final sample = await inlet.pullSample();
///
/// // For timing precision
/// final inlet = await LSL.createInlet<double>(streamInfo: info, useIsolates: false);
/// final sample = inlet.pullSampleSync(); // Zero async overhead
/// ```
class LSLInlet<T> extends LSLObj with LSLIOMixin, LSLExecutionMixin {
  /// The [LSLStreamInfo] stream information for this inlet.
  /// The stream info for this inlet
  LSLStreamInfo _streamInfo;

  @override
  LSLStreamInfo get streamInfo => _streamInfo;

  /// Whether to use isolates for thread safety.
  /// Default is true, which means it will use isolates for thread safety.
  final bool _useIsolates;

  /// Maximum buffer size in seconds.
  /// This is how many seconds of samples are stored in the inlet's buffer.
  /// Default is 360 seconds (6 minutes).
  @override
  final int maxBuffer;

  /// Maximum chunk length in seconds.
  /// This is the the maximum number of complete samples that can be pulled
  /// in a single call to pullSampleChunked (not yet implemented).
  /// Default is 0, which means it will use the default chunk length of the
  /// corresponding outlet.
  @override
  final int chunkSize;

  /// Whether to recover from lost samples.
  /// Default is true, which means it will try to recover lost samples.
  final bool recover;

  /// Timeout for creating the inlet in isolated mode.
  /// This is only used when `useIsolates: true`.
  /// Default is [LSL_FOREVER], which means it will wait indefinitely.
  final double createTimeout;

  /// Transport flags applied at creation via `lsl_create_inlet_ex`.
  ///
  /// An empty set (the default) uses the legacy `lsl_create_inlet` call and
  /// changes no behavior. See [LSLOutlet.transportOptions] for the
  /// [LSLTransportOptions.syncBlocking] semantics; the buffer-size flags
  /// change the unit of [maxBuffer] (samples or thousandths).
  final Set<LSLTransportOptions> transportOptions;

  /// Reusable buffer for pulling samples.
  /// Null until [create]/[createFromPointer] has set up the pull buffer, so
  /// [destroy] stays safe when creation failed part-way.
  LSLReusableBuffer? _buffer;

  LSLReusableBuffer get _bufferBang =>
      _buffer ?? (throw LSLException('Inlet buffer not initialized'));

  /// Out-parameter slots for [lsl_time_correction_ex]: `[0]` receives the
  /// remote clock reading, `[1]` the uncertainty.
  ///
  /// Allocated once with the pull buffer rather than per call, so
  /// [getTimeCorrectionExSync] keeps its zero-allocation contract.
  Pointer<Double>? _tcScratch;

  Pointer<Double> get _tcScratchBang =>
      _tcScratch ?? (throw LSLException('Inlet buffer not initialized'));

  /// Pull function for converting raw data to Dart types.
  /// This is initialized based on the [streamInfo] type.
  /// It provides methods to create reusable buffers and pull samples.
  late final LSLPullSample _pullFn;

  /// Chunk pull function; resolved lazily on the first chunk pull.
  LSLPullChunk? _pullChunkFn;

  /// Reusable native chunk buffer; lazily allocated on first chunk pull.
  LSLChunkBuffer? _chunkBuffer;

  /// Guards the shared chunk buffer against concurrent isolated chunk ops.
  bool _chunkOpInFlight = false;

  /// Whether the inlet is created using isolates or direct FFI calls.
  @override
  bool get useIsolates => _useIsolates;

  /// The underlying lsl_inlet pointer.
  lsl_inlet? _inlet;

  /// The underlying lsl_inlet pointer.
  lsl_inlet get inlet => _inletBang;

  /// Whether this inlet is managed (i.e. not created from an existing pointer).
  late final bool _managed;

  // Force-unwrap getters (avoiding ! everywhere)
  // These throw LSLException if the resource hasn't been initialized

  /// The underlying lsl_inlet pointer.
  lsl_inlet get _inletBang =>
      _inlet ?? (throw LSLException('Inlet not initialized'));

  /// Gets the full stream info with metadata from this inlet.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  ///   [_getFullInfoIsolated]
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///   [_getFullInfoDirect]
  /// **Returns:** Future that completes when full info is retrieved.
  /// **See also:** [getFullInfoSync] for zero-overhead direct calls
  Future<LSLStreamInfoWithMetadata> getFullInfo({
    required double timeout,
  }) async => _useIsolates
      ? await _getFullInfoIsolated(timeout)
      : _getFullInfoDirect(timeout);

  /// Synchronously gets the full stream info with metadata from this inlet.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// This provides maximum timing precision by eliminating all async overhead.
  /// **Example:**
  /// ```dart
  /// final inlet = await LSL.createInlet<double>(streamInfo: info, useIsolates: false);
  /// // Get full info with zero async overhead
  /// inlet.getFullInfoSync(timeout: 2.0);
  /// ```
  LSLStreamInfoWithMetadata getFullInfoSync({required double timeout}) =>
      requireDirect(() => _getFullInfoDirect(timeout));

  // Isolate resources (when using isolates)

  /// The isolate manager for handling async operations.
  LSLInletIsolateManager? _isolateManager;

  /// The isolate manager for handling async operations.
  LSLInletIsolateManager get _isolateManagerBang =>
      _isolateManager ??
      (throw LSLException('Isolate manager not initialized'));

  /// Creates a new LSLInlet instance.
  /// **Parameters:**
  /// - [streamInfo]: The stream information to create the inlet for.
  /// - [maxBuffer]: Maximum buffer size in seconds (default: 360).
  /// - [chunkSize]: Maximum chunk length in seconds (default: 0).
  /// - [recover]: Whether to recover from lost samples (default: true).
  /// - [createTimeout]: Seconds `lsl_open_stream` may block while opening the
  ///   data connection (default: [LSL_FOREVER], i.e. ~370 days). Used in
  ///   **both** modes — direct mode passes it to `lsl_open_stream` in
  ///   [_createDirect]. In direct mode the call is a synchronous FFI call on
  ///   the calling thread, so leaving this at the default lets an unreachable
  ///   peer block that thread indefinitely; callers sharing a thread or isolate
  ///   between several inlets should set a bounded value.
  /// - [useIsolates]: Whether to use isolates for thread safety (default: true)
  ///   This is recommended for most use cases to ensure thread safety,
  ///   if you choose to use direct mode (`useIsolates: false`), you most likely
  ///   will want to still run this in an isolate to avoid blocking the main
  ///   isolate.
  LSLInlet(
    this._streamInfo, {
    this.maxBuffer = 360,
    this.chunkSize = 0,
    this.recover = true,
    this.createTimeout = LSL_FOREVER,
    this.transportOptions = const {},
    bool useIsolates = true,
  }) : _useIsolates = useIsolates;

  // Method delegates

  /// Creates the inlet based on the execution mode
  /// This method must be called before using the inlet.
  /// It initializes the inlet and prepares it for pulling samples.
  /// **Execution:**
  /// - Isolated mode: Uses [LSLInletIsolateManager] for async operations
  ///   [_createIsolated]
  /// - Direct mode: Uses FFI calls directly
  ///   [_createDirect]
  /// **Returns:** A [LSLInlet] instance ready for fluid interface
  /// **See also:** [destroy] to clean up resources
  @override
  Future<LSLInlet<T>> create() async {
    LSLOutlet.validateTransportOptions(transportOptions, streamInfo);
    super.create();
    _managed = true;
    // Create the inlet based on the execution mode
    return _useIsolates ? _createIsolated() : _createDirect();
  }

  /// Destroys the inlet and cleans up resources.
  /// You can no longer use the inlet after calling this method.
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
    } else if (_inlet != null && _managed) {
      try {
        lsl_close_stream(_inletBang);
      } catch (e) {
        // Ignore errors during close, as the inlet may already be closed
      }
      try {
        lsl_destroy_inlet(_inletBang);
      } catch (e) {
        // Ignore errors during destroy, as the inlet may already be destroyed
      }
    }
    _inlet = null;
    _isolateManager = null;
    _buffer?.free();
    _buffer = null;
    _tcScratch?.free();
    _tcScratch = null;
    _chunkBuffer?.free();
    _chunkBuffer = null;
  }

  /// Pulls a sample from the inlet.
  ///
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (0.0 = non-blocking)
  ///
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///
  /// **Returns:** A [LSLSample] containing the data, timestamp, and error code.
  ///
  /// **See also:** [pullSampleSync] for zero-overhead direct calls
  Future<LSLSample<T>> pullSample({double timeout = 0.0}) => _useIsolates
      ? _pullSampleIsolated(timeout)
      : Future.value(_pullSampleDirect(timeout));

  /// Synchronously pulls a sample from the inlet.
  ///
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  ///
  /// This provides maximum timing precision by eliminating all async overhead.
  /// Ideal for high-frequency sampling or when precise timing is critical.
  ///
  /// **Example:**
  /// ```dart
  /// final inlet = await LSL.createInlet<double>(streamInfo: info, useIsolates: false);
  ///
  /// // High-precision sampling loop
  /// while (running) {
  ///   final sample = inlet.pullSampleSync(timeout: 0.001);
  ///   if (sample.isNotEmpty) {
  ///     processSample(sample);
  ///   }
  /// }
  /// ```
  /// **Returns:** A [LSLSample] containing the data, timestamp, and error code.
  /// **See also:** [pullSample] for async operations
  /// **Throws:** [LSLException] if `useIsolates: true`.
  LSLSample<T> pullSampleSync({double timeout = 0.0}) =>
      requireDirect(() => _pullSampleDirect(timeout));

  /// Pulls a chunk of buffered samples from the inlet.
  ///
  /// **Parameters:**
  /// - [maxSamples]: Upper bound on samples returned per call (default: 512).
  /// - [timeout]: Only applies while the buffer is empty — once at least one
  ///   sample is available the call returns immediately with everything
  ///   buffered (up to [maxSamples]).
  ///
  /// **Returns:** An [LSLChunk] with one list per sample and one timestamp
  /// per sample; empty if nothing arrived within [timeout].
  ///
  /// **See also:** [pullChunkSync], [pullChunkTyped]
  Future<LSLChunk<T>> pullChunk({int maxSamples = 512, double timeout = 0.0}) =>
      _useIsolates
      ? _pullChunkIsolated(maxSamples, timeout)
      : Future.value(_pullChunkDirect(maxSamples, timeout));

  /// Synchronously pulls a chunk of buffered samples.
  ///
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [pullChunk] for parameter semantics.
  LSLChunk<T> pullChunkSync({int maxSamples = 512, double timeout = 0.0}) =>
      requireDirect(() => _pullChunkDirect(maxSamples, timeout));

  /// Pulls a chunk as flat [TypedData] (fast path).
  ///
  /// The returned [LSLChunkTyped.data] is a fresh typed list matching the
  /// stream's channel format (`sampleCount * channelCount` values,
  /// sample-major); it remains valid after later pulls. Not available for
  /// string streams ([UnsupportedError]). See [pullChunk] for semantics.
  Future<LSLChunkTyped> pullChunkTyped({
    int maxSamples = 512,
    double timeout = 0.0,
  }) => _useIsolates
      ? _pullChunkTypedIsolated(maxSamples, timeout)
      : Future.value(_pullChunkTypedDirect(maxSamples, timeout));

  /// Synchronously pulls a chunk as flat [TypedData].
  ///
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [pullChunkTyped].
  LSLChunkTyped pullChunkTypedSync({
    int maxSamples = 512,
    double timeout = 0.0,
  }) => requireDirect(() => _pullChunkTypedDirect(maxSamples, timeout));

  /// Pulls a chunk and returns raw pointers into the reusable buffer
  /// (zero-copy escape hatch).
  ///
  /// **Direct mode only.** The pointers are valid until the next chunk pull
  /// on this inlet or its destruction. For string streams the data buffer
  /// holds `char*` entries owned by liblsl — the caller must release each
  /// with `lsl_destroy_string`.
  LSLChunkPointer pullChunkPointerSync({
    int maxSamples = 512,
    double timeout = 0.0,
  }) => requireDirect(() {
    final pullFn = _ensurePullChunkFn();
    final buf = _ensureChunkBuffer(maxSamples);
    final channels = streamInfo.channelCount;
    final elements = pullFn.pullInto(
      _inletBang,
      buf.data,
      buf.timestamps,
      maxSamples,
      channels,
      timeout,
      buf.ec,
    );
    return LSLChunkPointer(
      buf.data.address,
      buf.timestamps.address,
      elements ~/ channels,
      channels,
      buf.ec.value,
    );
  });

  /// Gets the time correction for the inlet.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 5.0)
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  ///   [_getTimeCorrectionIsolated]
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///   [_getTimeCorrectionDirect]
  /// **Returns:** Time correction in seconds.
  /// **See also:** [getTimeCorrectionSync] for zero-overhead direct calls
  Future<double> getTimeCorrection({double timeout = 5.0}) =>
      getTimeCorrectionEx(timeout: timeout).then((tc) => tc.offset);

  /// Synchronously gets the time correction for the inlet.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// This provides maximum timing precision by eliminating all async overhead.
  /// **Example:**
  /// ```dart
  /// final inlet = await LSL.createInlet<double>(streamInfo: info, useIsolates: false);
  /// // Get time correction with zero async overhead
  /// final timeCorrection = inlet.getTimeCorrectionSync(timeout: 0.001);
  /// ```
  /// **Returns:** Time correction in seconds.
  double getTimeCorrectionSync({double timeout = 5.0}) =>
      getTimeCorrectionExSync(timeout: timeout).offset;

  /// Gets the extended time correction for the inlet: the clock [offset], the
  /// [LSLTimeCorrection.remoteTime] it was measured against, and the
  /// [LSLTimeCorrection.uncertainty] (full round-trip time) that bounds it.
  ///
  /// liblsl computes all three on the same round trip and
  /// [getTimeCorrection] simply discards two of them, so this costs no extra
  /// network traffic and no extra native work.
  ///
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 5.0). Only the first
  ///   call blocks; later ones read a background-updated estimate.
  /// **Returns:** An [LSLTimeCorrection].
  /// **Throws:** [LSLException] if getting time correction fails.
  /// **See also:** [getTimeCorrectionExSync] for zero-overhead direct calls
  Future<LSLTimeCorrection> getTimeCorrectionEx({double timeout = 5.0}) =>
      _useIsolates
      ? _getTimeCorrectionExIsolated(timeout)
      : Future.value(_getTimeCorrectionExDirect(timeout));

  /// Synchronously gets the extended time correction for the inlet.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [getTimeCorrectionEx].
  LSLTimeCorrection getTimeCorrectionExSync({double timeout = 5.0}) =>
      requireDirect(() => _getTimeCorrectionExDirect(timeout));

  /// Enables automatic post-processing of incoming time stamps.
  ///
  /// By default an inlet does none, returning ground-truth time stamps in the
  /// sender's clock domain for you to synchronize with [getTimeCorrection].
  ///
  /// **Warning:** once enabled, the original time stamps are neither delivered
  /// nor recoverable. In particular [LSLProcessingOptions.clockSync] rewrites
  /// time stamps into the local domain, which conflicts with any layer that
  /// applies the correction itself.
  ///
  /// **Parameters:**
  /// - [options]: the post-processing steps to enable. An empty set, like
  ///   `{LSLProcessingOptions.none}`, disables post-processing.
  /// **Throws:** [LSLException] if liblsl rejects the flags.
  Future<void> setPostProcessing(Set<LSLProcessingOptions> options) async {
    if (_useIsolates) return _setPostProcessingIsolated(options);
    _setPostProcessingDirect(options);
  }

  /// Synchronously enables automatic post-processing of incoming time stamps.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [setPostProcessing].
  void setPostProcessingSync(Set<LSLProcessingOptions> options) =>
      requireDirect(() => _setPostProcessingDirect(options));

  void _setPostProcessingDirect(Set<LSLProcessingOptions> options) {
    final result = lsl_set_postprocessing(_inletBang, options.nativeFlags);
    if (result != 0) {
      throw lslError('Error setting post-processing', result);
    }
  }

  Future<void> _setPostProcessingIsolated(
    Set<LSLProcessingOptions> options,
  ) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.setPostProcessing, {
        'flags': options.nativeFlags,
      }),
    );
    if (!response.success) {
      throw LSLException('Error setting post-processing: ${response.error}');
    }
  }

  /// Overrides the half-time (forget factor) of the time-stamp smoothing used
  /// by [LSLProcessingOptions.dejitter].
  ///
  /// The default is 90 seconds unless the config file says otherwise. A longer
  /// window yields lower jitter but tracks changes in clock rate (usually from
  /// temperature) more slowly.
  ///
  /// **Parameters:**
  /// - [halftime]: seconds after which a past sample is weighted by 1/2.
  /// **Throws:** [LSLException] if liblsl rejects the value.
  Future<void> setSmoothingHalftime(double halftime) async {
    if (_useIsolates) return _setSmoothingHalftimeIsolated(halftime);
    _setSmoothingHalftimeDirect(halftime);
  }

  /// Synchronously overrides the time-stamp smoothing half-time.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [setSmoothingHalftime].
  void setSmoothingHalftimeSync(double halftime) =>
      requireDirect(() => _setSmoothingHalftimeDirect(halftime));

  void _setSmoothingHalftimeDirect(double halftime) {
    final result = lsl_smoothing_halftime(_inletBang, halftime);
    if (result != 0) {
      throw lslError('Error setting smoothing halftime', result);
    }
  }

  Future<void> _setSmoothingHalftimeIsolated(double halftime) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.setSmoothingHalftime, {'value': halftime}),
    );
    if (!response.success) {
      throw LSLException('Error setting smoothing halftime: ${response.error}');
    }
  }

  /// Whether the source machine's clock may have been reset since the last
  /// call to this method.
  ///
  /// Needed only when combining multiple [getTimeCorrectionEx] estimates to
  /// model clock drift: a source that was restarted or hot-swapped invalidates
  /// any offset fitted over earlier readings.
  ///
  /// **Note:** this is a consuming read. liblsl clears the flag as it reports
  /// it, so two calls in a row return `true` then `false` for the same reset.
  Future<bool> wasClockReset() => _useIsolates
      ? _wasClockResetIsolated()
      : Future.value(lsl_was_clock_reset(_inletBang) != 0);

  /// Synchronously checks whether the source clock was reset.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// See [wasClockReset].
  bool wasClockResetSync() =>
      requireDirect(() => lsl_was_clock_reset(_inletBang) != 0);

  Future<bool> _wasClockResetIsolated() async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.wasClockReset, {}),
    );
    if (!response.success) {
      throw LSLException('Error checking clock reset: ${response.error}');
    }
    return response.result as bool;
  }

  /// Flushes the inlet's buffer.
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  ///   [_flushIsolated]
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///   [lsl_inlet_flush]
  /// **Returns:** Number of samples dropped during flush.
  Future<int> flush() => _useIsolates
      ? _flushIsolated()
      : Future.value(lslInletFlushFast(_inletBang));

  int flushSync() => requireDirect(() => lslInletFlushFast(_inletBang));

  /// Checks how many samples are available in the inlet's buffer.
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  ///  [_samplesAvailableIsolated]
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///   [lsl_samples_available]
  /// **Returns:** Number of samples available in the inlet's buffer, if the OS
  /// supports it, otherwise, 1 if there is at least one sample available,
  /// or 0 if no samples are available.
  Future<int> samplesAvailable() => _useIsolates
      ? _samplesAvailableIsolated()
      : Future.value(lslSamplesAvailableFast(_inletBang));

  /// Synchronously checks how many samples are available in the inlet's buffer.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// This provides maximum timing precision by eliminating all async overhead.
  /// **Returns:** Number of samples available in the inlet's buffer, if the OS
  /// supports it, otherwise, 1 if there is at least one sample available,
  /// or 0 if no samples are available.
  int samplesAvailableSync() =>
      requireDirect(() => lslSamplesAvailableFast(_inletBang));

  /// Creates an inlet from an existing lsl_inlet pointer.
  /// **Parameters:**
  /// - [pointer]: The existing lsl_inlet pointer.
  /// **Returns:** A [LSLInlet] instance wrapping the existing pointer.
  /// **Throws:** [LSLException] if inlet creation fails or if
  /// `useIsolates: true`.
  Future<LSLInlet<T>> createFromPointer(lsl_inlet pointer) async {
    if (created) {
      throw LSLException('Inlet already created');
    }
    if (useIsolates) {
      throw LSLException(
        'Creating inlet from pointer is not supported in isolated mode',
      );
    }
    _managed = false;
    super.create();
    _inlet = pointer;
    setupPullBuffer();
    return this;
  }

  /// Sets up the pull buffer for sample data.
  /// This allocates memory based on the channel count and initializes the pull
  /// function.
  /// **Throws:** [LSLException] if buffer allocation fails.
  void setupPullBuffer() {
    // Initialize the pull function
    _pullFn = LSLMapper().streamPull(streamInfo);
    _buffer = _pullFn.createReusableBuffer(streamInfo.channelCount);
    _tcScratch = allocate<Double>(2);
  }

  /// Creates the inlet directly using FFI calls.
  /// This is used when `useIsolates: false`.
  /// **Returns:** A [LSLInlet] instance ready for fluid interface
  /// **Throws:** [LSLException] if inlet creation fails.
  Future<LSLInlet<T>> _createDirect() async {
    setupPullBuffer();
    // Create the inlet using FFI; the legacy call is kept for an empty
    // option set so default behavior is byte-for-byte unchanged.
    _inlet = transportOptions.isEmpty
        ? lsl_create_inlet(
            streamInfo.streamInfo,
            maxBuffer,
            chunkSize,
            recover ? 1 : 0,
          )
        : lslCreateInletFlags(
            streamInfo.streamInfo,
            maxBuffer,
            chunkSize,
            recover ? 1 : 0,
            transportOptions.nativeFlags,
          );
    if (_inlet == null || _inletBang.isNullPointer) {
      throw LSLException('Failed to create inlet');
    }

    lsl_open_stream(_inletBang, createTimeout, _bufferBang.ec);
    final result = _bufferBang.ec.value;
    if (result != 0) {
      // Build the exception before cleaning up: it reads liblsl's thread-local
      // last-error buffer, which any later call could overwrite.
      final error = lslError('Error opening inlet', result);
      final failedInlet = _inletBang;
      // Null out first so a later destroy() cannot touch the freed inlet.
      _inlet = null;
      lsl_destroy_inlet(failedInlet);
      _bufferBang.free();
      _tcScratch?.free();
      _tcScratch = null;
      throw error;
    }

    return this;
  }

  /// Creates the inlet in an isolated environment.
  /// This is used when `useIsolates: true`.
  /// **Returns:** A [LSLInlet] instance ready for fluid interface
  /// **Throws:** [LSLException] if inlet creation fails.
  Future<LSLInlet<T>> _createIsolated() async {
    // Initialize the isolate manager
    _isolateManager = LSLInletIsolateManager();
    await _isolateManagerBang.init();

    // Create reusable buffer for pulling samples
    setupPullBuffer();

    // Send message to create inlet in the isolate
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.createInlet, {
        'streamInfo': LSLSerializer.serializeStreamInfo(streamInfo),
        'maxBufferSize': maxBuffer,
        'maxChunkLength': chunkSize,
        'recover': recover,
        'timeout': createTimeout,
        'transportFlags': transportOptions.nativeFlags,
      }),
    );

    if (!response.success) {
      _bufferBang.free();
      _tcScratch?.free();
      _tcScratch = null;
      throw LSLException('Error creating inlet: ${response.error}');
    }

    return this;
  }

  /// Pulls a sample from the inlet in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 0.0)
  ///   if 0.0, it will not block and return immediately.
  /// **Returns:** A [LSLSample] containing the data, timestamp, and error code.
  /// **Throws:** [LSLException] if pulling the sample fails.
  /// **See also:** [pullSampleSync] for zero-overhead direct calls
  Future<LSLSample<T>> _pullSampleIsolated(double timeout) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.pullSample, {
        'timeout': timeout,
        'pointerAddr': _bufferBang.buffer.address,
        'ecPointerAddr': _bufferBang.ec.address,
        'channelCount': streamInfo.channelCount,
      }),
    );

    if (!response.success) {
      throw LSLException('Error pulling sample: ${response.error}');
    }

    final data = response.result as LSLSamplePointer;
    return _processSampleResponse(data.timestamp, data.errorCode);
  }

  /// Pulls a sample from the inlet directly using FFI calls.
  /// This may used when `useIsolates: false`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 0.0)
  ///   if 0.0, it will not block and return immediately.
  /// **Returns:** A [LSLSample] containing the data, timestamp, and error code.
  /// **Throws:** [LSLException] if pulling the sample fails.
  /// **See also:** [pullSample] for async operations
  /// **Note:** This method is only available when `useIsolates: false`.
  LSLSample<T> _pullSampleDirect(double timeout) {
    final LSLSamplePointer samplePointer = _pullFn.pullSampleIntoSync(
      _bufferBang.buffer,
      _inletBang,
      streamInfo.channelCount,
      timeout,
      _bufferBang.ec,
    );
    final sample = _processSampleResponse(
      samplePointer.timestamp,
      samplePointer.errorCode,
    );

    return sample;
  }

  /// Pull a sample but return the pointer instead of copying data.
  /// This may be used for advanced use cases where you want to avoid copying
  /// data out of the buffer.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 0.0)
  ///   if 0.0, it will not block and return immediately.
  /// **Returns:** A [LSLSamplePointer] containing the data pointer, timestamp, and error code.
  /// **Throws:** [LSLException] if pulling the sample fails.
  /// **Note:** This method is only available when `useIsolates: false`.
  LSLSamplePointer pullSamplePointerSync({double timeout = 0.0}) {
    return _pullFn.pullSampleIntoSync(
      _bufferBang.buffer,
      _inletBang,
      streamInfo.channelCount,
      timeout,
      _bufferBang.ec,
    );
  }

  /// Resolves the chunk pull function for this stream's channel format.
  LSLPullChunk _ensurePullChunkFn() =>
      _pullChunkFn ??= LSLMapper().streamPullChunk(streamInfo);

  /// Lazily allocates/grows the reusable chunk buffer.
  LSLChunkBuffer _ensureChunkBuffer(int samples) {
    final pullFn = _ensurePullChunkFn();
    final buf = _chunkBuffer ??= LSLChunkBuffer(
      streamInfo.channelCount,
      pullFn.allocBuffer,
    );
    buf.ensureCapacity(samples);
    return buf;
  }

  LSLChunk<T> _pullChunkDirect(int maxSamples, double timeout) {
    final pullFn = _ensurePullChunkFn();
    final buf = _ensureChunkBuffer(maxSamples);
    final channels = streamInfo.channelCount;
    final elements = pullFn.pullInto(
      _inletBang,
      buf.data,
      buf.timestamps,
      maxSamples,
      channels,
      timeout,
      buf.ec,
    );
    return _chunkFromBuffer(pullFn, buf, elements ~/ channels);
  }

  LSLChunkTyped _pullChunkTypedDirect(int maxSamples, double timeout) {
    final pullFn = _ensurePullChunkFn();
    final buf = _ensureChunkBuffer(maxSamples);
    final channels = streamInfo.channelCount;
    final elements = pullFn.pullInto(
      _inletBang,
      buf.data,
      buf.timestamps,
      maxSamples,
      channels,
      timeout,
      buf.ec,
    );
    return _chunkTypedFromBuffer(pullFn, buf, elements ~/ channels);
  }

  LSLChunk<T> _chunkFromBuffer(
    LSLPullChunk pullFn,
    LSLChunkBuffer buf,
    int sampleCount,
  ) {
    final errorCode = buf.ec.value;
    if (sampleCount == 0) {
      return LSLChunk<T>(const [], const [], errorCode);
    }
    final channels = streamInfo.channelCount;
    final samples =
        pullFn.bufferToLists(buf.data, sampleCount, channels) as List<List<T>>;
    final timestamps = List<double>.generate(
      sampleCount,
      (i) => buf.timestamps[i],
      growable: false,
    );
    return LSLChunk<T>(samples, timestamps, errorCode);
  }

  LSLChunkTyped _chunkTypedFromBuffer(
    LSLPullChunk pullFn,
    LSLChunkBuffer buf,
    int sampleCount,
  ) {
    final errorCode = buf.ec.value;
    final channels = streamInfo.channelCount;
    if (sampleCount == 0) {
      return LSLChunkTyped(
        pullFn.bufferToTypedData(buf.data, 0),
        Float64List(0),
        0,
        channels,
        errorCode,
      );
    }
    final data = pullFn.bufferToTypedData(buf.data, sampleCount * channels);
    final timestamps = Float64List.fromList(
      buf.timestamps.asTypedList(sampleCount),
    );
    return LSLChunkTyped(data, timestamps, sampleCount, channels, errorCode);
  }

  Future<LSLChunk<T>> _pullChunkIsolated(int maxSamples, double timeout) async {
    final pullFn = _ensurePullChunkFn();
    final buf = _ensureChunkBuffer(maxSamples);
    final sampleCount = await _sendPullChunkMessage(buf, maxSamples, timeout);
    return _chunkFromBuffer(pullFn, buf, sampleCount);
  }

  Future<LSLChunkTyped> _pullChunkTypedIsolated(
    int maxSamples,
    double timeout,
  ) async {
    final pullFn = _ensurePullChunkFn();
    final buf = _ensureChunkBuffer(maxSamples);
    final sampleCount = await _sendPullChunkMessage(buf, maxSamples, timeout);
    return _chunkTypedFromBuffer(pullFn, buf, sampleCount);
  }

  /// Asks the worker isolate to pull into the shared chunk buffer; returns
  /// the number of samples pulled.
  ///
  /// The request/response protocol guarantees the worker is done writing
  /// before the buffer is read here; [_chunkOpInFlight] turns concurrent
  /// misuse into an error instead of silent data corruption.
  Future<int> _sendPullChunkMessage(
    LSLChunkBuffer buf,
    int maxSamples,
    double timeout,
  ) async {
    if (_chunkOpInFlight) {
      throw LSLException('Concurrent chunk operation on the same inlet');
    }
    _chunkOpInFlight = true;
    try {
      final response = await _isolateManagerBang.sendMessage(
        LSLMessage(LSLMessageType.pullChunk, {
          'dataPointerAddr': buf.data.address,
          'tsPointerAddr': buf.timestamps.address,
          'ecPointerAddr': buf.ec.address,
          'maxSamples': maxSamples,
          'timeout': timeout,
        }),
        timeoutSeconds: timeout + 30,
      );
      if (!response.success) {
        throw LSLException('Error pulling chunk: ${response.error}');
      }
      final elements = response.result as int;
      return elements ~/ streamInfo.channelCount;
    } finally {
      _chunkOpInFlight = false;
    }
  }

  /// Flushes the inlet's buffer in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Returns:** Number of samples dropped during flush.
  /// **Throws:** [LSLException] if flushing the inlet fails.
  /// **See also:** [flushSync] for direct calls
  Future<int> _flushIsolated() async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.flush, {}),
    );

    if (!response.success) {
      throw LSLException('Error flushing inlet: ${response.error}');
    }

    return response.result as int;
  }

  /// Gets the time correction for the inlet in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 5.0)
  ///   subsequent calls will usually return immediately as the time correction
  ///   runs in the background.
  /// **Returns:** Time correction in seconds.
  /// **Throws:** [LSLException] if getting time correction fails.
  /// **See also:** [getTimeCorrectionExSync] for direct calls
  Future<LSLTimeCorrection> _getTimeCorrectionExIsolated(double timeout) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.timeCorrection, {
        'timeout': timeout,
        'ecPointerAddr': _bufferBang.ec.address,
      }),
    );

    if (!response.success) {
      throw LSLException('Error getting time correction: ${response.error}');
    }

    // The worker returns [offset, remoteTime, uncertainty]; the out-parameter
    // slots it wrote into are its own, so nothing is read back through a
    // pointer here.
    final values = response.result as List<double>;
    return LSLTimeCorrection(
      offset: values[0],
      remoteTime: values[1],
      uncertainty: values[2],
    );
  }

  /// Gets the time correction for the inlet directly using FFI calls.
  /// This may used when `useIsolates: false`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 5.0)
  ///   subsequent calls will usually return immediately as the time correction
  ///   runs in the background.
  /// **Returns:** Time correction in seconds.
  /// **Throws:** [LSLException] if getting time correction fails.
  LSLTimeCorrection _getTimeCorrectionExDirect(double timeout) {
    final scratch = _tcScratchBang;
    final offset = lsl_time_correction_ex(
      _inletBang,
      scratch,
      scratch + 1,
      timeout,
      _bufferBang.ec,
    );
    final result = _bufferBang.ec.value;
    if (result != 0) {
      throw lslError('Error getting time correction', result);
    }
    return LSLTimeCorrection(
      offset: offset,
      remoteTime: scratch[0],
      uncertainty: scratch[1],
    );
  }

  /// Gets the full stream info with metadata from the inlet in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds
  /// **Throws:** [LSLException] if getting full info fails.
  /// **See also:** [getFullInfoSync] for direct calls
  Future<LSLStreamInfoWithMetadata> _getFullInfoIsolated(double timeout) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.getFullInfo, {'timeout': timeout}),
    );

    if (!response.success) {
      throw LSLException('Error getting full info: ${response.error}');
    }

    final fullStreamInfoAddr = response.result as int;
    final fullStreamInfo = lsl_streaminfo.fromAddress(fullStreamInfoAddr);
    final streamInfo = LSLStreamInfoWithMetadata.fromStreamInfo(fullStreamInfo);
    _streamInfo = streamInfo;
    return streamInfo;
  }

  /// Gets the full stream info with metadata from the inlet directly using FFI calls.
  /// This may used when `useIsolates: false`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds
  /// **Throws:** [LSLException] if getting full info fails.
  /// **Note:** This method is only available when `useIsolates: false`.
  LSLStreamInfoWithMetadata _getFullInfoDirect(double timeout) {
    final fullStreamInfo = lsl_get_fullinfo(
      _inletBang,
      timeout,
      _bufferBang.ec,
    );
    final int errorCode = _bufferBang.ec.value;

    if (errorCode == 0 && !fullStreamInfo.isNullPointer) {
      // Replace the streamInfo with the full version
      final streamInfo = LSLStreamInfoWithMetadata.fromStreamInfo(
        fullStreamInfo,
      );
      _streamInfo = streamInfo;
      return streamInfo;
    }
    throw LSLException('Error getting full info: $errorCode');
  }

  Future<int> _samplesAvailableIsolated() async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.samplesAvailable, {}),
    );

    if (!response.success) {
      throw LSLException('Error checking samples available: ${response.error}');
    }

    return response.result as int;
  }

  /// Processes the sample response and converts it to a [LSLSample].
  /// **Parameters:**
  /// - [timestamp]: The timestamp of the sample.
  /// - [errorCode]: The error code from the sample pull operation.
  /// **Returns:** A [LSLSample] containing the data, timestamp, and error code.
  /// **Note:** If the timestamp is 0, it indicates no data was pulled.
  LSLSample<T> _processSampleResponse(double timestamp, int errorCode) {
    if (timestamp == 0) {
      return LSLSample<T>(IList<T>(), 0, errorCode);
    }

    final sampleData =
        _pullFn.bufferToList(_bufferBang.buffer, streamInfo.channelCount)
            as IList<T>;
    return LSLSample<T>(sampleData, timestamp, errorCode);
  }

  @override
  int get hashCode => Object.hash(
    _streamInfo,
    _useIsolates,
    maxBuffer,
    chunkSize,
    recover,
    createTimeout,
    transportOptions,
    _inlet?.address,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LSLInlet<T>) return false;
    return _streamInfo == other._streamInfo &&
        _useIsolates == other._useIsolates &&
        maxBuffer == other.maxBuffer &&
        chunkSize == other.chunkSize &&
        recover == other.recover &&
        createTimeout == other.createTimeout &&
        transportOptions == other.transportOptions &&
        _inlet?.address == other._inlet?.address;
  }
}
