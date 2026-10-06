/// Record format and analysis for transport timing runs.
///
/// Each device writes one log per run with [RunLogWriter]; [analyse] turns
/// the logs of a run into a [Report] of latency, jitter, loss, clock offset
/// and drift per sender and receiver.
///
/// Pure Dart; works on all platforms, including the web.
library;

export 'src/analysis.dart';
export 'src/format.dart';
export 'src/record.dart';
export 'src/report.dart';
export 'src/stats.dart';
