import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
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
  /// back: when the chunk began to be available to this process. The later
  /// samples were already queued then, or arrived within the `coalesce`
  /// time after it.
  final double receivedClock;

  const LSLTimedChunk(
    this.timestamps,
    this.channelCount,
    this.receivedClock, {
    this.data,
    this.strings,
  });

  int get sampleCount => timestamps.length;

  @override
  String toString() =>
      'LSLTimedChunk{samples: $sampleCount, channels: $channelCount, '
      'receivedClock: $receivedClock}';
}

/// What the listening isolate needs; addresses, because pointers do not
/// cross isolates.
final class _ListenerArgs {
  final int inletAddress;
  final int streamInfoAddress;
  final int stopFlagAddress;
  final double wakeInterval;
  final int maxSamples;
  final double coalesce;
  final int? debugFailAfter;
  final SendPort port;

  const _ListenerArgs({
    required this.inletAddress,
    required this.streamInfoAddress,
    required this.stopFlagAddress,
    required this.wakeInterval,
    required this.maxSamples,
    required this.coalesce,
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
  int? debugFailAfter,
}) => _listenTo<LSLTimedSample<T>>(
  _listenForSamples,
  inletAddress: inletAddress,
  streamInfoAddress: streamInfoAddress,
  wakeInterval: wakeInterval,
  debugFailAfter: debugFailAfter,
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
    debugFailAfter: debugFailAfter,
    decode: (message) => switch (message) {
      [
        final Float64List timestamps,
        final double clock,
        final int channels,
        final TypedData data,
      ] =>
        LSLTimedChunk(timestamps, channels, clock, data: data),
      [
        final Float64List timestamps,
        final double clock,
        final int channels,
        final List<Object?> strings,
      ] =>
        LSLTimedChunk(timestamps, channels, clock, strings: strings.cast()),
      _ => null,
    },
  );
}

/// The stream both listeners share: the isolate, its stop flag, and the rule
/// that it never ends quietly unless it was cancelled.
///
/// [decode] turns a message from the isolate into an event, or returns null
/// for one that is not data.
Stream<R> _listenTo<R>(
  void Function(_ListenerArgs) entry, {
  required int inletAddress,
  required int streamInfoAddress,
  required double wakeInterval,
  required R? Function(Object? message) decode,
  int maxSamples = 1,
  double coalesce = 0,
  int? debugFailAfter,
}) {
  late final StreamController<R> controller;
  Pointer<Uint8>? stopFlag;
  ReceivePort? port;
  final stopped = Completer<void>();
  var failed = false;

  void fail(String message, {int? code, String? stack}) {
    failed = true;
    if (controller.isClosed) return;
    controller.addError(
      LSLSampleListenerException(message, errorCode: code, stackTrace: stack),
      stack == null ? null : StackTrace.fromString(stack),
    );
  }

  void finish() {
    port?.close();
    stopFlag?.free();
    stopFlag = null;
    if (!stopped.isCompleted) stopped.complete();
  }

  controller = StreamController<R>(
    onListen: () {
      final flag = stopFlag = allocate<Uint8>()..value = 0;
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
            if (flag.value == 0 && !failed) {
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
              flag.value = 1;
              return;
            }
            if (event != null) controller.add(event);
        }
      });
      Isolate.spawn(
        entry,
        _ListenerArgs(
          inletAddress: inletAddress,
          streamInfoAddress: streamInfoAddress,
          stopFlagAddress: flag.address,
          wakeInterval: wakeInterval,
          maxSamples: maxSamples,
          coalesce: coalesce,
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
    onCancel: () {
      final flag = stopFlag;
      if (flag == null) return null;
      flag.value = 1;
      return stopped.future;
    },
  );
  return controller.stream;
}

/// Whether [code] ends a listener: anything liblsl reports but a timeout.
bool _fatal(int code) =>
    code != 0 && code != lsl_error_code_t.lsl_timeout_error.value;

void _listenForSamples(_ListenerArgs args) {
  try {
    final inlet = lsl_inlet.fromAddress(args.inletAddress);
    final streamInfo = LSLStreamInfo.fromStreamInfoAddr(args.streamInfoAddress);
    final stop = Pointer<Uint8>.fromAddress(args.stopFlagAddress);
    final pull = LSLMapper().streamPull(streamInfo);
    final channels = streamInfo.channelCount;
    var delivered = 0;

    while (stop.value == 0) {
      final sample = pull(inlet, channels, args.wakeInterval);
      if (sample.isNotEmpty) {
        // Read before anything else: this is the receive time.
        final clock = lsl_local_clock();
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
    final stop = Pointer<Uint8>.fromAddress(args.stopFlagAddress);
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
    // Where the samples after the first go.
    final restData = Pointer<NativeType>.fromAddress(
      data.address + channels * elementSize,
    );
    final restTimes = Pointer<Double>.fromAddress(
      times.address + sizeOf<Double>(),
    );
    var delivered = 0;

    try {
      while (stop.value == 0) {
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
        if (max > 1) {
          ec.value = 0;
          elements += pull.pullInto(
            inlet,
            restData,
            restTimes,
            max - 1,
            channels,
            args.coalesce,
            ec,
          );
          if (_fatal(ec.value)) failure = ec.value;
        }
        final samples = elements ~/ channels;
        args.port.send([
          Float64List.fromList(times.asTypedList(samples)),
          clock,
          channels,
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
