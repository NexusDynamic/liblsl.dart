import 'dart:async';
import 'dart:math' as math;

import 'lsl_types.dart';

/// How [receiveChunks] is getting an inlet's samples, reported when it changes.
class LslReceiveStatus {
  /// Whether samples are handed over as they arrive (false: they are
  /// collected every [LslInletOptions.pullIntervalMs]).
  final bool eventDriven;

  /// How many times in a row what listens for samples has ended by itself.
  /// Zero when it is working.
  final int failures;

  /// What ended it last, while [failures] is above zero or after
  /// [fellBack].
  final String? cause;

  /// Whether listening was given up for collecting on a timer, after it
  /// kept failing. Samples are still received.
  final bool fellBack;

  const LslReceiveStatus({
    required this.eventDriven,
    this.failures = 0,
    this.cause,
    this.fellBack = false,
  });

  /// Nothing has gone wrong, or it has been put right.
  bool get healthy => failures == 0 && !fellBack;

  /// For a status line or a tooltip; empty when [healthy].
  String get note => fellBack
      ? 'receiving on a timer after $failures failures ($cause)'
      : failures > 0
      ? 'receiving restarted $failures× ($cause)'
      : '';

  @override
  String toString() =>
      'LslReceiveStatus(eventDriven: $eventDriven, failures: $failures, '
      'fellBack: $fellBack, cause: $cause)';
}

/// Failures in a row after which [receiveChunks] stops listening and collects on a
/// timer instead.
const int receiveFallbackAfter = 3;

/// How long a restarted listener has to stay up before it counts as
/// working again.
const Duration _stableAfter = Duration(seconds: 1);

/// Everything [inlet] receives, as chunks, until the subscription is
/// cancelled. Await the cancel before closing the inlet.
///
/// With [LslInletOptions.eventDriven], on an inlet that can
/// ([LslArrivals]), chunks come as their samples arrive; otherwise
/// whatever is buffered is collected every
/// [LslInletOptions.pullIntervalMs].
///
/// What listens for arriving samples can end by itself. That is never
/// silent and never the end of receiving: [onStatus] is told, with the
/// cause, and it is started again, after 100 ms and then twice as long each
/// time. After [receiveFallbackAfter] failures in a row the inlet is
/// collected from on a timer instead, which [onStatus] is told as well. A
/// failed pull, as before, is an error on the stream, which then ends.
///
/// [debugListenerFaults] is for tests: that many listeners fail after
/// their first chunk.
Stream<LslChunk> receiveChunks(
  LslInlet inlet,
  LslInletOptions options, {
  void Function(LslReceiveStatus status)? onStatus,
  int debugListenerFaults = 0,
}) {
  final rate = inlet.stream.format.isString ? 0.0 : inlet.stream.rate;
  final arrivals = options.eventDriven && inlet is LslArrivals
      ? inlet as LslArrivals
      : null;

  late final StreamController<LslChunk> controller;
  StreamSubscription<LslChunk>? listener;
  Timer? timer;
  Future<void>? polling;
  var cancelled = false;
  var failures = 0;
  var faults = debugListenerFaults;

  Future<void> poll() async {
    final interval = Duration(milliseconds: options.pullIntervalMs);
    // Room for a few intervals, so one pull usually gets everything.
    final max = math.max(
      64,
      (math.max(rate, 1) * options.pullIntervalMs / 1000 * 8).ceil(),
    );
    while (!cancelled) {
      try {
        while (!cancelled) {
          final c = await inlet.pull(max);
          if (c.length == 0 || cancelled) break;
          controller.add(c);
          if (c.length < max) break;
        }
      } catch (e, st) {
        if (cancelled) return;
        controller.addError(e, st);
        unawaited(controller.close());
        return;
      }
      await Future<void>.delayed(interval);
    }
  }

  void listen() {
    timer = null;
    if (cancelled) return;
    Object? cause;
    int? failAfter;
    if (faults > 0) {
      faults--;
      failAfter = 1;
    }
    listener = arrivals!
        .arrivals(
          // A quarter of a second at most in one chunk.
          maxSamples: math.max(256, (rate / 4).ceil()),
          // A fast stream that is sent sample by sample would otherwise
          // deliver sample by sample. Markers are wanted at once.
          coalesce: rate > 0 ? const Duration(milliseconds: 5) : Duration.zero,
          debugFailAfter: failAfter,
        )
        .listen(
          controller.add,
          // The reason comes first and the end after it.
          onError: (Object e) => cause = e,
          onDone: () {
            listener = null;
            timer?.cancel();
            timer = null;
            if (cancelled) return;
            failures++;
            final why = '${cause ?? 'it ended without an error'}';
            if (failures >= receiveFallbackAfter) {
              onStatus?.call(
                LslReceiveStatus(
                  eventDriven: false,
                  failures: failures,
                  cause: why,
                  fellBack: true,
                ),
              );
              polling = poll();
              return;
            }
            onStatus?.call(
              LslReceiveStatus(
                eventDriven: true,
                failures: failures,
                cause: why,
              ),
            );
            timer = Timer(
              Duration(milliseconds: 100 << (failures - 1)),
              listen,
            );
          },
        );
    if (failures > 0) {
      timer = Timer(_stableAfter, () {
        timer = null;
        failures = 0;
        onStatus?.call(const LslReceiveStatus(eventDriven: true));
      });
    }
  }

  controller = StreamController<LslChunk>(
    onListen: () {
      onStatus?.call(LslReceiveStatus(eventDriven: arrivals != null));
      if (arrivals != null) {
        listen();
      } else {
        polling = poll();
      }
    },
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      timer = null;
      await listener?.cancel();
      listener = null;
      await polling;
    },
  );
  return controller.stream;
}
