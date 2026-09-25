@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/src/config.dart';
import '../benchmark/src/report.dart';
import '../benchmark/src/scenarios.dart';

/// Fallback benchmark runner for environments where the plain Dart VM
/// cannot execute the package (CI normally uses
/// `dart run benchmark/bin/liblsl_benchmark.dart` instead).
///
/// Run with: flutter test --tags benchmark test/liblsl_benchmark_test.dart
/// Output path comes from the BENCHMARK_OUT env var (default: bench.json).
void main() {
  test('benchmark matrix', () async {
    configureLsl();
    final outPath = Platform.environment['BENCHMARK_OUT'] ?? 'bench.json';
    final smoke = Platform.environment['BENCHMARK_SMOKE'] == '1';
    final config = parseArgs([if (smoke) '--smoke', '--out', outPath])!;

    final results = await runBenchmarks(config, log: print);
    printReport(results);
    writeBenchmarkJson(results, outPath);

    expect(results, isNotEmpty);
    for (final result in results) {
      expect(
        result.samplesReceived,
        greaterThan(0),
        reason: '${result.name} received no samples',
      );
    }
  }, timeout: Timeout(Duration(minutes: 15)));
}
