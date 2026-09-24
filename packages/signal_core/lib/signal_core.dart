/// Format-agnostic multichannel signal engine: summary pyramids for fast
/// zooming, display filters, re-referencing, channel quality, and random
/// access to the bytes of large recordings.
///
/// Pure Dart; everything here works on all platforms, including the web.
library;

export 'src/dsp/live_processor.dart';
export 'src/dsp/quality.dart';
export 'src/dsp/sos.dart';
export 'src/engine/chunked_engine.dart';
export 'src/engine/chunked_index.dart';
export 'src/io/byte_source.dart';
export 'src/pyramid.dart';
export 'src/requests.dart';
export 'src/util/list_prefix.dart';
