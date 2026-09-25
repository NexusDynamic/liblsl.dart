import 'package:signal_core/signal_core.dart';

import 'stream_info.dart';
import 'xdf_file.dart';

/// What a viewer needs of one stream of an indexed XDF recording.
abstract interface class XdfStreamView {
  /// Its position among the recording's streams; [ChannelRef.stream] of its
  /// channels.
  int get slot;

  /// Its id in the file.
  int get id;
  XdfStreamInfo get info;

  /// Whether samples are on an even grid (numeric, with a nominal rate);
  /// others are events, see [XdfRecordingSource.events].
  bool get regular;
  int get sampleCount;
  int get channelCount;

  /// Samples per second of the grid (regular streams).
  num get samplingRate;

  /// Time of the first sample, and just after the last, from the start of
  /// the recording.
  double get t0;
  double get t1;
}

/// An XDF recording being indexed, here ([XdfFile]) or in a background
/// isolate ([XdfFile.openInBackground]).
abstract interface class XdfRecordingSource {
  List<XdfStreamView> get streams;

  /// Seconds from the first to the last sample of any stream.
  double get duration;

  /// The recorder's LSL time of time 0.
  double get origin;

  bool get complete;

  /// Indexing progress, 0-1.
  double get progress;

  /// Fires while indexing runs, and when it is done.
  Stream<void> get onIndex;

  Future<void> get indexed;

  /// Progress of derived (filtered) summaries being built.
  Stream<DerivedProgress> get onDerivedProgress;

  Future<Envelope> envelope(EnvelopeRequest request);
  Future<SignalWindow> read(ReadRequest request);

  /// The samples of irregular stream [slot] so far.
  XdfEvents events(int slot);

  Future<void> close();
}
