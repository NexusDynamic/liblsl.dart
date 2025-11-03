import 'dart:async';
import 'dart:ffi';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
import 'package:liblsl/src/lsl/lsl_io_mixin.dart';
import 'package:liblsl/src/lsl/push_sample.dart';
import 'package:liblsl/src/ffi/mem.dart';

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
  @override
  final int maxBuffer;

  /// Push function for converting Dart types to raw data.
  /// This is initialized based on the [streamInfo] type.
  /// It provides methods to allocate buffers and push samples.
  late final LslPushSample _pushFn;

  LslPushSample get nativePush => _pushFn;

  /// Buffer for storing sample data before pushing.
  late final Pointer<NativeType> _buffer;

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
    _managed = true;
    super.create();
    // Create the outlet based on the execution mode
    return _useIsolates ? _createIsolated() : _createDirect();
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
    if (!_buffer.isNullPointer) {
      _buffer.free();
    }
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

  /// Checks if consumers are currently connected to the outlet.
  /// **Execution:**
  /// - Isolated mode: Async message passing to worker isolate
  /// - Direct mode: Immediate FFI call wrapped in Future
  /// **Returns:** `true` if consumers are connected, `false` otherwise.
  Future<bool> hasConsumers() => _useIsolates
      ? _hasConsumersIsolated()
      : Future.value(lsl_have_consumers(_outletBang) != 0);

  /// Synchronously checks if consumers are currently connected to the outlet.
  /// **Direct mode only** - throws [LSLException] if `useIsolates: true`.
  /// **Returns:** `true` if consumers are connected, `false` otherwise.
  bool hasConsumersSync() =>
      requireDirect(() => lsl_have_consumers(_outletBang) != 0);

  /// Sets up the push buffer for sample data.
  /// This allocates memory based on the channel count and initializes the push
  /// function.
  /// **Throws:** [LSLException] if buffer allocation fails.
  void _setupPushBuffer() {
    // Initialize the push function and buffer
    _pushFn = LSLMapper().streamPush(streamInfo);
    _buffer = _pushFn.allocBuffer(streamInfo.channelCount);
    if (_buffer.isNullPointer && _pushFn is! LslPushSampleVoid) {
      throw LSLException('Failed to allocate memory for buffer');
    }
  }

  /// Creates the outlet directly using FFI calls.
  /// This is used when `useIsolates: false`.
  /// **Returns:** A [LSLOutlet] instance ready for fluid interface
  /// **Throws:** [LSLException] if outlet creation fails.
  Future<LSLOutlet> _createDirect() async {
    _setupPushBuffer();
    // Create the outlet using FFI
    _outlet = lsl_create_outlet(streamInfo.streamInfo, chunkSize, maxBuffer);
    if (_outlet == null) {
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

    // Initialize the push function and buffer
    _pushFn = LSLMapper().streamPush(streamInfo);
    _buffer = _pushFn.allocBuffer(streamInfo.channelCount);
    if (_buffer.isNullPointer && _pushFn is! LslPushSampleVoid) {
      throw LSLException('Failed to allocate memory for buffer');
    }

    // Send message to create outlet in the isolate
    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.createOutlet, {
        'streamInfo': LSLSerializer.serializeStreamInfo(streamInfo),
        'chunkSize': chunkSize,
        'maxBuffer': maxBuffer,
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

    // Set the sample data in the buffer
    _pushFn.listToBuffer(IList(data), _buffer);

    final response = await _isolateManagerBang.sendMessage(
      LSLMessage(LSLMessageType.pushSample, {'pointerAddr': _buffer.address}),
    );

    if (!response.success) {
      throw LSLException('Error pushing sample: ${response.error}');
    }

    return response.result as int;
  }

  /// Pushes a sample directly using FFI calls.
  /// This is used when `useIsolates: false`.
  /// **Parameters:**
  /// - [data]: List of values to push
  /// **Returns:** Error code (0 = success).
  /// **Throws:** [LSLException] if pushing the sample fails.
  int _pushSampleDirect(Iterable<dynamic> data) {
    _validateSampleData(data);

    // Set the sample data in the buffer
    _pushFn.listToBuffer(IList(data), _buffer);

    // Push the sample
    final result = _pushFn(_outletBang, _buffer);
    if (LSLObj.error(result)) {
      throw LSLException('Error pushing sample: $result');
    }
    return result;
  }

  Pointer<NativeType> dataToBufferPointer(Iterable<dynamic> data) {
    _validateSampleData(data);
    // Set the sample data in the buffer
    _pushFn.listToBuffer(IList(data), _buffer);
    return _buffer;
  }

  int pushSamplePointerSync(Pointer<NativeType> pointer) {
    return _pushFn(_outletBang, pointer);
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
