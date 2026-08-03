import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
import 'package:ffi/ffi.dart' show StringUtf8Pointer;
import 'package:liblsl/src/ffi/mem.dart';

/// LSL content types used to identify the type of data being streamed.
class LSLContentType {
  /// The string representation of the content type.
  final String value;

  /// Indicates whether the content type is custom or not.
  /// @note Custom content types are not defined in the LSL / XDF standard.
  final bool isCustom;
  static final List<LSLContentType> _values = [
    eeg,
    mocap,
    nirs,
    gaze,
    videoRaw,
    videoCompressed,
    audio,
    markers,
  ];

  // ignore: unused_element_parameter
  const LSLContentType._(this.value, {this.isCustom = false});

  /// EEG (for Electroencephalogram).
  static const LSLContentType eeg = LSLContentType._("EEG");

  /// MoCap (for Motion Capture).
  static const LSLContentType mocap = LSLContentType._("MoCap");

  /// NIRS (Near-Infrared Spectroscopy).
  static const LSLContentType nirs = LSLContentType._("NIRS");

  /// Gaze (for gaze / eye tracking parameters).
  static const LSLContentType gaze = LSLContentType._("Gaze");

  /// VideoRaw (for uncompressed video).
  static const LSLContentType videoRaw = LSLContentType._("VideoRaw");

  /// VideoCompressed (for compressed video).
  static const LSLContentType videoCompressed = LSLContentType._(
    "VideoCompressed",
  );

  /// Audio (for PCM-encoded audio).
  static const LSLContentType audio = LSLContentType._("Audio");

  /// Markers (for event marker streams).
  static const LSLContentType markers = LSLContentType._("Markers");

  /// Custom content type.
  /// @param value The custom content type string.
  /// @note This is used for custom content types that are not defined in the
  /// LSL / XDF standard, e.g. "State" or "Stimulus".
  factory LSLContentType.custom(String value) {
    // throw UnsupportedError('Custom content types are not yet supported.');
    final customType = LSLContentType._(value, isCustom: true);
    if (_values.any((type) => type.value == value && !type.isCustom)) {
      // If a default type with the same name exists, throw an error.
      // This is to prevent conflicts with existing LSL content types.
      throw ArgumentError(
        'Custom content type "$value" conflicts with existing LSL content types.',
      );
    }
    if (_values.any((type) => type.value == value && type.isCustom)) {
      // If a custom type with the same name already exists, return it.
      return _values.firstWhere((type) => type.value == value);
    }
    // If no conflicts, add the new custom type to the list.
    _values.add(customType);
    return customType;
  }

  /// Converts the content type to a [Pointer<Char>].
  Pointer<Char> get charPtr =>
      value.toNativeUtf8(allocator: allocate) as Pointer<Char>;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LSLContentType) return false;
    return value == other.value && isCustom == other.isCustom;
  }

  @override
  int get hashCode => value.hashCode ^ isCustom.hashCode;

  @override
  String toString() {
    return 'LSLContentType(value: $value, isCustom: $isCustom)';
  }

  /// Returns a list of all available default and custom LSL content types.
  static List<LSLContentType> get values => _values;
}

/// The stream info channel formats.
enum LSLChannelFormat {
  float32,
  double64,
  int8,
  int16,
  int32,
  int64,
  string,
  undefined;

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
