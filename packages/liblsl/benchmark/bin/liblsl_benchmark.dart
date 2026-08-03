import 'dart:io';

import 'package:liblsl/lsl.dart';

import '../src/config.dart';
import '../src/report.dart';
import '../src/scenarios.dart';

/// Standalone LSL benchmark runner.
///
/// Usage (from packages/liblsl):
///   dart run benchmark/bin/liblsl_benchmark.dart [--smoke|--full]
///       [--repeat N] [--duration SECONDS] [--out results.json]
Future<void> main(List<String> args) async {
  final config = parseArgs(args);
  if (config == null) {
    exitCode = 64;
    return;
  }

  configureLsl();
  final estimated = config.scenarios.fold<double>(
    0,
    (acc, s) => acc + (s.durationSeconds + 3) * config.repeat,
  );
  print('liblsl benchmark — LSL library version ${LSL.version}');
  print(
    '${config.scenarios.length} scenario(s), repeat ${config.repeat}, '
    '~${estimated.round()} s estimated',
  );

  final results = await runBenchmarks(config, log: print);
  printReport(results);

  final outPath = config.outPath;
  if (outPath != null) {
    writeBenchmarkJson(results, outPath);
  }
}
