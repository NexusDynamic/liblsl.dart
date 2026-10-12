import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:liblsl/lsl.dart';
import 'package:timing_core/timing_core.dart';

import 'settings.dart';

/// Seconds between a run being announced and the first sample: time for
/// every device to publish its outlet, find the others' and get a first
/// clock offset for each.
const double _lead = 8;

/// Seconds the inlets stay open after the last sample is due.
const double _drain = 1;

String _sourcePrefix(String runId) => 'tt//$runId//';

/// A latency run on liblsl itself, with no coordinator in the data path.
///
/// This device publishes one outlet and opens an inlet to every device's
/// outlet, its own included (that pair is the no-network baseline). Each
/// outlet and inlet has an isolate to itself, which keeps what it measures
/// in memory and hands it over when the run ends, so nothing but the
/// transfer under test happens while samples flow.
///
/// Completes when the run is over and [log] holds its rows.
Future<void> runRawLsl({
  required RunConfig config,
  required String nodeUId,
  required int expectedNodes,
  required RunLogWriter log,
  void Function(String status)? onStatus,
}) async {
  final start = LSL.localClock() + _lead;
  final end = start + config.durationSeconds;
  final prefix = _sourcePrefix(config.runId);

  final info = await LSL.createStreamInfo(
    streamName: 'tt_${config.runId}',
    streamType: LSLContentType.custom('Timing'),
    channelCount: config.channels,
    sampleRate: config.sampleRate,
    channelFormat: LSLChannelFormat.double64,
    sourceId: '$prefix$nodeUId',
  );
  var resolved = <LSLStreamInfo>[];
  try {
    final outletArgs = _OutletArgs(
      infoAddress: info.streamInfo.address,
      sampleRate: config.sampleRate,
      channels: config.channels,
      sendMode: config.sendMode,
      startClock: start,
      endClock: end,
    );
    final sent = Isolate.run(() => _outletMain(outletArgs));

    onStatus?.call('Finding streams');
    // The other devices heard about the run at about the same moment; give
    // their outlets a second to appear before asking.
    await Future<void>.delayed(const Duration(seconds: 1));
    resolved = await LSL.resolveStreamsByPredicate(
      predicate: "starts-with(source_id,'$prefix')",
      waitTime: 4,
      minStreamCount: expectedNodes,
      maxStreams: 64,
    );

    // A device whose stream was not found is one this device will have
    // nothing from: the log says so, or the report could only leave it out.
    log.event(LSL.localClock(), 'resolved', {
      'expected': expectedNodes,
      'found': [
        for (final stream in resolved) stream.sourceId.substring(prefix.length),
      ],
    });
    onStatus?.call(
      resolved.length < expectedNodes
          ? 'Running: found only ${resolved.length} of $expectedNodes streams'
          : 'Running (${resolved.length} streams)',
    );
    final received = [
      for (final stream in resolved)
        () {
          final inletArgs = _InletArgs(
            infoAddress: stream.streamInfo.address,
            receiveMode: config.receiveMode,
            pollIntervalMicros: config.pollIntervalMicros,
            endClock: end + _drain,
            expectedSamples: (config.sampleRate * config.durationSeconds)
                .ceil(),
          );
          return Isolate.run(() => _inletMain(inletArgs));
        }(),
    ];

    final sentResult = await sent;
    for (var i = 0; i < sentResult.seq.length; i++) {
      log.sent(sentResult.seq[i], sentResult.clock[i]);
    }
    for (final (index, result) in (await Future.wait(received)).indexed) {
      final source = resolved[index].sourceId.substring(prefix.length);
      for (var i = 0; i < result.syncClock.length; i++) {
        log.clockSync(
          source,
          receivedClock: result.syncClock[i],
          offset: result.syncOffset[i],
          remoteTime: result.syncRemoteTime[i],
          uncertainty: result.syncUncertainty[i],
          clockReset: result.syncReset[i],
        );
      }
      final failed = result.errorCode;
      if (failed != null) {
        log.event(result.errorClock, 'receive_error', {
          'from': source,
          'code': failed,
        });
      }
      for (var i = 0; i < result.seq.length; i++) {
        log.received(
          source,
          result.seq[i],
          receivedClock: result.receivedClock[i],
          sourceClock: result.sourceClock[i],
          clockOffset: result.clockOffset[i],
          uncertainty: result.uncertainty[i],
        );
      }
    }
  } finally {
    for (final stream in resolved) {
      stream.destroy();
    }
    info.destroy();
  }
}

final class _OutletArgs {
  final int infoAddress;
  final double sampleRate;
  final int channels;
  final SendMode sendMode;
  final double startClock;
  final double endClock;

  const _OutletArgs({
    required this.infoAddress,
    required this.sampleRate,
    required this.channels,
    required this.sendMode,
    required this.startClock,
    required this.endClock,
  });
}

final class _Sent {
  final Int32List seq;
  final Float64List clock;
  const _Sent(this.seq, this.clock);
}

Future<_Sent> _outletMain(_OutletArgs args) async {
  final outlet = LSLOutlet(
    LSLStreamInfo.fromStreamInfoAddr(args.infoAddress),
    chunkSize: 1,
    transportOptions: {
      if (args.sendMode == SendMode.syncBlocking)
        LSLTransportOptions.syncBlocking,
    },
    useIsolates: args.sendMode == SendMode.async,
  );
  await outlet.create();

  // Room for the whole run from the start: a list that grows as it fills
  // copies itself now and then, in the middle of what is being timed.
  final expected =
      ((args.endClock - args.startClock) * args.sampleRate).ceil() + 1;
  final seqs = _Ints(expected);
  final clocks = _Doubles(expected);
  final sample = List<double>.filled(args.channels, 0);
  final interval = Duration(microseconds: (1e6 / args.sampleRate).round());
  // Sleep through most of a long interval; spin through a short one, where
  // a sleep's millisecond resolution would be the jitter.
  final startBusyAt = interval > const Duration(milliseconds: 4)
      ? const Duration(milliseconds: 2)
      : interval;
  final done = Completer<void>();
  var seq = 0;

  final wait = args.startClock - LSL.localClock();
  if (wait > 0) sleep(Duration(microseconds: (wait * 1e6).round()));

  // The clock read before the push is the sample's time stamp. Left to
  // itself liblsl stamps a sample when it gets it, which for an async push
  // is after the hop to the outlet's isolate: that hop would then be
  // missing from this mode's latency and in every other mode's.
  if (args.sendMode == SendMode.async) {
    await runPreciseIntervalAsync<void>(
      interval,
      (_) async {
        sample[0] = (++seq).toDouble();
        final clock = LSL.localClock();
        await outlet.pushSample(sample, timestamp: clock);
        seqs.add(seq);
        clocks.add(clock);
        if (clock >= args.endClock) done.complete();
      },
      completer: done,
      startBusyAt: startBusyAt,
      sw: Stopwatch(),
    );
  } else {
    runPreciseInterval<void>(
      interval,
      (_) {
        sample[0] = (++seq).toDouble();
        final clock = LSL.localClock();
        outlet.pushSampleSync(sample, timestamp: clock);
        seqs.add(seq);
        clocks.add(clock);
        if (clock >= args.endClock) done.complete();
      },
      completer: done,
      startBusyAt: startBusyAt,
      sw: Stopwatch(),
    );
  }

  // The outlet outlives every inlet's drain, or they would see the stream
  // break off and try to recover it.
  sleep(Duration(milliseconds: ((_drain + 0.5) * 1000).round()));
  await outlet.destroy();
  return _Sent(seqs.take(), clocks.take());
}

/// A column of a run's measurements, with room for [expected] of them from
/// the start and growing only if there turn out to be more.
final class _Doubles {
  _Doubles(int expected) : _values = Float64List(expected + _margin);

  Float64List _values;
  int length = 0;

  void add(double value) {
    if (length == _values.length) {
      _values = Float64List(length * 2)..setRange(0, length, _values);
    }
    _values[length++] = value;
  }

  Float64List take() => Float64List.sublistView(_values, 0, length);
}

final class _Ints {
  _Ints(int expected) : _values = Int32List(expected + _margin);

  Int32List _values;
  int length = 0;

  void add(int value) {
    if (length == _values.length) {
      _values = Int32List(length * 2)..setRange(0, length, _values);
    }
    _values[length++] = value;
  }

  Int32List take() => Int32List.sublistView(_values, 0, length);
}

/// Room beyond the samples a run is expected to have.
const int _margin = 1024;

final class _InletArgs {
  final int infoAddress;
  final ReceiveMode receiveMode;
  final int pollIntervalMicros;
  final double endClock;
  final int expectedSamples;

  const _InletArgs({
    required this.infoAddress,
    required this.receiveMode,
    required this.pollIntervalMicros,
    required this.endClock,
    required this.expectedSamples,
  });
}

final class _Received {
  final Int32List seq;
  final Float64List sourceClock;
  final Float64List receivedClock;
  final Float64List clockOffset;
  final Float64List uncertainty;
  final Float64List syncClock;
  final Float64List syncOffset;
  final Float64List syncRemoteTime;
  final Float64List syncUncertainty;
  final List<bool> syncReset;

  /// The liblsl error that ended receiving before the run did, and when;
  /// null when it ran to the end.
  final int? errorCode;
  final double errorClock;

  const _Received({
    required this.seq,
    required this.sourceClock,
    required this.receivedClock,
    required this.clockOffset,
    required this.uncertainty,
    required this.syncClock,
    required this.syncOffset,
    required this.syncRemoteTime,
    required this.syncUncertainty,
    required this.syncReset,
    this.errorCode,
    this.errorClock = 0,
  });
}

/// liblsl's `lsl_timeout_error`: nothing arrived in time, which is not a
/// failure.
const int _lslTimeout = -1;

Future<_Received> _inletMain(_InletArgs args) async {
  final inlet = LSLInlet<double>(
    LSLStreamInfo.fromStreamInfoAddr(args.infoAddress),
    chunkSize: 1,
    useIsolates: false,
  );
  await inlet.create();

  final seqs = _Ints(args.expectedSamples);
  final sourceClocks = _Doubles(args.expectedSamples);
  final receivedClocks = _Doubles(args.expectedSamples);
  final offsets = _Doubles(args.expectedSamples);
  final uncertainties = _Doubles(args.expectedSamples);
  final syncClocks = <double>[];
  final syncOffsets = <double>[];
  final syncRemoteTimes = <double>[];
  final syncUncertainties = <double>[];
  final syncResets = <bool>[];

  var offset = double.nan;
  var uncertainty = double.nan;
  var remoteTime = double.nan;
  var nextSync = 0.0;

  // liblsl keeps estimating in the background; this only reads its latest,
  // waiting for one only when there is none yet. It is called after a
  // sample's receive time has been taken, never before.
  void sync(double now, double timeout) {
    nextSync = now + 0.5;
    try {
      final estimate = inlet.getTimeCorrectionExSync(timeout: timeout);
      if (estimate.remoteTime == remoteTime && estimate.offset == offset) {
        return;
      }
      offset = estimate.offset;
      uncertainty = estimate.uncertainty;
      remoteTime = estimate.remoteTime;
      syncClocks.add(now);
      syncOffsets.add(offset);
      syncRemoteTimes.add(remoteTime);
      syncUncertainties.add(uncertainty);
      syncResets.add(inlet.wasClockResetSync());
    } on LSLException {
      // No estimate yet; samples stay without an offset until there is one.
    }
  }

  sync(LSL.localClock(), 2);

  final blocking = args.receiveMode == ReceiveMode.event;
  final pause = args.receiveMode == ReceiveMode.polled
      ? Duration(microseconds: args.pollIntervalMicros)
      : null;
  int? errorCode;
  var errorClock = 0.0;
  while (true) {
    // Event mode waits inside liblsl, which wakes the call the moment a
    // sample is queued; the timeout is only so the end of the run is seen.
    final sample = inlet.pullSampleSync(timeout: blocking ? 0.1 : 0);
    final now = LSL.localClock();
    if (sample.isNotEmpty) {
      seqs.add(sample[0].toInt());
      sourceClocks.add(sample.timestamp);
      receivedClocks.add(now);
      offsets.add(offset);
      uncertainties.add(uncertainty);
      // Polled: keep draining, so the pause comes once per poll and not
      // once per sample.
      if (pause != null && now < args.endClock) continue;
    } else if (sample.errorCode != 0 && sample.errorCode != _lslTimeout) {
      // Not "nothing yet": the inlet will give no more. Going on would spin
      // through failing pulls until the end and log nothing but a gap.
      errorCode = sample.errorCode;
      errorClock = now;
      break;
    }
    if (now >= args.endClock) break;
    if (now >= nextSync) sync(now, 0);
    if (pause != null) sleep(pause);
  }

  await inlet.destroy();
  return _Received(
    seq: seqs.take(),
    sourceClock: sourceClocks.take(),
    receivedClock: receivedClocks.take(),
    clockOffset: offsets.take(),
    uncertainty: uncertainties.take(),
    syncClock: Float64List.fromList(syncClocks),
    syncOffset: Float64List.fromList(syncOffsets),
    syncRemoteTime: Float64List.fromList(syncRemoteTimes),
    syncUncertainty: Float64List.fromList(syncUncertainties),
    syncReset: syncResets,
    errorCode: errorCode,
    errorClock: errorClock,
  );
}
