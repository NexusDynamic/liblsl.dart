import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/stream_info.dart';

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

/// What the listening isolate needs; addresses, because pointers do not
/// cross isolates.
final class _ListenerArgs {
  final int inletAddress;
  final int streamInfoAddress;
  final int stopFlagAddress;
  final double wakeInterval;
  final int? debugFailAfter;
  final SendPort port;

  const _ListenerArgs({
    required this.inletAddress,
    required this.streamInfoAddress,
    required this.stopFlagAddress,
    required this.wakeInterval,
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
}) {
  late final StreamController<LSLTimedSample<T>> controller;
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

  controller = StreamController<LSLTimedSample<T>>(
    onListen: () {
      final flag = stopFlag = allocate<Uint8>()..value = 0;
      final receive = port = ReceivePort();
      receive.listen((message) {
        switch (message) {
          case [
            final double timestamp,
            final double clock,
            final List<Object?> data,
          ]:
            final LSLTimedSample<T> sample;
            try {
              sample = LSLTimedSample<T>(
                IList<T>(data.cast<T>()),
                timestamp,
                clock,
              );
            } catch (e, st) {
              // The isolate is still pulling; say so rather than throw into
              // the listener's zone, where nobody is looking.
              fail('Sample could not be delivered: $e', stack: '$st');
              flag.value = 1;
              return;
            }
            controller.add(sample);
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
        }
      });
      Isolate.spawn(
        _listen,
        _ListenerArgs(
          inletAddress: inletAddress,
          streamInfoAddress: streamInfoAddress,
          stopFlagAddress: flag.address,
          wakeInterval: wakeInterval,
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

void _listen(_ListenerArgs args) {
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
      } else if (sample.errorCode != 0 &&
          sample.errorCode != lsl_error_code_t.lsl_timeout_error.value) {
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
