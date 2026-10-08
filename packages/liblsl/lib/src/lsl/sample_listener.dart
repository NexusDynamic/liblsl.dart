import 'dart:async';
import 'dart:ffi';
import 'dart:io' show sleep;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:logging/logging.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/structs.dart';

/// A sample and the local clock at the moment it was pulled.
final class LSLTimedSample<T> {
  final IList<T> data;

  /// The sample's time stamp, as [LSLSample.timestamp].
  final double timestamp;

  /// `lsl_local_clock()` as the pull that returned this sample came back:
  /// when the sample became available to this process, not when a listener
  /// got round to it.
  ///
  /// That is its arrival only for a sample the isolate was waiting for. One
  /// that was already in the inlet's buffer has the time it was taken out
  /// instead, which is later: whatever arrived before the stream was
  /// listened to, and with `maxBacklog` whatever arrived while the isolate
  /// was held back (a queue at its limit, a paused subscription).
  final double receivedClock;

  const LSLTimedSample(this.data, this.timestamp, this.receivedClock);

  @override
  String toString() =>
      'LSLTimedSample{data: $data, timestamp: $timestamp, '
      'receivedClock: $receivedClock}';
}

/// Samples that were waiting together, and the local clock at the moment
/// the first of them was pulled.
final class LSLTimedChunk {
  /// One time stamp per sample, as [LSLSample.timestamp].
  final Float64List timestamps;

  /// `sampleCount * channelCount` values, sample after sample, in a typed
  /// list matching the stream's channel format. Null for a string stream.
  final TypedData? data;

  /// `sampleCount * channelCount` strings, for a string stream.
  final List<String>? strings;

  final int channelCount;

  /// `lsl_local_clock()` as the pull that returned the first sample came
  /// back: when the chunk began to be available to this process. The first
  /// [readyCount] samples were in the inlet by then; the rest arrived within
  /// the `coalesce` time after it. As [LSLTimedSample.receivedClock], it is
  /// an arrival only if the isolate was waiting for the first sample.
  final double receivedClock;

  /// How many samples, from the first, were already in the inlet when
  /// [receivedClock] was read. All of them unless `coalesce` was given.
  ///
  /// A sender that pushes chunks delivers their samples together, with time
  /// stamps spread over the chunk, so the first sample's is older than its
  /// arrival by the time the sender took to fill the chunk. The sample that
  /// waited least is the last one that was ready:
  /// `receivedClock - timestamps[readyCount - 1]` is the transit time with
  /// no chunking in it, where `receivedClock - timestamps.first` has the
  /// sender's.
  final int readyCount;

  const LSLTimedChunk(
    this.timestamps,
    this.channelCount,
    this.receivedClock, {
    this.data,
    this.strings,
    int? readyCount,
  }) : readyCount = readyCount ?? timestamps.length;

  int get sampleCount => timestamps.length;

  @override
  String toString() =>
      'LSLTimedChunk{samples: $sampleCount, channels: $channelCount, '
      'receivedClock: $receivedClock}';
}

/// How far the listener of a sample or chunk stream is behind the isolate
/// that pulls for it. See `onBacklog` of [LSLInlet.sampleStream].
final class LSLBacklog {
  /// Samples that have been pulled from the inlet and not yet reached the
  /// stream: what is queued between the two isolates.
  final int queued;

  /// The most [queued] has been since it went over the threshold.
  final int peak;

  /// Whether this is the report that the queue is back under half the
  /// threshold. Nothing more is reported until it goes over again.
  final bool cleared;

  const LSLBacklog({
    required this.queued,
    required this.peak,
    this.cleared = false,
  });

  @override
  String toString() =>
      'LSLBacklog{queued: $queued, peak: $peak, cleared: $cleared}';
}

/// Stops a running listener, which then ends its stream with [reason] as an
/// [LSLSampleListenerException]. Completes once its isolate has left liblsl.
typedef LSLListenerStop = Future<void> Function(String reason);

final _log = Logger('liblsl');

void _logBacklog(LSLBacklog backlog) => backlog.cleared
    ? _log.info(
        'The listener of a sample stream has caught up '
        '(it was ${backlog.peak} samples behind)',
      )
    : _log.warning(
        'The listener of a sample stream is ${backlog.queued} samples '
        'behind and is not keeping up: they are queued in memory without '
        'limit. Do less per sample, use chunkStream, or set maxBacklog',
      );

// The words of the block of memory the two isolates share. Each has one
// writer, so they are read and written as they are, without a lock.
/// Nonzero: the isolate is to leave. Written by the listening side.
const _stop = 0;

/// Nonzero: the isolate is not to pull. Written by the listening side.
const _paused = 1;

/// Samples sent by the isolate, modulo 2^32.
const _sent = 2;

/// Samples that have reached the stream, modulo 2^32. Written by the
/// listening side.
const _received = 3;
const _controlWords = 4;
const _mask = 0xFFFFFFFF;

/// What the listening isolate needs; addresses, because pointers do not
/// cross isolates.
final class _ListenerArgs {
  final int inletAddress;
  final int streamInfoAddress;
  final int controlAddress;
  final double wakeInterval;
  final int maxSamples;
  final double coalesce;

  /// Samples the listening side may be behind before the isolate stops
  /// pulling; zero for no limit.
  final int maxBacklog;
  final int? debugFailAfter;
  final SendPort port;

  const _ListenerArgs({
    required this.inletAddress,
    required this.streamInfoAddress,
    required this.controlAddress,
    required this.wakeInterval,
    required this.maxSamples,
    required this.coalesce,
    required this.maxBacklog,
    required this.debugFailAfter,
    required this.port,
  });
}

/// Samples of the inlet at [inletAddress] as they arrive, pulled on an
/// isolate of their own.
///
/// The isolate sits inside `lsl_pull_sample` with a timeout. liblsl wakes
/// that call when a sample is queued, so there is no polling interval
/// between a sample arriving and its receive clock being read; the timeout
/// ([wakeInterval], in seconds) only bounds how long cancelling takes.
///
/// Listening starts the isolate and cancelling stops it; the cancel future
/// completes once the isolate has left liblsl, after which the inlet can be
/// pulled from elsewhere or destroyed.
///
/// The stream closes without an error only when it was cancelled. If the
/// isolate ends for any other reason (a pull error other than a timeout, an
/// exception, or an exit nobody asked for) the stream delivers an
/// [LSLSampleListenerException] and then closes.
///
/// [debugFailAfter] is for tests: the isolate throws after that many
/// samples.
Stream<LSLTimedSample<T>> listenToInlet<T>({
  required int inletAddress,
  required int streamInfoAddress,
  required double wakeInterval,
  required int backlogWarnAt,
  int? maxBacklog,
  void Function(LSLBacklog backlog)? onBacklog,
  void Function(LSLListenerStop stop)? onStarted,
  void Function(LSLListenerStop stop)? onEnded,
  int? debugFailAfter,
}) => _listenTo<LSLTimedSample<T>>(
  _listenForSamples,
  inletAddress: inletAddress,
  streamInfoAddress: streamInfoAddress,
  wakeInterval: wakeInterval,
  backlogWarnAt: backlogWarnAt,
  maxBacklog: maxBacklog,
  onBacklog: onBacklog,
  onStarted: onStarted,
  onEnded: onEnded,
  debugFailAfter: debugFailAfter,
  samplesIn: (_) => 1,
  decode: (message) => switch (message) {
    [final double timestamp, final double clock, final List<Object?> data] =>
      LSLTimedSample<T>(IList<T>(data.cast<T>()), timestamp, clock),
    _ => null,
  },
);

/// As [listenToInlet], but everything that is waiting when the isolate
/// wakes comes as one [LSLTimedChunk], of at most [maxSamples] samples.
///
/// With [coalesce] (seconds) above zero the isolate goes on collecting for
/// that long after the first sample before it hands the chunk over. A fast
/// stream whose sender does not chunk otherwise wakes it once per sample;
/// this bounds how often it delivers, at the cost of that much latency.
///
/// [debugFailAfter] is for tests: the isolate throws after that many
/// chunks.
Stream<LSLTimedChunk> listenToInletChunks({
  required int inletAddress,
  required int streamInfoAddress,
  required double wakeInterval,
  required int maxSamples,
  required double coalesce,
  required int backlogWarnAt,
  int? maxBacklog,
  void Function(LSLBacklog backlog)? onBacklog,
  void Function(LSLListenerStop stop)? onStarted,
  void Function(LSLListenerStop stop)? onEnded,
  int? debugFailAfter,
}) {
  if (maxSamples < 1) throw ArgumentError.value(maxSamples, 'maxSamples');
  return _listenTo<LSLTimedChunk>(
    _listenForChunks,
    inletAddress: inletAddress,
    streamInfoAddress: streamInfoAddress,
    wakeInterval: wakeInterval,
    maxSamples: maxSamples,
    coalesce: coalesce,
    backlogWarnAt: backlogWarnAt,
    maxBacklog: maxBacklog,
    onBacklog: onBacklog,
    onStarted: onStarted,
    onEnded: onEnded,
    debugFailAfter: debugFailAfter,
    samplesIn: (chunk) => chunk.sampleCount,
    decode: (message) => switch (message) {
      [
        final Float64List timestamps,
        final double clock,
        final int channels,
        final int ready,
        final TypedData data,
      ] =>
        LSLTimedChunk(
          timestamps,
          channels,
          clock,
          data: data,
          readyCount: ready,
        ),
      [
        final Float64List timestamps,
        final double clock,
        final int channels,
        final int ready,
        final List<Object?> strings,
      ] =>
        LSLTimedChunk(
          timestamps,
          channels,
          clock,
          strings: strings.cast(),
          readyCount: ready,
        ),
      _ => null,
    },
  );
}

/// The stream both listeners share: the isolate, its stop flag, and the rule
/// that it never ends quietly unless it was cancelled.
///
/// [decode] turns a message from the isolate into an event, or returns null
/// for one that is not data; [samplesIn] says how many samples an event is.
///
/// The two isolates count those samples into shared memory, one as it sends
/// and the other as the event reaches the stream. The difference is what is
/// queued in between, which is reported past [backlogWarnAt] ([onBacklog],
/// or the log) and, with [maxBacklog], holds the isolate back.
Stream<R> _listenTo<R>(
  void Function(_ListenerArgs) entry, {
  required int inletAddress,
  required int streamInfoAddress,
  required double wakeInterval,
  required R? Function(Object? message) decode,
  required int Function(R event) samplesIn,
  required int backlogWarnAt,
  int? maxBacklog,
  void Function(LSLBacklog backlog)? onBacklog,
  void Function(LSLListenerStop stop)? onStarted,
  void Function(LSLListenerStop stop)? onEnded,
  int maxSamples = 1,
  double coalesce = 0,
  int? debugFailAfter,
}) {
  if (maxBacklog != null && maxBacklog < 1) {
    throw ArgumentError.value(maxBacklog, 'maxBacklog');
  }
  if (backlogWarnAt < 1) {
    throw ArgumentError.value(backlogWarnAt, 'backlogWarnAt');
  }
  late final StreamController<R> controller;
  Pointer<Uint32>? control;
  ReceivePort? port;
  final stopped = Completer<void>();
  var failed = false;

  final report = onBacklog ?? _logBacklog;
  final sinceReport = Stopwatch();
  var behind = false;
  var peak = 0;

  // Only reached while [queued] is over the threshold or has been.
  void noteBacklog(int queued) {
    if (queued >= backlogWarnAt) {
      if (queued > peak) peak = queued;
      if (behind && sinceReport.elapsedMilliseconds < 1000) return;
      behind = true;
      sinceReport
        ..reset()
        ..start();
      report(LSLBacklog(queued: queued, peak: peak));
    } else if (queued <= backlogWarnAt ~/ 2) {
      behind = false;
      report(LSLBacklog(queued: queued, peak: peak, cleared: true));
      peak = 0;
    }
  }

  void fail(String message, {int? code, String? stack}) {
    failed = true;
    if (controller.isClosed) return;
    controller.addError(
      LSLSampleListenerException(message, errorCode: code, stackTrace: stack),
      stack == null ? null : StackTrace.fromString(stack),
    );
  }

  // The inlet's way of stopping this listener when it is itself going.
  Future<void> stop(String reason) {
    fail(reason);
    control?[_stop] = 1;
    return stopped.future;
  }

  void finish() {
    port?.close();
    control?.free();
    control = null;
    if (!stopped.isCompleted) {
      stopped.complete();
      onEnded?.call(stop);
    }
  }

  controller = StreamController<R>(
    onListen: () {
      final flag = control = allocate<Uint32>(_controlWords);
      for (var i = 0; i < _controlWords; i++) {
        flag[i] = 0;
      }
      onStarted?.call(stop);
      final receive = port = ReceivePort();
      receive.listen((message) {
        switch (message) {
          // From the isolate: a failed pull, or something it caught.
          case [final int? code, final String error, final String? stack]:
            fail(error, code: code, stack: stack);
          // From `onError`: something it did not catch.
          case [final String error, final String? stack]:
            fail('Sample listener isolate failed: $error', stack: stack);
          case null:
            // The isolate is gone. If nobody asked it to stop and it gave no
            // reason, that is still a failure, not an end of stream.
            if (flag[_stop] == 0 && !failed) {
              fail('Sample listener isolate exited unexpectedly');
            }
            finish();
            if (!controller.isClosed) controller.close();
          default:
            final R? event;
            try {
              event = decode(message);
            } catch (e, st) {
              // The isolate is still pulling; say so rather than throw into
              // the listener's zone, where nobody is looking.
              fail('Sample could not be delivered: $e', stack: '$st');
              flag[_stop] = 1;
              return;
            }
            if (event == null) return;
            // The isolate counts a sample before it sends it, so this is
            // never ahead of it.
            final received = (flag[_received] + samplesIn(event)) & _mask;
            flag[_received] = received;
            final queued = (flag[_sent] - received) & _mask;
            if (behind || queued >= backlogWarnAt) noteBacklog(queued);
            controller.add(event);
        }
      });
      Isolate.spawn(
        entry,
        _ListenerArgs(
          inletAddress: inletAddress,
          streamInfoAddress: streamInfoAddress,
          controlAddress: flag.address,
          wakeInterval: wakeInterval,
          maxSamples: maxSamples,
          coalesce: coalesce,
          maxBacklog: maxBacklog ?? 0,
          debugFailAfter: debugFailAfter,
          port: receive.sendPort,
        ),
        debugName: 'lsl-sample-listener',
        // An isolate that dies without reaching its last line still ends
        // the stream, and says why if it can.
        onError: receive.sendPort,
        onExit: receive.sendPort,
      ).then<void>(
        (_) {},
        onError: (Object e, StackTrace st) {
          fail(
            'Sample listener isolate could not be started: $e',
            stack: '$st',
          );
          finish();
          controller.close();
        },
      );
    },
    // Only with a limit: without one a paused subscription buffers, as any
    // stream's does, and the isolate goes on reading the receive clock as
    // samples arrive. (`await for` pauses around every event.)
    onPause: maxBacklog == null ? null : () => control?[_paused] = 1,
    onResume: maxBacklog == null ? null : () => control?[_paused] = 0,
    onCancel: () {
      final flag = control;
      if (flag == null) return null;
      flag[_stop] = 1;
      return stopped.future;
    },
  );
  return controller.stream;
}

/// Whether the isolate is to pull again; false when it is to leave.
///
/// With a limit ([max] above zero) it first waits here while the listening
/// side is that many samples behind or has paused, so what arrives meanwhile
/// stays in the inlet's buffer, which liblsl bounds. It spins for a moment,
/// since most such waits are over in microseconds, and then sleeps a
/// millisecond at a time.
@pragma('vm:prefer-inline')
bool _mayPull(Pointer<Uint32> control, int max) {
  if (control[_stop] != 0) return false;
  if (max == 0) return true;
  var spins = 0;
  while (control[_paused] != 0 ||
      ((control[_sent] - control[_received]) & _mask) >= max) {
    if (control[_stop] != 0) return false;
    if (++spins > 20000) sleep(const Duration(milliseconds: 1));
  }
  return true;
}

/// Whether [code] ends a listener: anything liblsl reports but a timeout.
bool _fatal(int code) =>
    code != 0 && code != lsl_error_code_t.lsl_timeout_error.value;

void _listenForSamples(_ListenerArgs args) {
  try {
    final inlet = lsl_inlet.fromAddress(args.inletAddress);
    final streamInfo = LSLStreamInfo.fromStreamInfoAddr(args.streamInfoAddress);
    final control = Pointer<Uint32>.fromAddress(args.controlAddress);
    final pull = LSLMapper().streamPull(streamInfo);
    final channels = streamInfo.channelCount;
    final maxBacklog = args.maxBacklog;
    var delivered = 0;

    while (_mayPull(control, maxBacklog)) {
      final sample = pull(inlet, channels, args.wakeInterval);
      if (sample.isNotEmpty) {
        // Read before anything else: this is the receive time.
        final clock = lsl_local_clock();
        // Counted before it is sent, so the other side never counts ahead.
        control[_sent] = control[_sent] + 1;
        args.port.send([
          sample.timestamp,
          clock,
          sample.data.toList(growable: false),
        ]);
        if (++delivered == args.debugFailAfter) {
          throw StateError('debugFailAfter: failing after $delivered samples');
        }
      } else if (_fatal(sample.errorCode)) {
        // Built here: liblsl's message for the error is thread-local.
        args.port.send([
          sample.errorCode,
          lslError('lsl_pull_sample', sample.errorCode).message,
          null,
        ]);
        break;
      }
    }
  } catch (e, st) {
    args.port.send([null, 'Sample listener failed: $e', '$st']);
  }
  // `onExit` sends null too; the first one ends the stream.
  Isolate.exit(args.port, null);
}

void _listenForChunks(_ListenerArgs args) {
  try {
    final inlet = lsl_inlet.fromAddress(args.inletAddress);
    final streamInfo = LSLStreamInfo.fromStreamInfoAddr(args.streamInfoAddress);
    final control = Pointer<Uint32>.fromAddress(args.controlAddress);
    final maxBacklog = args.maxBacklog;
    final pull = LSLMapper().streamPullChunk(streamInfo);
    final channels = streamInfo.channelCount;
    final strings = streamInfo.channelFormat == LSLChannelFormat.string;
    final max = args.maxSamples;
    // Freed with the isolate's process only if it is killed; otherwise below.
    final data = pull.allocBuffer(max * channels);
    final times = allocate<Double>(max);
    final ec = allocate<Int32>();
    final elementSize = switch (streamInfo.channelFormat) {
      LSLChannelFormat.int8 => 1,
      LSLChannelFormat.int16 => 2,
      LSLChannelFormat.float32 || LSLChannelFormat.int32 => 4,
      LSLChannelFormat.double64 || LSLChannelFormat.int64 => 8,
      _ => sizeOf<Pointer<Char>>(),
    };
    // Where the samples after the first [count] go.
    Pointer<NativeType> dataAfter(int count) => Pointer<NativeType>.fromAddress(
      data.address + count * channels * elementSize,
    );
    Pointer<Double> timesAfter(int count) =>
        Pointer<Double>.fromAddress(times.address + count * sizeOf<Double>());
    var delivered = 0;

    try {
      while (_mayPull(control, maxBacklog)) {
        // One sample, so the call returns the moment there is one rather
        // than waiting to fill a chunk.
        ec.value = 0;
        var elements = pull.pullInto(
          inlet,
          data,
          times,
          1,
          channels,
          args.wakeInterval,
          ec,
        );
        if (elements == 0) {
          if (!_fatal(ec.value)) continue;
          args.port.send([
            ec.value,
            lslError('lsl_pull_chunk', ec.value).message,
            null,
          ]);
          break;
        }
        // Read before anything else: this is the receive time.
        final clock = lsl_local_clock();
        var failure = 0;
        var samples = elements ~/ channels;
        if (samples < max) {
          // What came with it: these were in the inlet as the clock was
          // read.
          ec.value = 0;
          samples +=
              pull.pullInto(
                inlet,
                dataAfter(samples),
                timesAfter(samples),
                max - samples,
                channels,
                0,
                ec,
              ) ~/
              channels;
          if (_fatal(ec.value)) failure = ec.value;
        }
        final ready = samples;
        if (failure == 0 && args.coalesce > 0 && samples < max) {
          // And what arrives in the time allowed for more.
          ec.value = 0;
          samples +=
              pull.pullInto(
                inlet,
                dataAfter(samples),
                timesAfter(samples),
                max - samples,
                channels,
                args.coalesce,
                ec,
              ) ~/
              channels;
          if (_fatal(ec.value)) failure = ec.value;
        }
        elements = samples * channels;
        // Counted before it is sent, so the other side never counts ahead.
        control[_sent] = control[_sent] + samples;
        args.port.send([
          Float64List.fromList(times.asTypedList(samples)),
          clock,
          channels,
          ready,
          if (strings)
            pull
                .bufferToLists(data, samples, channels)
                .expand((sample) => sample)
                .toList(growable: false)
          else
            pull.bufferToTypedData(data, elements),
        ]);
        if (failure != 0) {
          args.port.send([
            failure,
            lslError('lsl_pull_chunk', failure).message,
            null,
          ]);
          break;
        }
        if (++delivered == args.debugFailAfter) {
          throw StateError('debugFailAfter: failing after $delivered chunks');
        }
      }
    } finally {
      data.free();
      times.free();
      ec.free();
    }
  } catch (e, st) {
    args.port.send([null, 'Sample listener failed: $e', '$st']);
  }
  // `onExit` sends null too; the first one ends the stream.
  Isolate.exit(args.port, null);
}
