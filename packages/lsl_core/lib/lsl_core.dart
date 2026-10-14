/// Pure-Dart Lab Streaming Layer types and utilities.
///
/// Everything here works without liblsl, including on the web:
/// channel formats and a value codec for them, samples and chunks, clock
/// offsets and the chain of hops a time stamp crossed, the API
/// configuration, and receiving and polling helpers. `package:liblsl`
/// re-exports the `LSL*` types and adds their FFI side.
library;

export 'src/api_config.dart';
export 'src/chunk.dart';
export 'src/clock/clock_hop.dart';
export 'src/clock/clock_model.dart';
export 'src/clock/clock_offset.dart';
export 'src/exception.dart';
export 'src/format.dart';
export 'src/polling/precise_interval.dart';
export 'src/sample.dart';
export 'src/stream_meta.dart';
export 'src/time_correction.dart';
export 'src/timed.dart';
export 'src/values.dart';
export 'src/facade/receive.dart';
export 'src/facade/types.dart';
export 'src/polling/listener_restart_schedule.dart';
export 'src/polling/time_correction_schedule.dart';
export 'src/facade/drain.dart';
export 'src/info_xml.dart';
