/// How the outlet/inlet pair is driven.
enum TransportMode {
  /// Direct FFI objects (`useIsolates: false`), producer and consumer each in
  /// their own isolate using `*Sync` calls.
  directSync,

  /// Wrapper-managed worker isolates (`useIsolates: true`) driven from the
  /// main isolate with the async API — measures the package's own isolate
  /// plumbing.
  isolateAsync,

  /// Like [directSync] but the outlet is created with
  /// `LSLTransportOptions.syncBlocking` (zero-copy blocking socket writes).
  directSyncBlocking,
}

/// Which operation is benchmarked.
enum OpKind {
  /// pushSample / pullSample, one native call per sample.
  sample,

  /// pushChunkTyped / pullChunkTyped with flat typed-data buffers.
  chunkTyped,

  /// pushChunk / pullChunk with `List<List<double>>` (convenience API).
  chunkList,
}

class ScenarioConfig {
  final TransportMode mode;
  final OpKind op;
  final int channels;
  final double rateHz;

  /// Samples per chunk push (chunk ops only).
  final int chunkSize;
  final double durationSeconds;

  const ScenarioConfig({
    required this.mode,
    required this.op,
    required this.channels,
    required this.rateHz,
    this.chunkSize = 32,
    this.durationSeconds = 3.0,
  });

  ScenarioConfig withDuration(double seconds) => ScenarioConfig(
    mode: mode,
    op: op,
    channels: channels,
    rateHz: rateHz,
    chunkSize: chunkSize,
    durationSeconds: seconds,
  );

  String get name {
    final opName = switch (op) {
      OpKind.sample => 'pushSample',
      OpKind.chunkTyped => 'pushChunkTyped$chunkSize',
      OpKind.chunkList => 'pushChunk$chunkSize',
    };
    return '${mode.name}/$opName/${channels}ch@${rateHz.toInt()}Hz';
  }
}

class BenchmarkConfig {
  final List<ScenarioConfig> scenarios;
  final int repeat;
  final String? outPath;

  const BenchmarkConfig({
    required this.scenarios,
    this.repeat = 1,
    this.outPath,
  });
}

const _defaultScenarios = [
  ScenarioConfig(
    mode: TransportMode.directSync,
    op: OpKind.sample,
    channels: 8,
    rateHz: 500,
  ),
  ScenarioConfig(
    mode: TransportMode.directSync,
    op: OpKind.chunkTyped,
    channels: 64,
    rateHz: 1000,
  ),
  ScenarioConfig(
    mode: TransportMode.directSyncBlocking,
    op: OpKind.sample,
    channels: 8,
    rateHz: 500,
  ),
  ScenarioConfig(
    mode: TransportMode.directSyncBlocking,
    op: OpKind.chunkTyped,
    channels: 64,
    rateHz: 1000,
  ),
  ScenarioConfig(
    mode: TransportMode.isolateAsync,
    op: OpKind.sample,
    channels: 8,
    rateHz: 500,
  ),
  ScenarioConfig(
    mode: TransportMode.isolateAsync,
    op: OpKind.chunkTyped,
    channels: 64,
    rateHz: 1000,
  ),
];

const _fullExtraScenarios = [
  ScenarioConfig(
    mode: TransportMode.directSync,
    op: OpKind.sample,
    channels: 1,
    rateHz: 1000,
  ),
  ScenarioConfig(
    mode: TransportMode.directSync,
    op: OpKind.chunkList,
    channels: 64,
    rateHz: 1000,
  ),
  ScenarioConfig(
    mode: TransportMode.directSyncBlocking,
    op: OpKind.sample,
    channels: 64,
    rateHz: 1000,
  ),
  ScenarioConfig(
    mode: TransportMode.isolateAsync,
    op: OpKind.chunkList,
    channels: 64,
    rateHz: 1000,
  ),
];

/// Parses CLI arguments; returns null (after printing usage) on `--help` or
/// an unknown option.
BenchmarkConfig? parseArgs(List<String> args) {
  var smoke = false;
  var full = false;
  var repeat = 1;
  double? duration;
  String? outPath;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--smoke':
        smoke = true;
      case '--full':
        full = true;
      case '--repeat':
        repeat = int.parse(args[++i]);
      case '--duration':
        duration = double.parse(args[++i]);
      case '--out':
        outPath = args[++i];
      case '--help':
      case '-h':
      default:
        print(
          'Usage: dart run benchmark/bin/liblsl_benchmark.dart '
          '[--smoke] [--full] [--repeat N] [--duration SECONDS] '
          '[--out results.json]',
        );
        return null;
    }
  }

  var scenarios = [..._defaultScenarios, if (full) ..._fullExtraScenarios];
  if (smoke) {
    scenarios = [
      _defaultScenarios[0].withDuration(1.0),
      _defaultScenarios[1].withDuration(1.0),
    ];
  } else if (duration != null) {
    scenarios = [for (final s in scenarios) s.withDuration(duration)];
  }
  return BenchmarkConfig(
    scenarios: scenarios,
    repeat: repeat,
    outPath: outPath,
  );
}
