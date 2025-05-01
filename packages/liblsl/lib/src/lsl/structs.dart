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
    final customType = LSLContentType._(value, isCustom: true);
    if (_values.any((type) => type.value == value)) {
      throw ArgumentError(
        'Custom content type "$value" conflicts with existing LSL content types.',
      );
    }
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
