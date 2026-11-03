import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'components.dart';
import 'generator.dart';

/// What goes wrong with a simulated stream: samples lost in dropouts, and
/// jitter in their time stamps.
class Impairments {
  /// Dropouts per second, on average.
  final double dropoutRate;

  /// Length of a dropout, in seconds.
  final double dropoutS;

  /// Standard deviation of the time stamps' error, in seconds.
  final double jitterS;

  const Impairments({
    this.dropoutRate = 0,
    this.dropoutS = 0.2,
    this.jitterS = 0,
  });

  static const none = Impairments();

  bool get isNone => dropoutRate <= 0 && jitterS <= 0;
}

/// When a [SynthRun] sends markers: every [every] seconds (`tick 1`,
/// `tick 2`, …), and/or at the events of the signal (`blink`, `spike`, …)
/// if [atEvents].
class MarkerSchedule {
  final double? every;
  final bool atEvents;

  const MarkerSchedule({this.every = 1, this.atEvents = true});
}

/// A text marker at [time] (on the run's clock).
class SynthMarker {
  final double time;
  final String text;

  const SynthMarker(this.time, this.text);

  @override
  String toString() => 'SynthMarker($time, $text)';
}

/// Samples made by a [SynthRun]: [count] samples from sample [first],
/// interleaved by channel, each stamped with its time on the run's clock
/// (jitter included).
class SynthChunk {
  final int first;
  final int count;
  final Float64List values;
  final Float64List times;

  const SynthChunk(this.first, this.count, this.values, this.times);
}

/// Sends a [SignalGenerator]'s samples in real time on [clock] (seconds):
/// on each tick, the samples due since the last one. Samples in a dropout
/// are made but not sent, so the signal carries on after the gap; markers
/// are sent regardless.
///
/// With [tick] null it does not run on a timer, and [pump] sends what is
/// due (e.g. in tests, with a clock of their own).
class SynthRun {
  final SignalGenerator generator;
  final double Function() clock;
  final Impairments impairments;
  final MarkerSchedule? markers;
  final void Function(SynthChunk chunk) onChunk;
  final void Function(List<SynthMarker> markers)? onMarkers;

  /// At most this many seconds are made at once; after a longer pause
  /// (e.g. the computer slept) the rest is dropped as lost.
  final double maxCatchUpS;

  /// Clock time of sample 0.
  late final double startTime;

  final math.Random _random;
  Timer? _timer;
  bool _stopped = false;

  /// Sample at which the current dropout ends, if in one.
  int _dropoutEnd = -1;
  int _nextTick = 1;

  /// Samples sent, and lost in dropouts.
  int sent = 0;
  int lost = 0;

  SynthRun(
    this.generator, {
    required this.clock,
    required this.onChunk,
    this.impairments = Impairments.none,
    this.markers,
    this.onMarkers,
    Duration? tick = const Duration(milliseconds: 20),
    this.maxCatchUpS = 1,
  }) : _random = math.Random(generator.seed ^ 0x5bd1e995) {
    startTime = clock() - generator.time;
    if (tick != null) _timer = Timer.periodic(tick, (_) => pump());
  }

  double get rate => generator.rate;

  bool get stopped => _stopped;

  /// Send the samples due by now.
  void pump() {
    if (_stopped) return;
    final g = generator;
    final due = ((clock() - startTime) * rate).floor();
    var n = due - g.sampleIndex;
    if (n <= 0) return;
    final cap = math.max(1, (maxCatchUpS * rate).round());
    final marks = <SynthMarker>[];
    if (n > cap) {
      _drop(n - cap, marks);
      n = cap;
    }
    // Split at the edges of dropouts.
    while (n > 0) {
      if (_dropoutEnd > g.sampleIndex) {
        final k = math.min(n, _dropoutEnd - g.sampleIndex);
        _drop(k, marks);
        n -= k;
        continue;
      }
      // Whether a dropout starts in these samples.
      final p = impairments.dropoutRate * n / rate;
      if (p > 0 && _random.nextDouble() < p) {
        final at = g.sampleIndex + (_random.nextDouble() * n).floor();
        _dropoutEnd = at + math.max(1, (impairments.dropoutS * rate).round());
        final k = at - g.sampleIndex;
        if (k > 0) _send(k, marks);
        n -= k;
        continue;
      }
      _send(n, marks);
      n = 0;
    }
    _ticks(marks);
    if (marks.isNotEmpty && onMarkers != null) {
      // In time order; at the same time, events before ticks.
      final order = [for (var i = 0; i < marks.length; i++) i]
        ..sort((a, b) {
          final c = marks[a].time.compareTo(marks[b].time);
          return c != 0 ? c : a.compareTo(b);
        });
      onMarkers!([for (final i in order) marks[i]]);
    }
  }

  void _send(int n, List<SynthMarker> marks) {
    final g = generator;
    final first = g.sampleIndex;
    final (values, events) = g.next(n);
    final times = Float64List(n);
    final jitter = impairments.jitterS;
    for (var i = 0; i < n; i++) {
      times[i] = startTime + (first + i) / rate;
      if (jitter > 0) times[i] += jitter * _gaussian();
    }
    _events(events, marks);
    sent += n;
    onChunk(SynthChunk(first, n, values, times));
  }

  void _drop(int n, List<SynthMarker> marks) {
    _events(generator.skip(n), marks);
    lost += n;
  }

  void _events(List<SynthEvent> events, List<SynthMarker> marks) {
    if (markers?.atEvents != true) return;
    for (final e in events) {
      marks.add(SynthMarker(startTime + e.sample / rate, e.label));
    }
  }

  /// A tick once the sample at its time has been made.
  void _ticks(List<SynthMarker> marks) {
    final every = markers?.every;
    if (every == null || every <= 0) return;
    while (_nextTick * every < generator.time) {
      marks.add(SynthMarker(startTime + _nextTick * every, 'tick $_nextTick'));
      _nextTick++;
    }
  }

  double _gaussian() {
    final u = 1 - _random.nextDouble();
    final v = _random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
  }
}
