import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'byte_source.dart';

ByteSource openPath(String path) =>
    throw UnsupportedError('Files by path are not supported on the web');

ByteSource openBlob(Object blob, String? name) {
  final b = blob as web.Blob;
  return _BlobByteSource(
    b,
    name ?? (b.isA<web.File>() ? (b as web.File).name : 'blob'),
  );
}

class _BlobByteSource implements ByteSource {
  final web.Blob _blob;
  @override
  final String name;

  _BlobByteSource(this._blob, this.name);

  @override
  int get length => _blob.size;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final end = (offset + length).clamp(offset, _blob.size);
    final buffer = await _blob.slice(offset, end).arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Future<void> close() async {}
}
