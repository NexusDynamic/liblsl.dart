/// XDF (Extensible Data Format), the file format of LabRecorder and the
/// Lab Streaming Layer.
///
/// - [loadXdf] reads a whole file into memory, like pyxdf's `load_xdf`
///   (clock synchronisation, clock reset handling and jitter removal with
///   pyxdf's algorithms and defaults).
/// - [readChunks] and [readSamples] give the raw chunks.
///
/// Pure Dart; works on all platforms, including the web.
library;

export 'src/chunks.dart';
export 'src/format.dart';
export 'src/load.dart';
export 'src/stream_info.dart';
export 'src/sync.dart';
export 'src/writer.dart';
export 'src/xdf_file.dart';
