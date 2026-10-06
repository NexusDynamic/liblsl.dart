import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:timing_core/timing_core.dart';

/// Where this device keeps its run logs.
class LogStore {
  LogStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  /// The downloads folder where the platform has one the app can write to,
  /// otherwise the app's documents.
  static Future<Directory> _defaultDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } on UnsupportedError {
      // No downloads folder on this platform.
    }
    return getApplicationDocumentsDirectory();
  }

  /// Writes the log of [header]'s run and returns the file.
  Future<File> save(RunHeader header, Uint8List content) async {
    final name = header.deviceName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(
      '${(await _directory()).path}/tt_${header.runId}_$name.xdf',
    );
    try {
      await file.create(recursive: true);
      await file.writeAsBytes(content);
      return file;
    } on FileSystemException {
      // Some platforms list a downloads folder the app may not write to.
      final fallback = File(
        '${(await getApplicationDocumentsDirectory()).path}/'
        'tt_${header.runId}_$name.xdf',
      );
      await fallback.create(recursive: true);
      await fallback.writeAsBytes(content);
      return fallback;
    }
  }
}
