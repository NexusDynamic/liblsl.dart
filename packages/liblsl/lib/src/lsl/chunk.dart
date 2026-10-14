export 'package:lsl_core/lsl_core.dart' show LSLChunk, LSLChunkTyped;

/// Zero-copy result of [LSLInlet.pullChunkPointerSync].
///
/// The pointers reference the inlet's reusable chunk buffer and are only
/// valid until the next chunk pull on the same inlet (or its destruction).
@pragma('vm:deeply-immutable')
final class LSLChunkPointer {
  /// Address of the flat data buffer (`sampleCount * channelCount` elements
  /// of the stream's native type).
  final int dataPointerAddress;

  /// Address of the `Float64` timestamp buffer (`sampleCount` elements).
  final int timestampPointerAddress;

  final int sampleCount;
  final int channelCount;
  final int errorCode;

  const LSLChunkPointer(
    this.dataPointerAddress,
    this.timestampPointerAddress,
    this.sampleCount,
    this.channelCount,
    this.errorCode,
  );

  bool get isEmpty => sampleCount == 0;
  bool get isNotEmpty => sampleCount > 0;
}
