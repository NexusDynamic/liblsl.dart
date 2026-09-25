import 'byte_source.dart';

ByteSource openPath(String path) =>
    throw UnsupportedError('Files by path are not supported on this platform');

ByteSource openBlob(Object blob, String? name) =>
    throw UnsupportedError('Blobs are only supported on the web');
