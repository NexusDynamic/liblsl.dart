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
  final SendPort port;

  const _ListenerArgs({
    required this.inletAddress,
    required this.streamInfoAddress,
    required this.stopFlagAddress,
    required this.wakeInterval,
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
Stream<LSLTimedSample<T>> listenToInlet<T>({
  required int inletAddress,
  required int streamInfoAddress,
  required double wakeInterval,
}) {
  late final StreamController<LSLTimedSample<T>> controller;
  Pointer<Uint8>? stopFlag;
  ReceivePort? port;
  final stopped = Completer<void>();

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
            controller.add(
              LSLTimedSample<T>(IList<T>(data.cast<T>()), timestamp, clock),
            );
          case final String error:
            controller.addError(LSLException(error));
          case null:
            // The isolate has left its loop (asked to, or after an error).
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
          port: receive.sendPort,
        ),
        debugName: 'lsl-sample-listener',
        // An isolate that dies without reaching its last line still ends
        // the stream.
        onExit: receive.sendPort,
      ).then<void>(
        (_) {},
        onError: (Object e) {
          controller.addError(e);
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
  final inlet = lsl_inlet.fromAddress(args.inletAddress);
  final streamInfo = LSLStreamInfo.fromStreamInfoAddr(args.streamInfoAddress);
  final stop = Pointer<Uint8>.fromAddress(args.stopFlagAddress);
  final pull = LSLMapper().streamPull(streamInfo);
  final channels = streamInfo.channelCount;

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
    } else if (sample.errorCode != 0 &&
        sample.errorCode != lsl_error_code_t.lsl_timeout_error.value) {
      args.port.send('Error pulling sample (code ${sample.errorCode})');
      break;
    }
  }
  // `onExit` sends null too; the first one ends the stream.
  Isolate.exit(args.port, null);
}
