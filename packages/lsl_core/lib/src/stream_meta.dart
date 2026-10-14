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

/// Represents a property of an LSL stream that can be used for filtering.
/// This enum is used in `LSLStreamResolver` (liblsl) to filter streams by their
/// properties.
enum LSLStreamProperty {
  name(lslName: 'name'),
  type(lslName: 'type'),
  channelCount(lslName: 'channel_count'),
  channelFormat(lslName: 'channel_format'),
  sourceId(lslName: 'source_id'),
  sampleRate(lslName: 'nominal_srate');

  const LSLStreamProperty({required this.lslName});
  final String lslName;
}
