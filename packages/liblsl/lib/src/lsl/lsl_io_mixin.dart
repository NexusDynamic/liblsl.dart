import 'package:liblsl/lsl.dart';
import 'package:meta/meta.dart';

mixin LSLIOMixin {
  /// The [LSLStreamInfo] stream information for this outlet.
  LSLStreamInfo get streamInfo;

  /// Chunk size in samples for transmission.
  /// 0 creates a chunk for each push operation.
  int get chunkSize;

  /// Maximum buffer size in seconds.
  /// This is how many seconds of samples are stored in the outlet's buffer.
  /// Default is 360 seconds (6 minutes).
  int get maxBuffer;
}

mixin LSLExecutionMixin {
  /// Whether to use isolates for thread safety.
  /// Default is true, which means it will use isolates for thread safety.
  bool get useIsolates;

  /// Helper to enforce direct-only operations
  @protected
  R requireDirect<R>(R Function() operation) {
    if (useIsolates) {
      throw LSLException('Sync operations not available when using isolates');
    }
    return operation();
  }
}
