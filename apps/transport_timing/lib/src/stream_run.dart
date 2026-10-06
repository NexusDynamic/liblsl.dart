import 'dart:async';

import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:timing_core/timing_core.dart';

import 'settings.dart';

/// The node uId behind a transport's source id.
///
/// The LSL transport names a source `stream//role//uId//id`; the others use
/// the uId itself.
String nodeUIdOf(String sourceId) {
  final parts = sourceId.split('//');
  return parts.length >= 4 ? parts[2] : sourceId;
}

/// One device's part in a run on a coordinator data stream: it sends
/// numbered samples and logs everything it receives, with the timing the
/// transport measured for it.
class StreamRun {
  StreamRun({
    required this.stream,
    required this.config,
    required this.log,
    required this.clock,
    this.onSample,
  });

  final DataStream stream;
  final RunConfig config;
  final RunLogWriter log;

  /// This device's monotonic clock, in the domain the transport reports
  /// receive times in.
  final double Function() clock;

  /// Called for every sample received, with the sender's node uId and the
  /// sample's sequence number.
  final void Function(String fromUId, int seq)? onSample;

  final List<StreamSubscription<void>> _subscriptions = [];
  Timer? _sendTimer;
  int _seq = 0;
  late final List<double> _sample = List.filled(config.channels, 0);

  int get sent => _seq;
  int received = 0;

  /// Starts logging what arrives and, for a latency run, sending.
  void start() {
    _subscriptions.add(stream.inbox.listen(_onMessage));
    _subscriptions.add(
      stream.clockSyncs.listen((sync) {
        final source = sync.sourceId;
        if (source == null) return;
        log.clockSync(
          nodeUIdOf(source),
          receivedClock: sync.receivedClock,
          offset: sync.offset,
          remoteTime: sync.remoteTime,
          uncertainty: sync.uncertainty,
          clockReset: sync.clockReset,
        );
      }),
    );
    if (config.test != TestKind.latency) return;

    // A timer cannot tick faster than about once a millisecond and is often
    // late, so each tick sends every sample that has fallen due rather than
    // exactly one. The log records when each was really sent.
    final watch = Stopwatch()..start();
    final total = (config.sampleRate * config.durationSeconds).round();
    final period = Duration(
      microseconds: (1e6 / config.sampleRate).round().clamp(1000, 1000000),
    );
    _sendTimer = Timer.periodic(period, (timer) {
      final due = (watch.elapsedMicroseconds * config.sampleRate / 1e6)
          .floor()
          .clamp(0, total);
      while (_seq < due) {
        send();
      }
      if (_seq >= total) timer.cancel();
    });
  }

  /// Sends the next sample and returns its sequence number.
  int send() {
    final seq = ++_seq;
    _sample[0] = seq.toDouble();
    log.sent(seq, clock());
    // A copy: the transport may still hold the list when the next is sent.
    unawaited(stream.sendData(List<double>.of(_sample)));
    return seq;
  }

  void _onMessage(IMessage message) {
    final timing = message.timing;
    // The in-memory transport hands over the sender's own object, with no
    // timing and so no sender.
    final source = timing?.sourceId;
    final from = source == null ? 'unknown' : nodeUIdOf(source);
    final seq = (message.data[0] as num).toInt();
    received++;
    log.received(
      from,
      seq,
      // The transport takes this as the sample arrives; without it, now is
      // the best there is.
      receivedClock: timing?.receivedClock ?? clock(),
      sourceClock: timing?.sourceClock,
      clockOffset: timing?.clockOffset,
      uncertainty: timing?.uncertainty,
    );
    onSample?.call(from, seq);
  }

  Future<void> finish() async {
    _sendTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
