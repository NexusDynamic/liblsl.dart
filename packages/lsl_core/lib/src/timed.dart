import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// A sample and the local clock at the moment it was pulled.
final class LSLTimedSample<T> {
  final IList<T> data;

  /// The sample's time stamp, as [LSLSample.timestamp].
  final double timestamp;

  /// `lsl_local_clock()` as the pull that returned this sample came back:
  /// when the sample became available to this process, not when a listener
  /// got round to it.
  ///
  /// That is its arrival only for a sample the listener was waiting for. One
  /// that was already in the inlet's buffer has the time it was taken out
  /// instead, which is later: whatever arrived before the stream was
  /// listened to, and with `maxBacklog` whatever arrived while the listener
  /// was held back (a queue at its limit, a paused subscription).
  final double receivedClock;

  const LSLTimedSample(this.data, this.timestamp, this.receivedClock);

  @override
  String toString() =>
      'LSLTimedSample{data: $data, timestamp: $timestamp, '
      'receivedClock: $receivedClock}';
}

/// Samples that were waiting together, and the local clock at the moment
/// the first of them was pulled.
final class LSLTimedChunk {
  /// One time stamp per sample, as [LSLSample.timestamp].
  final Float64List timestamps;

  /// `sampleCount * channelCount` values, sample after sample, in a typed
  /// list matching the stream's channel format. Null for a string stream.
  final TypedData? data;

  /// `sampleCount * channelCount` strings, for a string stream.
  final List<String>? strings;

  final int channelCount;

  /// `lsl_local_clock()` as the pull that returned the first sample came
  /// back: when the chunk began to be available to this process. The first
  /// [readyCount] samples were in the inlet by then; the rest arrived within
  /// the `coalesce` time after it. As [LSLTimedSample.receivedClock], it is
  /// an arrival only if the listener was waiting for the first sample.
  final double receivedClock;

  /// How many samples, from the first, were already in the inlet when
  /// [receivedClock] was read. All of them unless `coalesce` was given.
  ///
  /// A sender that pushes chunks delivers their samples together, with time
  /// stamps spread over the chunk, so the first sample's is older than its
  /// arrival by the time the sender took to fill the chunk. The sample that
  /// waited least is the last one that was ready:
  /// `receivedClock - timestamps[readyCount - 1]` is the transit time with
  /// no chunking in it, where `receivedClock - timestamps.first` has the
  /// sender's.
  final int readyCount;

  const LSLTimedChunk(
    this.timestamps,
    this.channelCount,
    this.receivedClock, {
    this.data,
    this.strings,
    int? readyCount,
  }) : readyCount = readyCount ?? timestamps.length;

  int get sampleCount => timestamps.length;

  @override
  String toString() =>
      'LSLTimedChunk{samples: $sampleCount, channels: $channelCount, '
      'receivedClock: $receivedClock}';
}

/// How far the listener of a sample or chunk stream is behind the thread
/// that pulls for it. See `onBacklog` of `LSLInlet.sampleStream` (liblsl).
final class LSLBacklog {
  /// Samples that have been pulled from the inlet and not yet reached the
  /// stream: what is queued between the thread and the stream.
  final int queued;

  /// The most [queued] has been since it went over the threshold.
  final int peak;

  /// Whether this is the report that the queue is back under half the
  /// threshold. Nothing more is reported until it goes over again.
  final bool cleared;

  const LSLBacklog({
    required this.queued,
    required this.peak,
    this.cleared = false,
  });

  @override
  String toString() =>
      'LSLBacklog{queued: $queued, peak: $peak, cleared: $cleared}';
}
