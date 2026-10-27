import 'dart:io';

import 'package:signal_viewer/signal_viewer.dart';

import 'sd_target.dart';

SdTarget create(String name) => _FileTarget(name);

/// A file in a new temporary directory, left for the system to clear.
class _FileTarget implements SdTarget {
  final File file;
  late final IOSink _sink = file.openWrite();

  _FileTarget(String name)
    : file = File(
        '${Directory.systemTemp.createTempSync('cyton_sd').path}'
        '${Platform.pathSeparator}$name.xdf',
      );

  @override
  Sink<List<int>> get sink => _sink;

  @override
  Future<ByteSourceSpec> finish() async {
    await _sink.close();
    return ByteSourceSpec.path(file.path);
  }
}
