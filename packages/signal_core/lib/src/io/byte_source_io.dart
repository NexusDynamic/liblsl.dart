import 'dart:io';
import 'dart:typed_data';

import 'byte_source.dart';

ByteSource openPath(String path) => _FileByteSource(path);

ByteSource openBlob(Object blob, String? name) =>
    throw UnsupportedError('Blobs are only supported on the web');

/// Reads with synchronous calls on a [RandomAccessFile]: the reads are small
/// and usually run in a background isolate, and synchronous calls cannot
/// overlap the way pending asynchronous ones would.
class _FileByteSource implements ByteSource {
  final RandomAccessFile _file;
  @override
  final String name;
  @override
  final int length;

  _FileByteSource._(this._file, this.name, this.length);

  factory _FileByteSource(String path) {
    final file = File(path).openSync();
    return _FileByteSource._(
      file,
      path.split(Platform.pathSeparator).last,
      file.lengthSync(),
    );
  }

  @override
  Future<Uint8List> read(int offset, int length) async {
    final n = (length).clamp(0, this.length - offset);
    final out = Uint8List(n);
    _file.setPositionSync(offset);
    var done = 0;
    while (done < n) {
      final r = _file.readIntoSync(out, done, n);
      if (r == 0) break;
      done += r;
    }
    return done == n ? out : Uint8List.sublistView(out, 0, done);
  }

  @override
  Future<void> close() async => _file.closeSync();
}
