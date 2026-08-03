import 'dart:typed_data';

/// A chunk of samples pulled from an inlet, in list-of-samples form.
///
/// `samples[i]` is one frame of `channelCount` values and `timestamps[i]` is
/// its capture timestamp on the sender's clock.
class LSLChunk<T> {
  final List<List<T>> samples;
  final List<double> timestamps;
  final int errorCode;

  const LSLChunk(this.samples, this.timestamps, this.errorCode);

  int get sampleCount => samples.length;
  bool get isEmpty => samples.isEmpty;
  bool get isNotEmpty => samples.isNotEmpty;

  @override
  String toString() =>
      'LSLChunk<$T>{samples: $sampleCount, errorCode: $errorCode}';
}

/// A chunk of samples in flat typed-data form.
///
/// [data] holds `sampleCount * channelCount` values in sample-major order
/// (all channels of sample 0, then sample 1, ...). The concrete [TypedData]
/// type matches the stream's channel format (e.g. [Float32List] for float32).
/// Both [data] and [timestamps] are copies and stay valid after further pulls.
class LSLChunkTyped {
  final TypedData data;
  final Float64List timestamps;
  final int sampleCount;
  final int channelCount;
  final int errorCode;

  const LSLChunkTyped(
    this.data,
    this.timestamps,
    this.sampleCount,
    this.channelCount,
    this.errorCode,
  );

  bool get isEmpty => sampleCount == 0;
  bool get isNotEmpty => sampleCount > 0;

  @override
  String toString() =>
      'LSLChunkTyped{samples: $sampleCount, channels: $channelCount, '
      'errorCode: $errorCode}';
}

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
