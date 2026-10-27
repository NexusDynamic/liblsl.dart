import 'package:signal_viewer/signal_viewer.dart';

import 'sd_target_memory.dart'
    if (dart.library.io) 'sd_target_io.dart'
    as platform;

/// Where a converted SD card recording goes: a temporary file where there
/// are files, memory otherwise (the web).
abstract class SdTarget {
  Sink<List<int>> get sink;

  /// Done writing: where to read it from.
  Future<ByteSourceSpec> finish();

  static SdTarget create(String name) => platform.create(name);
}
