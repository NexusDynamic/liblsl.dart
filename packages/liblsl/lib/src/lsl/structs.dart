import 'dart:ffi';
import 'package:liblsl/liblsl.dart';
import 'package:ffi/ffi.dart' show StringUtf8Pointer;
import 'package:liblsl/src/ffi/mem.dart';

/// The stream info content types.
enum LSLContentType {
  /// EEG (for Electroencephalogram).
  eeg("EEG"),

  /// MoCap (for Motion Capture).
  mocap("MoCap"),

  /// NIRS (Near-Infrared Spectroscopy).
  nirs("NIRS"),

  /// Gaze (for gaze / eye tracking parameters).
  gaze("Gaze"),

  /// VideoRaw (for uncompressed video).
  videoRaw("VideoRaw"),

  /// VideoCompressed (for compressed video).
  videoCompressed("VideoCompressed"),

  /// Audio (for PCM-encoded audio).
  audio("Audio"),

  /// Markers (for event marker streams).
  markers("Markers");

  final String value;

  const LSLContentType(this.value);

  /// Converts the content type to a [Pointer<Char>].
  Pointer<Char> get charPtr =>
      value.toNativeUtf8(allocator: allocate) as Pointer<Char>;
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
