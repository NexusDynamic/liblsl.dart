import 'dart:async';
import 'dart:io' show ProcessInfo, sleep;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:liblsl/lsl.dart';
import 'package:liblsl/native_liblsl.dart' show lsl_outlet;

import 'config.dart';
import 'stats.dart';

/// Applies the loopback-only LSL configuration used for benchmarking.
void configureLsl({String? sessionId}) {
  final apiConfig = LSLApiConfig(
    ipv6: IPv6Mode.disable,
    resolveScope: ResolveScope.link,
    listenAddress: '127.0.0.1',
    addressesOverride: ['224.0.0.183'],
    knownPeers: ['127.0.0.1'],
    sessionId:
        sessionId ??
        'LSLBench${DateTime.now().millisecondsSinceEpoch % 100000}',
    unicastMinRTT: 0.1,
    multicastMinRTT: 0.1,
    portRange: 64,
    watchdogCheckInterval: 600.0,
    outletBufferReserveMs: 2000,
    inletBufferReserveMs: 2000,
  );
  LSL.setConfigContent(apiConfig);
}

/// Runs every scenario in [config] and returns one merged result per
/// scenario (repeats are pooled: counts summed, latencies merged).
Future<List<ScenarioResult>> runBenchmarks(
  BenchmarkConfig config, {
  void Function(String message)? log,
}) async {
  final results = <ScenarioResult>[];
  for (final scenario in config.scenarios) {
    var sent = 0;
    var received = 0;
    var duration = 0.0;
    var rssDelta = 0;
    final latency = LatencyStats();
    for (int rep = 0; rep < config.repeat; rep++) {
      log?.call(
        'Running ${scenario.name}'
        '${config.repeat > 1 ? ' (rep ${rep + 1}/${config.repeat})' : ''}...',
      );
      final run = scenario.mode == TransportMode.isolateAsync
          ? await _runIsolateAsyncScenario(scenario, rep)
          : await _runDirectScenario(scenario, rep);
      sent += run.samplesSent;
      received += run.samplesReceived;
      duration += run.durationSeconds;
      rssDelta += run.rssDeltaBytes;
      latency.addAll(run.latencies);
    }
    results.add(
      ScenarioResult(
        name: scenario.name,
        samplesSent: sent,
        samplesReceived: received,
        durationSeconds: duration,
        latency: latency,
        rssDeltaBytes: rssDelta,
      ),
    );
  }
  return results;
}

class _RunOutcome {
  final int samplesSent;
  final int samplesReceived;
  final double durationSeconds;
  final Float64List latencies;
  final int rssDeltaBytes;

  _RunOutcome(
    this.samplesSent,
    this.samplesReceived,
    this.durationSeconds,
    this.latencies,
    this.rssDeltaBytes,
  );
}

int _streamCounter = 0;

/// Direct-mode scenario: producer and consumer each run in their own
/// isolate with `useIsolates: false` objects recreated from pointers
/// (the pattern proven in test/liblsl_performance_test.dart).
Future<_RunOutcome> _runDirectScenario(ScenarioConfig cfg, int rep) async {
  final name = 'Bench_${_streamCounter++}_$rep';
  final info = await LSL.createStreamInfo(
    streamName: name,
    channelCount: cfg.channels,
    channelFormat: LSLChannelFormat.float32,
    sampleRate: cfg.rateHz,
    streamType: LSLContentType.eeg,
    sourceId: '${name}_src',
  );
  final outlet = await LSL.createOutlet(
    streamInfo: info,
    transportOptions: cfg.mode == TransportMode.directSyncBlocking
        ? {LSLTransportOptions.syncBlocking}
        : const {},
    useIsolates: false,
  );

  final infoAddr = info.streamInfo.address;
  final outletAddr = outlet.outlet.address;
  final channels = cfg.channels;
  final rateHz = cfg.rateHz;
  final chunkSize = cfg.chunkSize;
  final durationSeconds = cfg.durationSeconds;
  final op = cfg.op;

  final rssBefore = ProcessInfo.currentRss;

  final consumerFuture = Isolate.run(
    () => _directConsumer(infoAddr, channels, durationSeconds, op),
  );
  // Give the consumer a head start to connect before producing.
  final producerFuture = Isolate.run(
    () => _directProducer(
      infoAddr,
      outletAddr,
      channels,
      rateHz,
      chunkSize,
      durationSeconds,
      op,
    ),
  );

  final sent = await producerFuture;
  final consumer = await consumerFuture;
  final rssAfter = ProcessInfo.currentRss;

  await outlet.destroy();
  info.destroy();

  return _RunOutcome(
    sent,
    consumer['received'] as int,
    durationSeconds,
    consumer['latencies'] as Float64List,
    rssAfter - rssBefore,
  );
}

/// Busy-waits (with coarse 1 ms sleeps while far away) until the LSL clock
/// reaches [deadline]. Runs inside worker isolates only.
void _waitUntil(double deadline) {
  while (true) {
    final remaining = deadline - LSL.localClock();
    if (remaining <= 0) return;
    if (remaining > 0.002) {
      sleep(const Duration(milliseconds: 1));
    }
    // Otherwise spin: the last <2 ms are burned for pacing precision.
  }
}

Future<int> _directProducer(
  int infoAddr,
  int outletAddr,
  int channels,
  double rateHz,
  int chunkSize,
  double durationSeconds,
  OpKind op,
) async {
  final info = LSLStreamInfo.fromStreamInfoAddr(infoAddr);
  final outlet = await LSLOutlet(
    info,
    useIsolates: false,
  ).createFromPointer(lsl_outlet.fromAddress(outletAddr));

  if (!outlet.waitForConsumerSync(timeout: 10.0)) {
    await outlet.destroy();
    throw StateError('Benchmark consumer did not connect within 10 s');
  }

  var sent = 0;
  final start = LSL.localClock();
  final end = start + durationSeconds;

  switch (op) {
    case OpKind.sample:
      final sample = List<double>.filled(channels, 42.0);
      final interval = 1.0 / rateHz;
      var next = start;
      while (true) {
        next += interval;
        if (next > end) break;
        _waitUntil(next);
        sample[0] = LSL.localClock();
        outlet.pushSampleSync(sample);
        sent++;
      }
    case OpKind.chunkTyped:
      final chunk = Float32List(chunkSize * channels);
      final interval = chunkSize / rateHz;
      var next = start;
      while (true) {
        next += interval;
        if (next > end) break;
        _waitUntil(next);
        final now = LSL.localClock();
        for (int s = 0; s < chunkSize; s++) {
          chunk[s * channels] = now;
        }
        outlet.pushChunkTypedSync(chunk);
        sent += chunkSize;
      }
    case OpKind.chunkList:
      final chunk = List.generate(
        chunkSize,
        (_) => List<double>.filled(channels, 42.0),
      );
      final interval = chunkSize / rateHz;
      var next = start;
      while (true) {
        next += interval;
        if (next > end) break;
        _waitUntil(next);
        final now = LSL.localClock();
        for (final sample in chunk) {
          sample[0] = now;
        }
        outlet.pushChunkSync(chunk);
        sent += chunkSize;
      }
  }

  // Only frees wrapper-internal buffers; the native outlet is owned by the
  // main isolate (createFromPointer semantics).
  await outlet.destroy();
  return sent;
}

Future<Map<String, Object>> _directConsumer(
  int infoAddr,
  int channels,
  double durationSeconds,
  OpKind op,
) async {
  final info = LSLStreamInfo.fromStreamInfoAddr(infoAddr);
  final inlet = LSLInlet<double>(
    info,
    maxBuffer: 1,
    recover: false,
    useIsolates: false,
  );
  await inlet.create();

  final latencies = <double>[];
  var received = 0;
  final start = LSL.localClock();
  final hardDeadline = start + durationSeconds + 4.0;
  var lastData = start + durationSeconds;

  while (true) {
    final now = LSL.localClock();
    if (now > hardDeadline) break;
    if (received > 0 && now - lastData > 1.0) break;

    switch (op) {
      case OpKind.sample:
        final sample = inlet.pullSampleSync(timeout: 0.02);
        if (sample.isNotEmpty) {
          received++;
          lastData = LSL.localClock();
          latencies.add((lastData - sample[0]) * 1e6);
        }
      case OpKind.chunkTyped:
        final chunk = inlet.pullChunkTypedSync(maxSamples: 256, timeout: 0.02);
        if (chunk.isNotEmpty) {
          received += chunk.sampleCount;
          lastData = LSL.localClock();
          final data = chunk.data as Float32List;
          for (int s = 0; s < chunk.sampleCount; s++) {
            latencies.add((lastData - data[s * channels]) * 1e6);
          }
        }
      case OpKind.chunkList:
        final chunk = inlet.pullChunkSync(maxSamples: 256, timeout: 0.02);
        if (chunk.isNotEmpty) {
          received += chunk.sampleCount;
          lastData = LSL.localClock();
          for (final sample in chunk.samples) {
            latencies.add((lastData - sample[0]) * 1e6);
          }
        }
    }
  }

  await inlet.destroy();
  return {'received': received, 'latencies': Float64List.fromList(latencies)};
}

/// isolateAsync scenario: wrapper-managed worker isolates driven from the
/// main isolate through the async API. Measures the package's own isolate
/// message-passing overhead on top of transport latency.
Future<_RunOutcome> _runIsolateAsyncScenario(
  ScenarioConfig cfg,
  int rep,
) async {
  final name = 'Bench_${_streamCounter++}_$rep';
  final info = await LSL.createStreamInfo(
    streamName: name,
    channelCount: cfg.channels,
    channelFormat: LSLChannelFormat.float32,
    sampleRate: cfg.rateHz,
    streamType: LSLContentType.eeg,
    sourceId: '${name}_src',
  );
  final outlet = await LSL.createOutlet(streamInfo: info, useIsolates: true);

  await Future.delayed(const Duration(milliseconds: 100));
  final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 16);
  LSLStreamInfo? resolved;
  for (final s in streams) {
    if (s.streamName == name) {
      resolved = s;
    } else {
      s.destroy();
    }
  }
  if (resolved == null) {
    await outlet.destroy();
    info.destroy();
    throw StateError('Benchmark stream $name did not resolve');
  }
  final inlet = await LSL.createInlet<double>(
    streamInfo: resolved,
    recover: false,
    useIsolates: true,
  );
  if (!await outlet.waitForConsumer(timeout: 10.0)) {
    throw StateError('Benchmark consumer did not connect within 10 s');
  }

  final rssBefore = ProcessInfo.currentRss;
  final latencies = <double>[];
  var sent = 0;
  var received = 0;
  final channels = cfg.channels;
  final start = LSL.localClock();
  final end = start + cfg.durationSeconds;

  Future<void> producer() async {
    switch (cfg.op) {
      case OpKind.sample:
        final sample = List<double>.filled(channels, 42.0);
        final interval = 1.0 / cfg.rateHz;
        var next = start;
        while (true) {
          next += interval;
          if (next > end) break;
          final waitUs = ((next - LSL.localClock()) * 1e6).round();
          if (waitUs > 0) {
            await Future.delayed(Duration(microseconds: waitUs));
          }
          sample[0] = LSL.localClock();
          await outlet.pushSample(sample);
          sent++;
        }
      case OpKind.chunkTyped:
        final f32 = Float32List(cfg.chunkSize * channels);
        final interval = cfg.chunkSize / cfg.rateHz;
        var next = start;
        while (true) {
          next += interval;
          if (next > end) break;
          final waitUs = ((next - LSL.localClock()) * 1e6).round();
          if (waitUs > 0) {
            await Future.delayed(Duration(microseconds: waitUs));
          }
          final now = LSL.localClock();
          for (int s = 0; s < cfg.chunkSize; s++) {
            f32[s * channels] = now;
          }
          await outlet.pushChunkTyped(f32);
          sent += cfg.chunkSize;
        }
      case OpKind.chunkList:
        final chunk = List.generate(
          cfg.chunkSize,
          (_) => List<double>.filled(channels, 42.0),
        );
        final interval = cfg.chunkSize / cfg.rateHz;
        var next = start;
        while (true) {
          next += interval;
          if (next > end) break;
          final waitUs = ((next - LSL.localClock()) * 1e6).round();
          if (waitUs > 0) {
            await Future.delayed(Duration(microseconds: waitUs));
          }
          final now = LSL.localClock();
          for (final sample in chunk) {
            sample[0] = now;
          }
          await outlet.pushChunk(chunk);
          sent += cfg.chunkSize;
        }
    }
  }

  Future<void> consumer() async {
    final hardDeadline = start + cfg.durationSeconds + 4.0;
    var lastData = start + cfg.durationSeconds;
    while (true) {
      final now = LSL.localClock();
      if (now > hardDeadline) break;
      if (received > 0 && now - lastData > 1.0) break;
      switch (cfg.op) {
        case OpKind.sample:
          final sample = await inlet.pullSample(timeout: 0.02);
          if (sample.isNotEmpty) {
            received++;
            lastData = LSL.localClock();
            latencies.add((lastData - sample[0]) * 1e6);
          }
        case OpKind.chunkTyped:
          final chunk = await inlet.pullChunkTyped(
            maxSamples: 256,
            timeout: 0.02,
          );
          if (chunk.isNotEmpty) {
            received += chunk.sampleCount;
            lastData = LSL.localClock();
            final data = chunk.data as Float32List;
            for (int s = 0; s < chunk.sampleCount; s++) {
              latencies.add((lastData - data[s * channels]) * 1e6);
            }
          }
        case OpKind.chunkList:
          final chunk = await inlet.pullChunk(maxSamples: 256, timeout: 0.02);
          if (chunk.isNotEmpty) {
            received += chunk.sampleCount;
            lastData = LSL.localClock();
            for (final sample in chunk.samples) {
              latencies.add((lastData - sample[0]) * 1e6);
            }
          }
      }
    }
  }

  await Future.wait([producer(), consumer()]);
  final rssAfter = ProcessInfo.currentRss;

  await inlet.destroy();
  await outlet.destroy();
  resolved.destroy();
  info.destroy();

  return _RunOutcome(
    sent,
    received,
    cfg.durationSeconds,
    Float64List.fromList(latencies),
    math.max(0, rssAfter - rssBefore),
  );
}
