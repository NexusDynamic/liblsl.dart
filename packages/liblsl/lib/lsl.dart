/// The liblsl.dart Library for LSL (Lab Streaming Layer) functionality.
library;

export 'package:liblsl/src/lsl/structs.dart';
export 'package:liblsl/src/lsl/stream_info.dart';
export 'package:liblsl/src/lsl/outlet.dart' show LSLOutlet;
export 'package:liblsl/src/lsl/inlet.dart' show LSLInlet;
export 'package:liblsl/src/lsl/stream_resolver.dart';
export 'package:liblsl/src/lsl/sample.dart' show LSLSample;
export 'package:liblsl/src/lsl.dart';
export 'package:liblsl/src/lsl/exception.dart';
export 'package:liblsl/src/lsl/api_config.dart';
export 'package:liblsl/src/util/precise_scheduling.dart'
    show runPreciseInterval, runPreciseIntervalAsync;
