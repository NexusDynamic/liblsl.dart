import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
import 'package:ffi/ffi.dart' show StringUtf8Pointer;
import 'package:liblsl/src/ffi/mem.dart';
import 'package:lsl_core/lsl_core.dart' show LSLChannelFormat, LSLContentType;

export 'package:lsl_core/lsl_core.dart' show LSLChannelFormat, LSLContentType;

/// The FFI side of an [LSLContentType].
extension LSLContentTypeNative on LSLContentType {
  /// Converts the content type to a [Pointer<Char>].
  Pointer<Char> get charPtr =>
      value.toNativeUtf8(allocator: allocate) as Pointer<Char>;
}

/// The FFI side of an [LSLChannelFormat].
extension LSLChannelFormatNative on LSLChannelFormat {
  /// Gets the underlying lsl_channel_format_t value for the channel format.
  lsl_channel_format_t get lslFormat {
    switch (this) {
      case LSLChannelFormat.float32:
        return lsl_channel_format_t.cft_float32;
      case LSLChannelFormat.double64:
        return lsl_channel_format_t.cft_double64;
      case LSLChannelFormat.int8:
        return lsl_channel_format_t.cft_int8;
      case LSLChannelFormat.int16:
        return lsl_channel_format_t.cft_int16;
      case LSLChannelFormat.int32:
        return lsl_channel_format_t.cft_int32;
      case LSLChannelFormat.int64:
        return lsl_channel_format_t.cft_int64;
      case LSLChannelFormat.string:
        return lsl_channel_format_t.cft_string;
      case LSLChannelFormat.undefined:
        return lsl_channel_format_t.cft_undefined;
    }
  }

  /// Gets the underlying FFI [NativeType] for the channel format.
  /// @note This returns [Type], not [NativeType], because FFI types are
  /// not considered subtypes of [NativeType].
  Type get ffiType {
    switch (this) {
      case LSLChannelFormat.float32:
        return Float;
      case LSLChannelFormat.double64:
        return Double;
      case LSLChannelFormat.int8:
        return Int8;
      case LSLChannelFormat.int16:
        return Int16;
      case LSLChannelFormat.int32:
        return Int32;
      case LSLChannelFormat.int64:
        return Int64;
      case LSLChannelFormat.string:
        return Pointer<Char>;
      case LSLChannelFormat.undefined:
        return Void;
    }
  }

  /// Gets the underlying Dart [Type] for the channel format.
  Type get dartType {
    switch (this) {
      case LSLChannelFormat.float32:
        return double;
      case LSLChannelFormat.double64:
        return double;
      case LSLChannelFormat.int8:
        return int;
      case LSLChannelFormat.int16:
        return int;
      case LSLChannelFormat.int32:
        return int;
      case LSLChannelFormat.int64:
        return int;
      case LSLChannelFormat.string:
        return String;
      case LSLChannelFormat.undefined:
        return Void;
    }
  }
}

/// This enum has flags that are used for inlets and outlets
enum LSLTransportOptions {
  /// Keep legacy behavior: max_buffered / max_buflen is in seconds; use asynch transfer.
  legacy(lsl_transport_options_t.transp_default),

  /// The supplied max_buf value is in samples.
  bufsizeInSamples(lsl_transport_options_t.transp_bufsize_samples),

  /// The supplied max_buf should be scaled by 0.001.
  bufsizeInThousandths(lsl_transport_options_t.transp_bufsize_thousandths),

  /// Use synchronous (blocking) socket writes for zero-copy data transfer.
  /// When enabled, push_sample/push_chunk write the caller's buffer directly to every
  /// connected consumer and block until the data has been handed to the OS for all of them.
  /// Reduces CPU usage for high-bandwidth streams at the cost of increased call latency.
  /// Notes:
  /// - Not compatible with string-format streams (variable-size samples).
  /// - Single-producer: push from only one thread at a time (the sync path is unsynchronized).
  /// - The pushthrough flag is ignored; every push sends immediately (no internal buffering).
  syncBlocking(lsl_transport_options_t.transp_sync_blocking);

  final lsl_transport_options_t _nativeType;

  lsl_transport_options_t get nativeType => _nativeType;
  int get value => nativeType.value;

  /// Private constructor to associate the enum value with its native type.
  const LSLTransportOptions(this._nativeType);

  /// Converts a native lsl_transport_options_t value to the corresponding LSLTransportOptions enum value.
  static LSLTransportOptions fromNative(lsl_transport_options_t native) {
    return LSLTransportOptions.values.firstWhere(
      (e) => e.nativeType == native,
      orElse: () => throw ArgumentError(
        'No matching LSLTransportOptions for native value: $native',
      ),
    );
  }

  /// Converts an integer value to the corresponding LSLTransportOptions enum value.
  static LSLTransportOptions fromValue(int value) {
    return LSLTransportOptions.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError(
        'No matching LSLTransportOptions for value: $value',
      ),
    );
  }
}

/// Combines a set of [LSLTransportOptions] into the bitwise-OR'd int that
/// the `lsl_create_outlet_ex` / `lsl_create_inlet_ex` functions expect.
extension LSLTransportOptionsFlags on Set<LSLTransportOptions> {
  @pragma('vm:prefer-inline')
  int get nativeFlags => fold(0, (acc, option) => acc | option.value);
}

/// Automatic post-processing an inlet applies to incoming time stamps.
///
/// The default is no post-processing at all: the inlet returns ground-truth
/// time stamps in the *sender's* clock domain, which you synchronize yourself
/// with [LSLInlet.getTimeCorrection].
///
/// **Warning:** once post-processing is enabled the original time stamps are
/// neither delivered nor recoverable.
enum LSLProcessingOptions {
  /// No automatic post-processing; ground-truth time stamps, for manual
  /// synchronization. This is the inlet default.
  none(lsl_processing_options_t.proc_none),

  /// Automatic clock synchronization: equivalent to adding the
  /// [LSLInlet.getTimeCorrection] value to every received time stamp.
  ///
  /// **Do not enable this under `liblsl_coordinator`.** Its `MessageTiming`
  /// treats the sample time stamp as the sender's clock and adds the offset
  /// itself, so a pre-corrected time stamp would be corrected twice and every
  /// reported transit time would be wrong by roughly one offset.
  clockSync(lsl_processing_options_t.proc_clocksync),

  /// Remove jitter from time stamps by smoothing them.
  ///
  /// Needs to see a minimum number of samples (30-120 seconds worst case)
  /// before the residual jitter is consistently below 1 ms. See
  /// [LSLInlet.setSmoothingHalftime] to tune the smoothing window.
  dejitter(lsl_processing_options_t.proc_dejitter),

  /// Force time stamps to ascend monotonically.
  /// Only meaningful together with [dejitter].
  monotonize(lsl_processing_options_t.proc_monotonize),

  /// Make post-processing thread-safe, so one inlet can be read from multiple
  /// threads. Uses somewhat more CPU.
  threadSafe(lsl_processing_options_t.proc_threadsafe);

  final lsl_processing_options_t _nativeType;

  lsl_processing_options_t get nativeType => _nativeType;
  int get value => nativeType.value;

  /// Private constructor to associate the enum value with its native type.
  const LSLProcessingOptions(this._nativeType);

  /// Converts a native lsl_processing_options_t value to the corresponding
  /// LSLProcessingOptions enum value.
  static LSLProcessingOptions fromNative(lsl_processing_options_t native) {
    return LSLProcessingOptions.values.firstWhere(
      (e) => e.nativeType == native,
      orElse: () => throw ArgumentError(
        'No matching LSLProcessingOptions for native value: $native',
      ),
    );
  }

  /// Converts an integer value to the corresponding LSLProcessingOptions enum
  /// value.
  static LSLProcessingOptions fromValue(int value) {
    return LSLProcessingOptions.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError(
        'No matching LSLProcessingOptions for value: $value',
      ),
    );
  }
}

/// Combines a set of [LSLProcessingOptions] into the bitwise-OR'd int that
/// `lsl_set_postprocessing` expects.
extension LSLProcessingOptionsFlags on Set<LSLProcessingOptions> {
  @pragma('vm:prefer-inline')
  int get nativeFlags => fold(0, (acc, option) => acc | option.value);
}
