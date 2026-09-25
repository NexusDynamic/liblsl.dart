import 'dart:typed_data';

import 'byte_source_stub.dart'
    if (dart.library.io) 'byte_source_io.dart'
    if (dart.library.js_interop) 'byte_source_web.dart'
    as platform;

/// Random access to the bytes of a file, wherever they are: a path on
/// native platforms, a `Blob` (e.g. a picked `File`) on the web, or bytes
/// already in memory.
///
/// Used to read large recordings in pieces instead of all at once.
abstract interface class ByteSource {
  /// A name for display, e.g. the file name.
  String get name;

  /// Total number of bytes.
  int get length;

  /// Read up to [length] bytes starting at [offset]. Fewer bytes are
  /// returned only at the end of the source.
  Future<Uint8List> read(int offset, int length);

  /// Release the underlying file handle.
  Future<void> close();

  /// Bytes held in memory.
  factory ByteSource.bytes(Uint8List bytes, {String name}) = _BytesByteSource;

  /// A file on disk. Native platforms only.
  factory ByteSource.path(String path) => platform.openPath(path);

  /// A web `Blob` or `File` (from `package:web`), read with `Blob.slice`, so
  /// the file is never loaded as a whole. Web only.
  factory ByteSource.blob(Object blob, {String? name}) =>
      platform.openBlob(blob, name);
}

/// How to open an [ByteSource], in a form that can be sent to another
/// isolate (e.g. to open a recording in the background).
sealed class ByteSourceSpec {
  const ByteSourceSpec();

  /// A file on disk. Native platforms only.
  const factory ByteSourceSpec.path(String path) = PathSourceSpec;

  /// Bytes held in memory.
  const factory ByteSourceSpec.bytes(Uint8List bytes, {String name}) =
      BytesSourceSpec;

  /// A web `Blob` or `File`. It cannot be sent to another isolate, so it is
  /// always read in-process. Web only.
  const factory ByteSourceSpec.blob(Object blob, {String? name}) =
      BlobSourceSpec;

  /// Open the source.
  ByteSource open();
}

final class PathSourceSpec extends ByteSourceSpec {
  final String path;
  const PathSourceSpec(this.path);
  @override
  ByteSource open() => ByteSource.path(path);
}

final class BytesSourceSpec extends ByteSourceSpec {
  final Uint8List bytes;
  final String name;
  const BytesSourceSpec(this.bytes, {this.name = 'bytes'});
  @override
  ByteSource open() => ByteSource.bytes(bytes, name: name);
}

final class BlobSourceSpec extends ByteSourceSpec {
  final Object blob;
  final String? name;
  const BlobSourceSpec(this.blob, {this.name});
  @override
  ByteSource open() => ByteSource.blob(blob, name: name);
}

class _BytesByteSource implements ByteSource {
  final Uint8List _bytes;
  @override
  final String name;

  _BytesByteSource(this._bytes, {this.name = 'bytes'});

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final end = (offset + length).clamp(offset, _bytes.length);
    return Uint8List.sublistView(_bytes, offset, end);
  }

  @override
  Future<void> close() async {}
}
