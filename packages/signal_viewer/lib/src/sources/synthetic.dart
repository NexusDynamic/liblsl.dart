import 'package:flutter/foundation.dart';
import 'package:signal_core/signal_core.dart';

import '../model/stream_info.dart';
import '../model/view_settings.dart';
import '../viewer/source.dart';
import 'live_buffers.dart';
import 'live_source.dart';
import 'stream_source.dart';

/// What a synthetic stream sends: the signal, its markers (if any) and
/// what goes wrong with it.
class SynthOptions {
  final SynthSpec spec;

  /// Null for no marker stream.
  final MarkerSchedule? markers;
  final Impairments impairments;

  const SynthOptions({
    this.spec = const SynthSpec(),
    this.markers,
    this.impairments = Impairments.none,
  });

  SynthOptions copyWith({
    SynthSpec? spec,
    MarkerSchedule? Function()? markers,
    Impairments? impairments,
  }) => SynthOptions(
    spec: spec ?? this.spec,
    markers: markers == null ? this.markers : markers(),
    impairments: impairments ?? this.impairments,
  );
}

/// A synthetic signal made in the app and shown as a live stream, with no
/// LSL or device in between: for trying the viewer's displays and testing
/// its performance at any channel count and rate.
///
/// The signal is stream 0; its markers, if sent, are stream 1 (a tab of
/// their own). Samples lost in a simulated dropout are filled by
/// interpolation, as for LSL and serial streams.
class SyntheticSession extends SourceSession implements LiveData {
  final String name;
  final SynthOptions options;
  late final SynthRun _run;
  late final RegularRing _ring;
  IrregularLog? _log;
  final _changes = Changes();
  final Stopwatch _clock = Stopwatch()..start();
  bool _closed = false;

  late final StreamInfo info;
  StreamInfo? markerInfo;

  /// With [clock] and [tick] for tests: the run is then pumped by hand.
  SyntheticSession(
    this.name,
    this.options, {
    double Function()? clock,
    Duration? tick = const Duration(milliseconds: 20),
  }) {
    final spec = options.spec;
    final g = spec.generator();
    info = StreamInfo(
      key: 'synthetic:$name',
      name: name,
      type: 'EEG',
      kind: Kind.eeg,
      rate: spec.rate,
      labels: g.labels,
      units: g.units,
      channels: [for (var c = 0; c < spec.channels; c++) ChannelRef(0, c)],
    );
    _ring = RegularRing(spec.channels, spec.rate);
    if (options.markers != null) {
      _log = IrregularLog(1, keepS: 2 * liveBufferS, strings: true);
      markerInfo = StreamInfo(
        key: 'synthetic:$name:markers',
        name: '$name markers',
        type: 'Markers',
        kind: Kind.event,
        rate: 0,
        labels: const ['marker'],
        units: const [''],
        channels: const [ChannelRef(1, 0)],
      );
    }
    _run = SynthRun(
      g,
      clock: clock ?? () => _clock.elapsedMicroseconds / 1e6,
      impairments: options.impairments,
      markers: options.markers,
      onChunk: _onChunk,
      onMarkers: _log == null ? null : _onMarkers,
      tick: tick,
    );
  }

  /// Send the samples due now (see [SynthRun.pump]).
  @visibleForTesting
  void pump() => _run.pump();

  void _onChunk(SynthChunk c) {
    if (_closed) return;
    final ch = _ring.channelCount;
    // Samples lost before these (a dropout).
    _ring.fill(c.first - _ring.written, c.values);
    for (var i = 0; i < c.count; i++) {
      _ring.add(c.values, i * ch);
    }
    _changes.ping();
  }

  void _onMarkers(List<SynthMarker> markers) {
    if (_closed) return;
    final nan = [double.nan];
    for (final m in markers) {
      _log!.add(m.time - _run.startTime, nan, 0, [m.text]);
    }
    _changes.ping();
  }

  int get sent => _run.sent;
  int get lost => _run.lost;

  // -- SourceSession ----------------------------------------------------------

  @override
  List<StreamInfo> get streams => [info, ?markerInfo];

  @override
  String get label => 'Synthetic';

  @override
  String get titleSuffix => _closed ? ' (stopped)' : '';

  @override
  String get tooltip => describe();

  @override
  bool get groupable => false;

  @override
  String get rememberKey => 'synthetic:$name';

  @override
  bool get closed => _closed;

  @override
  bool decodable(StreamInfo info) => info.key == this.info.key;

  @override
  StreamSource sourceFor(StreamInfo info) => LiveStreamSource(this, info);

  @override
  String describe() {
    final s = options.spec;
    return [
      'Synthetic: ${s.preset.label}',
      '${s.channels} ch at ${formatNumber(s.rate)} Hz',
      if (lost > 0) '${_ring.lost} samples lost',
    ].join(' · ');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _run.stop();
    notifyListeners();
  }

  // -- LiveData ---------------------------------------------------------------

  @override
  Listenable get changes => _changes;

  @override
  double get now => _ring.written == 0 ? 0 : _ring.end;

  @override
  List<Float64List>? columnsAt(
    List<ChannelRef> refs,
    double rate,
    int from,
    int to,
  ) => ringColumns({0: _ring}, refs, rate, from, to);

  @override
  (int, int)? tickRange(List<ChannelRef> refs, double rate) =>
      ringTickRange({0: _ring}, refs, rate);

  @override
  EventSamples events(int stream) => stream == 1 && _log != null
      ? _log!.events(markers: true)
      : EventSamples.empty;
}
