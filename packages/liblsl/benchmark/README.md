# liblsl.dart benchmark suite

Benchmarks the Dart wrapper end-to-end over loopback: a producer and a
consumer exchange float32 samples and the consumer measures per-sample
latency plus achieved throughput, loss, and RSS growth.

The chunked consumers pull one pushed chunk at a time. Before liblsl 1.1.0
the bencmark asked for chunks of 256 samples with the outlet's `chunkSize`
set to 32, resulting in inaccurate measurements.


Results over time from CI: <https://nexusdynamic.org/liblsl.dart/dev/bench/>

## Running

From `packages/liblsl`:

```sh
dart run benchmark/bin/liblsl_benchmark.dart            # default matrix (~40 s)
dart run benchmark/bin/liblsl_benchmark.dart --smoke    # 2 quick scenarios
dart run benchmark/bin/liblsl_benchmark.dart --full     # extended matrix
dart run benchmark/bin/liblsl_benchmark.dart --repeat 3 --out bench.json
```

If the plain Dart VM cannot run the package on your platform, the same
matrix is available as a tagged test:

```sh
BENCHMARK_OUT=bench.json flutter test --tags benchmark test/liblsl_benchmark_test.dart
```

## Scenarios

Transport modes are tested with per-sample and chunked operations:

- `directSync` — `useIsolates: false` objects; producer and consumer each
  run in their own `Isolate.run` using the `*Sync` calls (the
  minimum-overhead configuration).
- `directSyncBlocking` — like `directSync`, but the outlet uses
  `LSLTransportOptions.syncBlocking` (zero-copy blocking socket writes).
- `isolateAsync` — `useIsolates: true` objects driven from the main isolate
  with the async API; measures the wrapper's isolate plumbing on top of
  transport cost.
- `eventStream` — a `directSync` producer received in the main isolate with
  `LSLInlet.sampleStream()` (per-sample) or `chunkStream()` (chunked).
   Regardless of the `useIsolates` setting, the event-drive samples will
   always add one extra isolate per inlet. (this is because the event-driven
   part of this relies on a blocking pull in liblsl, rather than a callback
   mechanism. The pull is time-limited so the thread can respond to stop
   requests, so depending on the interval setting, it might introduce a
   very small delay if that isolate becomes busy, but this is fairly
   negligable).

Chunked pushes blocks of `chunkSize` samples (default 32); all
samples in a block carry the same push-time timestamp, so their reported
latency includes the intrinsic block-accumulation delay, this is a
latency/throughput trade-off with chunking.

## Output

`--out` writes [github-action-benchmark](https://github.com/benchmark-action/github-action-benchmark)
`customSmallerIsBetter` JSON: per scenario `latency_p50`/`p95`/`p99` (µs)
and `time_per_sample` (µs/sample — inverse throughput, so smaller is
better in the same file). CI stores these on the `gh-pages` branch per
push/tag; see `.github/workflows/benchmark.yml`.
