import 'package:flutter/foundation.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:timing_core/timing_core.dart';

/// The channels of every stream, in order.
const _labels = [
  'latency',
  'latency (fitted)',
  'offset change',
  'offset bound',
];

/// The most samples a stream is laid out for; a log claiming a longer
/// sequence is shown by arrival time instead.
const _maxRegular = 20000000;

/// An open run log: a tab for each source the device received from, with
/// its latency and clock offset over the run.
class TimingSession extends SourceSession {
  TimingSession(this.name, this.log, {this.path, required this.nameOf})
    : pairs = analyse([log]).runs.single.pairs {
    _series = [for (final pair in pairs) _Series.of(pair, log.header)];
  }

  final String name;
  final String? path;
  final RunLog log;

  /// What this log alone says about each source.
  final List<PairReport> pairs;

  /// The device name behind a source id, when its log is open too.
  final String? Function(String sourceId) nameOf;

  late final List<_Series> _series;
  bool _closed = false;

  /// The sources may have gained names from a log opened since.
  void refreshNames() => notifyListeners();

  @override
  List<StreamInfo> get streams => [
    for (final (index, pair) in pairs.indexed)
      StreamInfo(
        key:
            'timing:${log.header.runId}:${log.header.deviceId}:'
            '${pair.sourceId}',
        name:
            '${nameOf(pair.sourceId) ?? pair.from} → '
            '${log.header.deviceName}',
        type: 'Timing',
        kind: Kind.other,
        rate: _series[index].rate,
        labels: _labels,
        units: const ['ms', 'ms', 'ms', 'ms'],
        channels: [
          for (var c = 0; c < _labels.length; c++) ChannelRef(index, c),
        ],
      ),
  ];

  @override
  String get label => name;

  @override
  String get tooltip => path ?? name;

  @override
  bool get groupable => false;

  @override
  String get rememberKey => 'timing:$name';

  @override
  String get memberNoun => 'sources';

  @override
  bool decodable(StreamInfo info) => false;

  @override
  bool get closed => _closed;

  @override
  StreamSource sourceFor(StreamInfo info) =>
      _TimingStreamSource(this, info, _series[info.channels.first.stream]);

  @override
  String describe() {
    final h = log.header;
    return [
      name,
      '${h.test} over ${h.backend}',
      if (h.receiveMode != null) h.receiveMode!,
      '${pairs.length} source${pairs.length == 1 ? '' : 's'}',
    ].join(' · ');
  }

  @override
  Future<void> close() async => _closed = true;
}

/// One source's values in milliseconds, laid out for the plot.
///
/// A latency run numbers its samples at a fixed rate, so they are placed by
/// sequence number: time is when each sample was due, and a lost sample is
/// a gap. An interactive run has no rate; its samples are placed by when
/// they arrived.
final class _Series {
  _Series.regular(this.rate, this.columns) : times = null;
  _Series.irregular(this.times, this.columns) : rate = 0;

  final double rate;
  final List<Float64List> columns;
  final Float64List? times;

  factory _Series.of(PairReport pair, RunHeader header) {
    final s = pair.series;
    final n = s.seq.length;
    var firstOffset = double.nan;
    for (var i = 0; i < n && firstOffset.isNaN; i++) {
      firstOffset = s.clockOffset[i];
    }
    // The offset itself can be any size (the clocks' epochs are unrelated);
    // what a plot can show is how it moves.
    List<double> row(int i) => [
      s.latency[i] * 1e3,
      s.latencyFitted[i] * 1e3,
      (s.clockOffset[i] - firstOffset) * 1e3,
      s.uncertainty[i] * 500,
    ];

    var lowest = 0, highest = -1;
    if (n > 0) {
      lowest = highest = s.seq[0];
      for (final seq in s.seq) {
        if (seq < lowest) lowest = seq;
        if (seq > highest) highest = seq;
      }
    }
    final length = highest - lowest + 1;
    if (header.sampleRate > 0 && length > 0 && length <= _maxRegular) {
      final columns = [
        for (final _ in _labels)
          Float64List(length)..fillRange(0, length, double.nan),
      ];
      // Backwards, so the first arrival of a duplicated sample is kept.
      for (var i = n - 1; i >= 0; i--) {
        final values = row(i);
        for (var c = 0; c < columns.length; c++) {
          columns[c][s.seq[i] - lowest] = values[c];
        }
      }
      return _Series.regular(header.sampleRate, columns);
    }

    final columns = [for (final _ in _labels) Float64List(n)];
    final times = Float64List(n);
    for (var i = 0; i < n; i++) {
      times[i] = s.receivedClock[i] - s.receivedClock[0];
      final values = row(i);
      for (var c = 0; c < columns.length; c++) {
        columns[c][i] = values[c];
      }
    }
    return _Series.irregular(times, columns);
  }

  int get length => columns.first.length;
}

class _TimingStreamSource implements StreamSource {
  _TimingStreamSource(this.session, this.info, this._series);

  final TimingSession session;
  @override
  final StreamInfo info;
  final _Series _series;

  /// The whole series with the tab's processing (a mean trace) applied.
  LiveProcessor? _processor;

  List<Float64List> get _columns => [
    for (final ref in info.channels) _series.columns[ref.channel],
  ];

  (List<Float64List>, double)? _window(
    double t0,
    double t1,
    DerivedSpec derived,
  ) {
    if (info.irregular || session.closed) return null;
    final n = _series.length;
    final from = (t0 * info.rate).floor().clamp(0, n);
    final to = (t1 * info.rate).ceil().clamp(from, n);
    if (derived.isIdentity) {
      return (
        [for (final c in _columns) Float64List.sublistView(c, from, to)],
        from / info.rate,
      );
    }
    var processor = _processor;
    if (processor == null || processor.spec != derived) {
      processor = _processor = LiveProcessor(
        derived,
        info.channelCount,
        info.rate,
        n,
      )..append(_columns, 0);
    }
    return (processor.read(from, to), from / info.rate);
  }

  @override
  bool get live => false;

  @override
  Listenable get changes => session;

  @override
  double? get derivedProgress => null;

  @override
  bool get indexing => false;

  @override
  double get start => 0;

  @override
  double get end {
    final times = _series.times;
    if (times == null) return _series.length / _series.rate;
    return times.isEmpty ? 0 : times.last;
  }

  @override
  Future<Envelope?> envelope(
    double t0,
    double t1,
    int bins,
    DerivedSpec derived, {
    bool binStats = false,
  }) async {
    final window = _window(t0, t1, derived);
    if (window == null) return null;
    final (columns, start) = window;
    return envelopeOf(
      columns,
      start,
      info.rate,
      t0,
      t1,
      bins,
      binStats: binStats,
    );
  }

  @override
  Future<SignalWindow?> read(double t0, double t1, DerivedSpec derived) async {
    final window = _window(t0, t1, derived);
    if (window == null) return null;
    final (columns, start) = window;
    return SignalWindow(start, info.rate, [
      for (final c in columns) Float32List.fromList(c),
    ]);
  }

  @override
  EventSamples events() {
    final times = _series.times;
    if (times == null) return EventSamples.empty;
    return EventSamples(times, [
      for (final c in _columns) Float32List.fromList(c),
    ]);
  }
}
