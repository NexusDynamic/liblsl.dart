import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:logging/logging.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;
import 'package:liblsl/src/ffi/bindings_ex.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:lsl_core/lsl_core.dart'
    show LSLTimedSample, LSLTimedChunk, LSLBacklog;

export 'package:lsl_core/lsl_core.dart'
    show LSLTimedSample, LSLTimedChunk, LSLBacklog;

/// Stops a running listener, which then ends its stream with [reason] as an
/// [LSLSampleListenerException]. Completes once its thread has left liblsl.
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

// The control words the listener thread shares with this side
// (`src/dart/sample_listener.cpp`). Each has one writer, so they are read and
// written as they are, without a lock.
/// Nonzero: the thread is to leave. Written here.
const _stop = 0;

/// Nonzero: the thread is not to pull. Written here.
const _paused = 1;

/// Samples handed over by the thread, modulo 2^32.
const _sent = 2;

/// Samples that have reached the stream, modulo 2^32. Written here.
const _received = 3;
const _mask = 0xFFFFFFFF;

/// Samples of an inlet as they arrive, pulled on a native thread of their
/// own. [inletAddress] is asked for the inlet (the address of its
/// `LslDartInlet`, which the listener holds while it runs) when the stream is
/// listened to,
/// and throws if there is no longer one to listen to; [format] and
/// [channels] are the stream's.
///
/// The thread sits inside `lsl_pull_chunk` with a timeout. liblsl wakes that
/// call when a sample is queued, so there is no polling interval between a
/// sample arriving and its receive clock being read; the timeout
/// ([wakeInterval], in seconds) only bounds how long cancelling takes.
///
/// It is a thread and not an isolate because the Dart VM bounds how many
/// isolates of a group are entered at once, and one that is blocked in a
/// native call still counts: sixteen listening isolates were enough to leave
/// every other isolate of the process waiting for one of them to time out.
/// The thread hands each sample to a `NativeCallable.listener`, so it reaches
/// the isolate that listened on that isolate's event loop.
///
/// Listening starts the thread and cancelling stops it; the cancel future
/// completes once the thread has left liblsl, after which the inlet can be
/// pulled from elsewhere or destroyed.
///
/// The stream closes without an error only when it was cancelled. If the
/// thread ends for any other reason (a pull error other than a timeout, or a
/// sample that could not be delivered) the stream delivers an
/// [LSLSampleListenerException] and then closes.
///
/// [debugFailAfter] is for tests: the listener fails after that many
/// samples.
Stream<LSLTimedSample<T>> listenToInlet<T>({
  required int Function() inletAddress,
  required LSLChannelFormat format,
  required int channels,
  required double wakeInterval,
  required int backlogWarnAt,
  int? maxBacklog,
  void Function(LSLBacklog backlog)? onBacklog,
  void Function(LSLListenerStop stop)? onStarted,
  void Function(LSLListenerStop stop)? onEnded,
  int? debugFailAfter,
}) => _listenTo<LSLTimedSample<T>>(
  inletAddress: inletAddress,
  format: format,
  channels: channels,
  wakeInterval: wakeInterval,
  backlogWarnAt: backlogWarnAt,
  maxBacklog: maxBacklog,
  onBacklog: onBacklog,
  onStarted: onStarted,
  onEnded: onEnded,
  debugFailAfter: debugFailAfter,
  samplesIn: (_) => 1,
  // One sample to a block: the thread was started with a limit of one.
  decode: (block, format, channels) => LSLTimedSample<T>(
    IList<T>(_values(block, format, channels).cast<T>()),
    block.timestamps[0],
    block.clock,
  ),
);

/// As [listenToInlet], but everything that is waiting when the thread wakes
/// comes as one [LSLTimedChunk], of at most [maxSamples] samples.
///
/// With [coalesce] (seconds) above zero the thread goes on collecting for
/// that long after the first sample before it hands the chunk over. A fast
/// stream whose sender does not chunk otherwise wakes it once per sample;
/// this bounds how often it delivers, at the cost of that much latency.
///
/// [debugFailAfter] is for tests: the listener fails after that many
/// chunks.
Stream<LSLTimedChunk> listenToInletChunks({
  required int Function() inletAddress,
  required LSLChannelFormat format,
  required int channels,
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
  if (!(coalesce >= 0)) throw ArgumentError.value(coalesce, 'coalesce');
  return _listenTo<LSLTimedChunk>(
    inletAddress: inletAddress,
    format: format,
    channels: channels,
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
    decode: (block, format, channels) {
      final timestamps = Float64List.fromList(
        block.timestamps.asTypedList(block.samples),
      );
      return format == LSLChannelFormat.string
          ? LSLTimedChunk(
              timestamps,
              channels,
              block.clock,
              strings: _strings(block, channels),
              readyCount: block.ready,
            )
          : LSLTimedChunk(
              timestamps,
              channels,
              block.clock,
              data: _typedData(block, format, channels),
              readyCount: block.ready,
            );
    },
  );
}

/// A copy of a block's values, in a typed list matching [format].
TypedData _typedData(
  LslDartBlock block,
  LSLChannelFormat format,
  int channels,
) {
  final elements = block.samples * channels;
  final data = block.data;
  return switch (format) {
    LSLChannelFormat.float32 => Float32List.fromList(
      data.cast<Float>().asTypedList(elements),
    ),
    LSLChannelFormat.double64 => Float64List.fromList(
      data.cast<Double>().asTypedList(elements),
    ),
    LSLChannelFormat.int8 => Int8List.fromList(
      data.cast<Int8>().asTypedList(elements),
    ),
    LSLChannelFormat.int16 => Int16List.fromList(
      data.cast<Int16>().asTypedList(elements),
    ),
    LSLChannelFormat.int32 => Int32List.fromList(
      data.cast<Int32>().asTypedList(elements),
    ),
    LSLChannelFormat.int64 => Int64List.fromList(
      data.cast<Int64>().asTypedList(elements),
    ),
    _ => throw UnsupportedError('No typed data for a $format stream'),
  };
}

/// A string block's values: they lie one after another, each ending in a
/// zero byte.
List<String> _strings(LslDartBlock block, int channels) {
  final bytes = block.data.cast<Uint8>().asTypedList(block.dataBytes);
  final count = block.samples * channels;
  final strings = List<String>.filled(count, '', growable: false);
  var start = 0;
  for (var i = 0; i < count; i++) {
    var end = start;
    while (bytes[end] != 0) {
      end++;
    }
    if (end > start) {
      strings[i] = utf8.decode(Uint8List.sublistView(bytes, start, end));
    }
    start = end + 1;
  }
  return strings;
}

/// A block's values as a list of the stream's Dart type.
List<Object> _values(
  LslDartBlock block,
  LSLChannelFormat format,
  int channels,
) => format == LSLChannelFormat.string
    ? _strings(block, channels)
    : switch (_typedData(block, format, channels)) {
        final List<double> doubles => doubles,
        final List<int> ints => ints,
        _ => const [],
      };

/// What a running listener thread is tied to on this side, so that the
/// thread is told if the isolate goes away without stopping it.
final class _ListenerToken implements Finalizable {}

/// Runs for a listener that is still attached when its isolate exits or is
/// killed. The thread must not call into the isolate after that.
final _abandon = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
    lslDartListenerAbandon,
  ),
);

/// The stream both listeners share: the thread, its stop flag, and the rule
/// that it never ends quietly unless it was cancelled.
///
/// [decode] turns a block from the thread into an event; [samplesIn] says how
/// many samples an event is.
///
/// The thread counts those samples into shared memory as it hands them over,
/// and this side as the event reaches the stream. The difference is what is
/// queued in between, which is reported past [backlogWarnAt] ([onBacklog],
/// or the log) and, with [maxBacklog], holds the thread back.
Stream<R> _listenTo<R>({
  required int Function() inletAddress,
  required LSLChannelFormat format,
  required int channels,
  required double wakeInterval,
  required R Function(LslDartBlock block, LSLChannelFormat format, int channels)
  decode,
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
  // liblsl does not wait at all on a timeout of zero or less, so the thread
  // would spin instead of parking while the stream is quiet.
  if (!wakeInterval.isFinite || wakeInterval <= 0) {
    throw ArgumentError.value(wakeInterval, 'wakeInterval', 'must be above 0');
  }
  if (maxBacklog != null && maxBacklog < 1) {
    throw ArgumentError.value(maxBacklog, 'maxBacklog');
  }
  if (backlogWarnAt < 1) {
    throw ArgumentError.value(backlogWarnAt, 'backlogWarnAt');
  }
  late final StreamController<R> controller;
  Pointer<LslDartListener>? listener;
  Pointer<Uint32>? control;
  NativeCallable<LslDartBlockCallback>? callable;
  final token = _ListenerToken();
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

  // The thread has made its last call, or was never started.
  void finish() {
    final handle = listener;
    listener = null;
    control = null;
    if (handle != null) {
      _abandon.detach(token);
      // Returns at once: the thread is past its last call.
      lslDartListenerDestroy(handle);
    }
    callable?.close();
    callable = null;
    if (!stopped.isCompleted) {
      stopped.complete();
      onEnded?.call(stop);
    }
  }

  controller = StreamController<R>(
    onListen: () {
      // Asked now, not when the stream was made: the inlet may have been
      // destroyed in between.
      final int inlet;
      try {
        inlet = inletAddress();
      } catch (e) {
        fail('Sample listener could not start: $e');
        finish();
        controller.close();
        return;
      }
      onStarted?.call(stop);

      void onBlock(Pointer<LslDartBlock> pointer) {
        final block = pointer.ref;
        final flag = control;
        if (block.kind != lslDartBlockData) {
          final thread = block.kind == lslDartBlockFailed;
          final code = block.error;
          final detail = block.message == nullptr
              ? ''
              : block.message.cast<Utf8>().toDartString();
          lslDartBlockFree(pointer);
          if (thread) {
            fail(
              'Sample listener failed: $detail',
              stack: '${StackTrace.current}',
            );
          } else if (code != 0) {
            fail(
              lslErrorWithDetail('lsl_pull_chunk', code, detail).message,
              code: code,
            );
          } else if (flag != null && flag[_stop] == 0 && !failed) {
            // Nobody asked it to stop and it gave no reason: still a
            // failure, not an end of stream.
            fail('Sample listener ended unexpectedly');
          }
          finish();
          if (!controller.isClosed) controller.close();
          return;
        }
        // On its way out: what it still hands over is not wanted.
        if (flag == null || flag[_stop] != 0) {
          lslDartBlockFree(pointer);
          return;
        }
        final R event;
        try {
          event = decode(block, format, channels);
        } catch (e, st) {
          // The thread is still pulling; say so rather than throw into the
          // listener's zone, where nobody is looking.
          fail('Sample could not be delivered: $e', stack: '$st');
          flag[_stop] = 1;
          return;
        } finally {
          lslDartBlockFree(pointer);
        }
        // The thread counts a sample before it hands it over, so this is
        // never ahead of it.
        final received = (flag[_received] + samplesIn(event)) & _mask;
        flag[_received] = received;
        final queued = (flag[_sent] - received) & _mask;
        if (behind || queued >= backlogWarnAt) noteBacklog(queued);
        controller.add(event);
      }

      final callback = callable = NativeCallable<LslDartBlockCallback>.listener(
        onBlock,
      );
      final handle = lslDartListenerStart(
        Pointer<LslDartInlet>.fromAddress(inlet),
        format.lslFormat.value,
        channels,
        maxSamples,
        coalesce,
        wakeInterval,
        maxBacklog ?? 0,
        debugFailAfter ?? 0,
        callback.nativeFunction,
      );
      if (handle == nullptr) {
        fail('Sample listener thread could not be started');
        finish();
        controller.close();
        return;
      }
      listener = handle;
      control = lslDartListenerControl(handle);
      _abandon.attach(token, handle.cast(), detach: token);
    },
    // Only with a limit: without one a paused subscription buffers, as any
    // stream's does, and the thread goes on reading the receive clock as
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
