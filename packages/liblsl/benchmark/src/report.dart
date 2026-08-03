import 'dart:convert';
import 'dart:io';

import 'stats.dart';

/// Prints a human-readable summary table.
void printReport(List<ScenarioResult> results) {
  String pad(String s, int w) => s.padRight(w);
  String num_(double v) => v.toStringAsFixed(1).padLeft(9);

  print('');
  print('=' * 118);
  print(
    '${pad('Scenario', 44)}'
    '${'sent'.padLeft(8)}${'recv'.padLeft(8)}${'rate/s'.padLeft(9)}'
    '${'loss%'.padLeft(7)}'
    '${'p50µs'.padLeft(10)}${'p95µs'.padLeft(10)}${'p99µs'.padLeft(10)}'
    '${'meanµs'.padLeft(10)}${'ΔRSS MiB'.padLeft(10)}',
  );
  print('-' * 118);
  for (final r in results) {
    print(
      '${pad(r.name, 44)}'
      '${r.samplesSent.toString().padLeft(8)}'
      '${r.samplesReceived.toString().padLeft(8)}'
      '${r.achievedRateHz.toStringAsFixed(0).padLeft(9)}'
      '${r.lossPercent.toStringAsFixed(1).padLeft(7)}'
      '${num_(r.latency.p50)}'
      '${num_(r.latency.p95)}'
      '${num_(r.latency.p99)}'
      '${num_(r.latency.mean)}'
      '${(r.rssDeltaBytes / (1024 * 1024)).toStringAsFixed(1).padLeft(10)}',
    );
  }
  print('=' * 118);
  print('Peak RSS: ${(ProcessInfo.maxRss / (1024 * 1024)).round()} MiB');
}

/// Writes github-action-benchmark `customSmallerIsBetter` JSON.
///
/// Throughput is encoded as its inverse (µs/sample) so a single
/// smaller-is-better file covers both latency and throughput trends.
void writeBenchmarkJson(List<ScenarioResult> results, String path) {
  final entries = <Map<String, dynamic>>[];
  for (final r in results) {
    entries.addAll([
      {
        'name': '${r.name} latency_p50',
        'unit': 'us',
        'value': r.latency.p50,
        'extra': 'n=${r.latency.count}',
      },
      {'name': '${r.name} latency_p95', 'unit': 'us', 'value': r.latency.p95},
      {'name': '${r.name} latency_p99', 'unit': 'us', 'value': r.latency.p99},
      {
        'name': '${r.name} time_per_sample',
        'unit': 'us/sample',
        'value': r.timePerSampleUs,
        'extra':
            '${r.achievedRateHz.toStringAsFixed(0)} samples/s, '
            'loss ${r.lossPercent.toStringAsFixed(1)}%',
      },
    ]);
  }
  File(
    path,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
  print('Wrote ${entries.length} benchmark entries to $path');
}
