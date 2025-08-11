import 'dart:ffi';

import 'package:liblsl/lsl.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
import 'package:liblsl/src/lsl/lsl_io_mixin.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/util/reusable_buffer.dart';

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

  /// Reusable buffer for pulling samples.
  late final LSLReusableBuffer _buffer;

  /// Pull function for converting raw data to Dart types.
  /// This is initialized based on the [streamInfo] type.
  /// It provides methods to create reusable buffers and pull samples.
  late final LslPullSample _pullFn;

  /// Whether the inlet is created using isolates or direct FFI calls.
  @override
  bool get useIsolates => _useIsolates;

  /// The underlying lsl_inlet pointer.
  lsl_inlet? _inlet;

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
  Future<void> getFullInfo({required double timeout}) async => _useIsolates
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
  void getFullInfoSync({required double timeout}) =>
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
  /// - [createTimeout]: Timeout for creating the inlet (default: LSL_FOREVER).
  ///   Only used in isolated mode.
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
    super.create();
    // Create the inlet based on the execution mode
    return _useIsolates ? _createIsolated() : _createDirect();
  }

  /// Destroys the inlet and cleans up resources.
  /// You can no longer use the inlet after calling this method.
  @override
  Future<void> destroy() async {
    if (destroyed) {
      return; // Already destroyed
    }
    super.destroy();
    // Clean up resources
    if (_useIsolates) {
      await _isolateManagerBang.sendMessage(
        LSLMessage(LSLMessageType.destroy, {}),
      );
      _isolateManagerBang.dispose();
    } else if (_inlet != null) {
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
    _buffer.free();
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
  Future<double> getTimeCorrection({double timeout = 5.0}) => _useIsolates
      ? _getTimeCorrectionIsolated(timeout)
      : Future.value(_getTimeCorrectionDirect(timeout));

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
      requireDirect(() => _getTimeCorrectionDirect(timeout));

  /// Flushes the inlet's buffer.
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  ///   [_flushIsolated]
  /// - Direct mode: Immediate FFI call wrapped in Future
  ///   [lsl_inlet_flush]
  /// **Returns:** Number of samples dropped during flush.
  Future<int> flush() => _useIsolates
      ? _flushIsolated()
      : Future.value(lsl_inlet_flush(_inletBang));

  int flushSync() => requireDirect(() => lsl_inlet_flush(_inletBang));

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
      : Future.value(lsl_samples_available(_inletBang));

  /// Synchronously checks how many samples are available in the inlet's buffer.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// This provides maximum timing precision by eliminating all async overhead.
  /// **Returns:** Number of samples available in the inlet's buffer, if the OS
  /// supports it, otherwise, 1 if there is at least one sample available,
  /// or 0 if no samples are available.
  int samplesAvailableSync() =>
      requireDirect(() => lsl_samples_available(_inletBang));

  /// Creates the inlet directly using FFI calls.
  /// This is used when `useIsolates: false`.
  /// **Returns:** A [LSLInlet] instance ready for fluid interface
  /// **Throws:** [LSLException] if inlet creation fails.
  Future<LSLInlet<T>> _createDirect() async {
    // Initialize the pull function
    _pullFn = LSLMapper().streamPull(streamInfo);
    _buffer = _pullFn.createReusableBuffer(streamInfo.channelCount);

    // Create the inlet using FFI
    _inlet = lsl_create_inlet(
      streamInfo.streamInfo,
      maxBuffer,
      chunkSize,
      recover ? 1 : 0,
    );
    if (_inlet == null) {
      throw LSLException('Failed to create inlet');
    }

    lsl_open_stream(_inletBang, createTimeout, _buffer.ec);
    final result = _buffer.ec.value;
    if (result != 0) {
      lsl_destroy_inlet(_inletBang);
      throw LSLException('Error opening inlet: $result');
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

    _pullFn = LSLMapper().streamPull(streamInfo);
    // Create reusable buffer for pulling samples
    _buffer = _pullFn.createReusableBuffer(streamInfo.channelCount);

    // Send message to create inlet in the isolate
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.createInlet, {
        'streamInfo': LSLSerializer.serializeStreamInfo(streamInfo),
        'maxBufferSize': maxBuffer,
        'maxChunkLength': chunkSize,
        'recover': recover,
        'timeout': createTimeout,
      }),
    );

    if (!response.success) {
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
        'pointerAddr': _buffer.buffer.address,
        'ecPointerAddr': _buffer.ec.address,
        'channelCount': streamInfo.channelCount,
      }),
    );

    if (!response.success) {
      throw LSLException('Error pulling sample: ${response.error}');
    }

    final data = response.result as Map<String, dynamic>;
    return _processSampleResponse(
      data['timestamp'] as double,
      data['errorCode'] as int,
    );
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
      _buffer.buffer,
      _inletBang,
      streamInfo.channelCount,
      timeout,
      _buffer.ec,
    );
    return _processSampleResponse(
      samplePointer.timestamp,
      samplePointer.errorCode,
    );
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
  /// **See also:** [getTimeCorrectionSync] for direct calls
  Future<double> _getTimeCorrectionIsolated(double timeout) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.timeCorrection, {
        'timeout': timeout,
        'ecPointerAddr': _buffer.ec.address,
      }),
    );

    if (!response.success) {
      throw LSLException('Error getting time correction: ${response.error}');
    }

    return response.result as double;
  }

  /// Gets the time correction for the inlet directly using FFI calls.
  /// This may used when `useIsolates: false`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds (default: 5.0)
  ///   subsequent calls will usually return immediately as the time correction
  ///   runs in the background.
  /// **Returns:** Time correction in seconds.
  /// **Throws:** [LSLException] if getting time correction fails.
  double _getTimeCorrectionDirect(double timeout) {
    final timeCorrection = lsl_time_correction(_inletBang, timeout, _buffer.ec);
    final result = _buffer.ec.value;
    if (result != 0) {
      throw LSLException('Error getting time correction: $result');
    }
    return timeCorrection;
  }

  /// Gets the full stream info with metadata from the inlet in isolated mode.
  /// This is used when `useIsolates: true`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds
  /// **Throws:** [LSLException] if getting full info fails.
  /// **See also:** [getFullInfoSync] for direct calls
  Future<void> _getFullInfoIsolated(double timeout) async {
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.getFullInfo, {'timeout': timeout}),
    );

    if (!response.success) {
      throw LSLException('Error getting full info: ${response.error}');
    }

    final fullStreamInfoAddr = response.result as int;
    final fullStreamInfo = lsl_streaminfo.fromAddress(fullStreamInfoAddr);
    _streamInfo = LSLStreamInfoWithMetadata.fromStreamInfo(fullStreamInfo);
  }

  /// Gets the full stream info with metadata from the inlet directly using FFI calls.
  /// This may used when `useIsolates: false`.
  /// **Parameters:**
  /// - [timeout]: Maximum wait time in seconds
  /// **Throws:** [LSLException] if getting full info fails.
  /// **Note:** This method is only available when `useIsolates: false`.
  void _getFullInfoDirect(double timeout) {
    final Pointer<Int32> ec = allocate<Int32>();
    final fullStreamInfo = lsl_get_fullinfo(_inletBang, timeout, ec);
    final int errorCode = ec.value;
    ec.free();

    if (errorCode == 0 && !fullStreamInfo.isNullPointer) {
      // Replace the streamInfo with the full version
      _streamInfo = LSLStreamInfoWithMetadata.fromStreamInfo(fullStreamInfo);
    } else if (errorCode != 0) {
      throw LSLException('Error getting full info: $errorCode');
    }
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
      return LSLSample<T>([], 0, errorCode);
    }

    final sampleData =
        _pullFn.bufferToList(_buffer.buffer, streamInfo.channelCount)
            as List<T>;
    return LSLSample<T>(sampleData, timestamp, errorCode);
  }
}
