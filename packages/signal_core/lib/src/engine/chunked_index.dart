import 'dart:typed_data';

import '../pyramid.dart';

/// Timing and size of one stream of a recording.
///
/// Samples of a regular stream (sampling rate > 0) are evenly spaced:
/// sample `k` (its *ordinal*) is at `t0 + k / samplingRate` seconds. Gaps
/// are the format's business (e.g. filled by interpolation, or NaN).
abstract interface class StreamTiming {
  /// Channels per sample.
  int get channelCount;

  /// Samples per second, or 0 for irregular streams.
  num get samplingRate;

  /// Time of the first sample in seconds.
  double get t0;

  /// Number of samples (ordinals) so far.
  int get length;

  /// Whether the stream is regular (sampling rate > 0).
  bool get regular;
}

/// Where the samples of one stream lie within a chunk.
abstract interface class StreamChunkSpan {
  /// Ordinal of the stream's first sample in the chunk.
  int get firstOrdinal;

  /// Ordinals of the stream in the chunk.
  int get length;
}

/// A byte range of a recording that can be decoded on its own.
abstract interface class SignalChunk {
  int get offset;
  int get length;

  /// The samples of [stream] in this chunk, or null if it has none.
  StreamChunkSpan? span(int stream);
}

/// Decoded samples of one stream within a chunk, per channel.
class StreamColumns {
  final int firstOrdinal;
  final List<Float32List> channels;

  const StreamColumns(this.firstOrdinal, this.channels);

  int get length => channels.isEmpty ? 0 : channels.first.length;
}

/// Decoded regular-stream samples of one chunk, indexed by stream.
class ChunkData {
  final int chunkIndex;
  final List<StreamColumns?> streams;

  ChunkData(this.chunkIndex, this.streams);

  int get sizeInBytes {
    var n = 0;
    for (final s in streams) {
      if (s == null) continue;
      for (final c in s.channels) {
        n += c.lengthInBytes;
      }
    }
    return n + 64;
  }
}

/// What a file format provides so a [ChunkedSignalEngine] can answer views
/// of a recording: its chunks, the timing of its regular streams, and a
/// summary pyramid per regular stream.
///
/// The index may grow while the recording is being indexed; [complete]
/// says when it is done. Only the last chunk may still grow.
abstract interface class ChunkedSignalIndex {
  /// Whether the whole recording has been indexed.
  bool get complete;

  /// The chunks indexed so far, in order.
  List<SignalChunk> get chunks;

  /// Timing of [stream], or null if it has no samples.
  StreamTiming? stream(int stream);

  /// The summary pyramid of regular [stream], or null.
  SummaryPyramid? pyramid(int stream);

  /// Decode the regular-stream samples of [chunk] from its [bytes].
  ChunkData decodeChunk(covariant SignalChunk chunk, Uint8List bytes);
}
