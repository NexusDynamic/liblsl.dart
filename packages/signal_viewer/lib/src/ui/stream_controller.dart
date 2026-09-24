import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:signal_core/signal_core.dart';

import '../display/colors.dart';
import '../display/manchester.dart';
import '../display/power.dart';
import '../display/scale.dart';
import '../model/stream_info.dart';
import '../model/view_settings.dart';
import '../sources/live_buffers.dart';
import '../sources/stream_source.dart';

/// Shortest time window, in seconds.
const minWindowS = 0.5;

/// Height of an event trace, in lanes.
const eventHeight = 0.8;

/// Power of each channel over the window and, for the heatmap, per bin.
class PowerData {
  final String metric;

  /// Per output channel (NaN where it could not be computed).
  final Float64List perChannel;

  /// Heatmap bins: start of the first, length of each, values per channel.
  final double binStart;
  final double binS;
  final List<Float64List> binned;

  const PowerData(
    this.metric,
    this.perChannel,
    this.binStart,
    this.binS,
    this.binned,
  );
}

/// State and data of one tab: the time window, display settings and the
/// data fetched for them.
///
/// Listeners of the controller hear about changes to settings and to what
/// the controls show; new data only fires [repaint], so the controls are
/// not rebuilt for every live frame.
class StreamController extends ChangeNotifier {
  final StreamSource source;
  ViewSettings _settings;
  ManchesterSettings _manchester;

  /// Start of the window (recordings). Live views follow the newest data.
  double _t0 = 0;

  /// Width of the plot in physical pixels: the number of bins requested.
  int _bins = 1000;

  bool _active = false;
  bool _disposed = false;

  Envelope? _data;
  Envelope? _overview;
  PowerData? _power;
  ui.Image? _heatmap;

  /// The overview's activity per channel as an image, see [_setActivity].
  ui.Image? _activity;
  (double, double)? _powerLevels;

  double? _autoScale;
  final Map<int, double> _channelScales = {};

  final _dataPipe = _Pipe();
  final _overviewPipe = _Pipe();
  final _powerPipe = _Pipe();
  final _qualityPipe = _Pipe();
  Timer? _liveTimer;

  /// Pending refresh while a recording is indexed, see [_onSourceChanged].
  Timer? _indexTimer;

  /// Pending quality and power update after the window moved, see
  /// [_windowChanged].
  Timer? _settleTimer;

  /// [StreamSource.end] when the window's data was last fetched.
  double _fetchedEnd = 0;
  DateTime _lastPower = DateTime(0);
  DateTime _lastQuality = DateTime(0);

  final _frame = _Frame();
  late final Listenable repaint = Listenable.merge([this, _frame]);

  late QualityTracker _tracker = _newTracker();
  List<ChannelQuality> _quality = const [];

  /// Raw samples the quality was last measured on.
  List<List<double>>? _qualityRaw;

  List<List<DecodedWord>>? _words;
  Object? _wordsKey;
  List<double>? _eventPeaks;

  String? error;

  StreamController(
    this.source,
    ViewSettings settings, {
    ManchesterSettings manchester = const ManchesterSettings(),
  }) : _settings = settings.validFor(source.info),
       // ignore: prefer_initializing_formals
       _manchester = manchester {
    _t0 = source.start;
    source.changes.addListener(_onSourceChanged);
  }

  StreamInfo get info => source.info;

  ViewSettings get settings => _settings;

  ManchesterSettings get manchester => _manchester;

  Envelope? get data => _data;

  Envelope? get overview => _overview;

  PowerData? get power => _power;

  ui.Image? get heatmap => _heatmap;

  /// Activity (peak-to-peak on a log scale) of [overview]: one row per
  /// output channel, one pixel per bin.
  ui.Image? get activity => _activity;

  (double, double)? get powerLevels => _powerLevels;

  /// Quality of each channel (empty when not measured).
  List<ChannelQuality> get quality => _quality;

  ChannelQuality qualityOf(int ch) =>
      ch < _quality.length ? _quality[ch] : ChannelQuality.unknown;

  /// Whether channel quality is measured: EEG/EMG with several channels.
  bool get qualityActive => info.badChannels && !info.irregular;

  /// Whether data is being fetched.
  bool get busy =>
      _settleTimer != null ||
      _dataPipe.running ||
      _overviewPipe.running ||
      _powerPipe.running ||
      _qualityPipe.running;

  /// Whether the trace data is for the current window and settings.
  bool get settled => !busy && !(_data?.approximate ?? false);

  /// Whether the tab is visible; only visible tabs fetch data.
  bool get active => _active;

  set active(bool v) {
    if (_active == v) return;
    _active = v;
    if (v) {
      _refreshAll();
    } else {
      _liveTimer?.cancel();
      _liveTimer = null;
      _indexTimer?.cancel();
      _indexTimer = null;
      _settleTimer?.cancel();
      _settleTimer = null;
    }
  }

  // -- window ---------------------------------------------------------------

  double get windowS => _settings.windowS;

  double get maxWindowS {
    if (source.live) return liveBufferS;
    return math.max(minWindowS, source.end - source.start);
  }

  double get t0 => source.live ? math.max(0, source.end - windowS) : _t0;

  double get t1 => t0 + windowS;

  bool get live => source.live;

  /// Move the window to start at [t].
  void scrollTo(double t) {
    if (source.live) return;
    final lo = source.start;
    final hi = math.max(lo, source.end - windowS);
    final v = t.clamp(lo, hi).toDouble();
    if (v == _t0) return;
    _t0 = v;
    _windowChanged();
  }

  /// Move by [fraction] of the window.
  void scrollBy(double fraction) => scrollTo(_t0 + fraction * windowS);

  /// Set the window length, keeping its centre (or its start at the
  /// beginning of the recording).
  void setWindow(double seconds) {
    final w = seconds.clamp(minWindowS, maxWindowS).toDouble();
    if (w == windowS) return;
    final centre = _t0 + windowS / 2;
    _settings = _settings.copyWith(windowS: w);
    if (!source.live) {
      final atStart = _t0 <= source.start + 1e-9;
      _t0 = atStart ? source.start : centre - w / 2;
      final hi = math.max(source.start, source.end - w);
      _t0 = _t0.clamp(source.start, hi).toDouble();
    }
    _windowChanged();
  }

  /// Step the window through the 1-2-5 series.
  void stepWindow(int direction) =>
      setWindow(stepScale(windowS, direction).clamp(minWindowS, maxWindowS));

  /// Zoom by [factor] around the time [anchor] (e.g. under the pointer).
  void zoom(double factor, double anchor) {
    final w = (windowS * factor).clamp(minWindowS, maxWindowS).toDouble();
    if (w == windowS) return;
    final f = (anchor - t0) / windowS;
    _settings = _settings.copyWith(windowS: w);
    if (!source.live) {
      final hi = math.max(source.start, source.end - w);
      _t0 = (anchor - f * w).clamp(source.start, hi).toDouble();
    }
    _windowChanged();
  }

  /// Plot width in physical pixels.
  void setBins(int bins) {
    bins = bins.clamp(16, maxBins);
    if (bins == _bins) return;
    _bins = bins;
    _changed(data: true, overview: true, notify: false);
  }

  // -- settings -------------------------------------------------------------

  void update(ViewSettings s) {
    final old = _settings;
    _settings = s.validFor(info);
    final spec =
        derivedSpec(info, old, lanesOf(old)) !=
        derivedSpec(info, _settings, lanes);
    if (_settings.scaleMode != old.scaleMode ||
        !setEquals(_settings.bad, old.bad) ||
        _settings.mean != old.mean) {
      _autoScale = null;
      _channelScales.clear();
      _updateScales();
    }
    if (_settings.notch != old.notch) {
      _tracker = _newTracker();
      _quality = const [];
    }
    _changed(
      data: spec,
      overview: spec,
      power:
          spec ||
          _settings.colour != old.colour ||
          _settings.powerMetric != old.powerMetric ||
          _settings.powerStyle != old.powerStyle,
      quality:
          !setEquals(_settings.bad, old.bad) || _settings.notch != old.notch,
    );
    if (!spec) notifyListeners();
  }

  // -- channels and reference -----------------------------------------------

  /// Leave channel [ch] out of the average reference (and the mean), or put
  /// it back.
  void setExcluded(int ch, bool excluded) => update(
    _settings.copyWith(
      bad: excluded ? {..._settings.bad, ch} : ({..._settings.bad}..remove(ch)),
    ),
  );

  void toggleExcluded(int ch) => setExcluded(ch, !_settings.bad.contains(ch));

  /// Reference every channel to [ch].
  void useAsReference(int ch) =>
      update(_settings.copyWith(refMode: RefMode.channel, refChannels: {ch}));

  /// Add [ch] to the channels whose mean is the reference, or remove it.
  void toggleInReferenceSet(int ch) {
    final current = _settings.refMode == RefMode.channel
        ? {..._settings.refChannels.take(1)}
        : {..._settings.refChannels};
    final refs = current.contains(ch)
        ? (current..remove(ch))
        : {...current, ch};
    update(
      _settings.copyWith(
        refMode: refs.isEmpty ? RefMode.recorded : RefMode.subset,
        refChannels: refs,
      ),
    );
  }

  /// What the channels are referenced to, e.g. "average of 14/16".
  String get referenceSummary {
    final s = _settings;
    if (!info.canReference) return 'as recorded';
    String names(Iterable<int> chans) => [
      for (final c in chans.toList()..sort())
        if (c < info.channelCount) info.labels[c],
    ].join(', ');
    switch (s.refMode) {
      case RefMode.recorded:
        return 'as recorded';
      case RefMode.average:
        final n = info.channelCount - s.bad.length;
        return 'average of $n/${info.channelCount}'
            '${s.bad.isEmpty ? '' : ' (excluded: ${names(s.bad)})'}';
      case RefMode.channel:
        return s.refChannels.isEmpty
            ? 'one channel (none chosen)'
            : names(s.refChannels.take(1));
      case RefMode.subset:
        return s.refChannels.isEmpty
            ? 'mean of chosen channels (none chosen)'
            : 'mean of ${names(s.refChannels)}';
    }
  }

  /// Exclude every channel flagged bad, measuring again without them, up
  /// to five times (a very bad channel can hide a less bad one). Returns
  /// the channels newly excluded.
  Set<int> excludeFlagged() {
    final raw = _qualityRaw;
    if (raw == null) return const {};
    final t = QualityTracker(lineHz: _lineHz, smoothing: 1);
    var bad = {..._settings.bad};
    final added = <int>{};
    for (var pass = 0; pass < 5; pass++) {
      final q = t.update(raw, info.rate, exclude: bad);
      final more = {
        for (var c = 0; c < q.length; c++)
          if (q[c].flag == ChannelFlag.bad && !bad.contains(c)) c,
      };
      if (more.isEmpty) break;
      added.addAll(more);
      bad = {...bad, ...more};
    }
    if (added.isNotEmpty) update(_settings.copyWith(bad: bad));
    return added;
  }

  set manchester(ManchesterSettings m) {
    _manchester = m;
    _wordsKey = null;
    notifyListeners();
  }

  /// Channels shown, top to bottom.
  List<int> get lanes => lanesOf(_settings);

  List<int> lanesOf(ViewSettings s) => [
    for (var c = 0; c < info.channelCount; c++)
      if (!s.hidden.contains(c)) c,
  ];

  /// Channels that make up the mean trace: shown and not bad.
  List<int> get averaged => [
    for (final c in lanes)
      if (!_settings.bad.contains(c)) c,
  ];

  DerivedSpec get spec => derivedSpec(info, _settings, lanes);

  bool get meanMode => _settings.mean && info.canMean;

  // -- scales ---------------------------------------------------------------

  /// Value per lane for output channel [ch] (the mean trace is
  /// [info.channelCount]), or null when there is nothing to scale by.
  double scaleFor(int ch) {
    switch (_settings.scaleMode) {
      case ScaleMode.fixed:
        return _settings.scale;
      case ScaleMode.auto:
        return _autoScale ?? _settings.scale;
      case ScaleMode.perChannel:
        return _channelScales[ch] ?? _settings.scale;
    }
  }

  /// The shared scale shown on the scale bar, or null in per-channel mode.
  double? get sharedScale =>
      _settings.scaleMode == ScaleMode.perChannel ? null : scaleFor(0);

  /// Baseline subtracted from output channel [ch].
  double baselineFor(int ch) {
    if (!(_settings.baseline || _settings.scaleMode == ScaleMode.perChannel)) {
      return 0;
    }
    final d = _data;
    if (d == null || ch >= d.stats.length) return 0;
    final m = d.stats[ch].mean;
    return m.isFinite ? m : 0;
  }

  /// Wheel over the plot: step the fixed scale.
  void stepAmplitude(int direction) {
    if (_settings.scaleMode == ScaleMode.perChannel) return;
    final current = scaleFor(0);
    update(
      _settings.copyWith(
        scaleMode: ScaleMode.fixed,
        scale: stepScale(current, direction).clamp(1e-3, 1e7),
      ),
    );
  }

  /// Update the auto scales from the data; returns whether any changed.
  bool _updateScales() {
    final d = _data;
    if (d == null) return false;
    final before = (_autoScale, {..._channelScales});
    if (_settings.scaleMode == ScaleMode.auto) {
      final chans = meanMode
          ? [info.channelCount]
          : (() {
              final good = averaged;
              return good.isEmpty ? lanes : good;
            })();
      final stds = [
        for (final c in chans)
          if (c < d.stats.length) d.stats[c].std,
      ];
      _autoScale = settle(_autoScale, autoScaleShared(stds));
    } else if (_settings.scaleMode == ScaleMode.perChannel) {
      for (var c = 0; c < d.stats.length; c++) {
        final s = d.stats[c];
        if (s.isEmpty) continue;
        _channelScales[c] = settle(
          _channelScales[c],
          autoScaleChannel(s.peakDeviation),
        )!;
      }
    }
    return before.$1 != _autoScale || !mapEquals(before.$2, _channelScales);
  }

  // -- colours --------------------------------------------------------------

  Color laneColor(int ch, {required bool dark}) {
    if (_settings.bad.contains(ch)) return badChannelColor;
    final p = _power;
    final levels = _powerLevels;
    if (p != null &&
        levels != null &&
        powerActive &&
        _settings.powerStyle != PowerStyle.heatmap &&
        ch < p.perChannel.length) {
      final (lo, hi) = levels;
      return viridis((p.perChannel[ch] - lo) / (hi - lo));
    }
    return channelColor(ch, info.channelCount, dark: dark);
  }

  bool get powerActive =>
      _settings.colour == ColourMode.power &&
      info.filterable &&
      !meanMode &&
      info.kind != Kind.event;

  // -- events ---------------------------------------------------------------

  EventSamples events() => source.events();

  /// Largest absolute value of each event channel (at least 1), to
  /// normalise the step traces.
  List<double> eventPeaks(EventSamples e) {
    if (_eventPeaks != null &&
        _eventPeaks!.length == e.channels.length &&
        !source.live) {
      return _eventPeaks!;
    }
    return _eventPeaks = [
      for (final ch in e.channels)
        ch.fold<double>(1, (m, v) => v.abs() > m ? v.abs() : m),
    ];
  }

  /// Decoded Manchester words per channel (empty for channels not
  /// decoded).
  List<List<DecodedWord>> words() {
    final e = events();
    // Marker streams carry their values as text already.
    if (e.markers) return const [];
    final key = (_settings.decoded, _manchester, e.length, source.end);
    if (_words != null && _wordsKey == key) return _words!;
    _wordsKey = key;
    return _words = [
      for (var c = 0; c < e.channels.length; c++)
        _settings.decoded.contains(c)
            ? decodeManchester(
                e.times,
                e.channels[c],
                settings: _manchester,
                tEnd: source.live ? source.end : double.infinity,
              ).$1
            : const [],
    ];
  }

  // -- fetching -------------------------------------------------------------

  void _onSourceChanged() {
    if (!_active) return;
    if (source.live) {
      // Redraw at most ~30 times a second.
      _liveTimer ??= Timer(const Duration(milliseconds: 33), () {
        _liveTimer = null;
        final now = DateTime.now();
        _changed(
          data: true,
          power: now.difference(_lastPower).inMilliseconds >= 200,
          quality: now.difference(_lastQuality).inMilliseconds >= 500,
          notify: false,
        );
      });
      return;
    }
    if (source.indexing || source.derivedProgress != null) {
      // Index growth or progress of a filtered summary: refetching
      // everything each time competes with that work (and requests queue
      // behind it). Refresh about once a second, and the window only if it
      // reaches newly indexed data or is still approximate.
      _indexTimer ??= Timer(const Duration(seconds: 1), () {
        _indexTimer = null;
        if (!_active) return;
        if (_t0 < source.start) _t0 = source.start;
        final grown =
            _data == null || t1 > _fetchedEnd || (_data?.approximate ?? false);
        _changed(data: grown, overview: true, power: grown, quality: grown);
      });
      return;
    }
    // A file: indexing finished, or a derived summary is done.
    _indexTimer?.cancel();
    _indexTimer = null;
    if (_t0 < source.start) _t0 = source.start;
    _changed(data: true, overview: true, power: true, quality: true);
  }

  /// The window moved or changed length: fetch its data now, and measure
  /// quality and power once it stops changing (not for every step of a
  /// drag).
  void _windowChanged() {
    _changed(data: true);
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 250), () {
      _settleTimer = null;
      _changed(power: true, quality: true);
    });
  }

  void _refreshAll() =>
      _changed(data: true, overview: true, power: true, quality: true);

  /// Fetch what changed; [notify] tells the controls too (otherwise only
  /// the plot is repainted when data arrives).
  void _changed({
    bool data = false,
    bool overview = false,
    bool power = false,
    bool quality = false,
    bool notify = true,
  }) {
    if (_disposed) return;
    if (notify) notifyListeners();
    if (!_active) return;
    if (data) _dataPipe.run(_fetchData);
    if (overview && !source.live) _overviewPipe.run(_fetchOverview);
    if (power) _powerPipe.run(_fetchPower);
    if (quality && qualityActive) _qualityPipe.run(_fetchQuality);
  }

  Future<void> _fetchData() async {
    if (info.irregular) {
      notifyListeners();
      return;
    }
    final hadData = _data != null;
    final oldError = error;
    var scales = false;
    _fetchedEnd = source.end;
    try {
      final d = await source.envelope(t0, t1, _bins, spec);
      if (_disposed) return;
      _data = d;
      error = null;
      scales = _updateScales();
    } catch (e) {
      error = '$e';
    }
    if (_disposed) return;
    if (!hadData || scales || error != oldError) notifyListeners();
    _frame.ping();
  }

  Future<void> _fetchOverview() async {
    if (info.irregular) return;
    try {
      final d = await source.envelope(
        source.start,
        math.max(source.start + minWindowS, source.end),
        math.min(_bins, 2000),
        spec,
      );
      if (_disposed) return;
      _overview = d;
      await _setActivity(d);
      if (_disposed) return;
    } catch (e) {
      error = '$e';
    }
    if (!_disposed) _frame.ping();
  }

  Future<void> _fetchPower() async {
    _lastPower = DateTime.now();
    if (!powerActive) {
      if (_power != null) {
        _power = null;
        _powerLevels = null;
        _setHeatmap(null);
        notifyListeners();
      }
      return;
    }
    final s = _settings;
    final metric = s.powerMetric;
    final heat = s.powerStyle != PowerStyle.trace;
    final binS = heatmapBin(metric, windowS);
    final w0 = t0, w1 = t1;
    PowerData? result;
    try {
      if (metric == 'rms') {
        // RMS is the standard deviation, available at any zoom.
        final d = _data ?? await source.envelope(w0, w1, _bins, spec);
        final per = Float64List.fromList([
          for (final st in d?.stats ?? const <SignalStats>[]) st.std,
        ]);
        var binned = <Float64List>[];
        var first = w0;
        if (heat) {
          first = (w0 / binS).floor() * binS;
          final last = (w1 / binS).ceil() * binS;
          final bins = math.max(1, ((last - first) / binS).round());
          final env = await source.envelope(
            first,
            last,
            bins,
            spec,
            binStats: true,
          );
          binned = [
            for (final c in env?.binStd ?? const <Float32List>[])
              Float64List.fromList(c),
          ];
        }
        result = PowerData(metric, per, first, binS, binned);
      } else if (windowS <= maxBandWindowS) {
        final w = await source.read(w0, w1, spec);
        if (w != null && w.length > 0) {
          result = await compute(_bandPower, (
            w.channels,
            w.start,
            w.samplingRate,
            metric,
            heat ? binS : 0.0,
          ));
        }
      }
    } catch (e) {
      error = '$e';
    }
    if (_disposed) return;
    final hadLevels = _powerLevels != null;
    _power = result;
    _powerLevels = _levels(result);
    await _setHeatmap(result);
    if (_disposed) return;
    if (hadLevels != (_powerLevels != null)) notifyListeners();
    _frame.ping();
  }

  double get _lineHz => _settings.notch ?? 50;

  QualityTracker _newTracker() => QualityTracker(
    lineHz: _settings.notch ?? 50,
    // Live: smooth over a few updates; recordings: the window as it is.
    smoothing: source.live ? 0.3 : 1,
  );

  /// Seconds of data the quality is measured on (the newest, live).
  static const qualityWindowS = 2.0;

  Future<void> _fetchQuality() async {
    _lastQuality = DateTime.now();
    final double a, b;
    if (source.live) {
      b = source.end;
      a = math.max(source.start, b - qualityWindowS);
    } else {
      // The middle of the window, at most 10 s of it.
      final w = math.min(windowS, 10.0);
      a = t0 + (windowS - w) / 2;
      b = a + w;
    }
    List<ChannelQuality>? q;
    try {
      final w = await source.read(a, b, DerivedSpec.none);
      if (w != null && w.length > 0) {
        final raw = [for (final c in w.channels) List<double>.of(c)];
        _qualityRaw = raw;
        q = _tracker.update(raw, info.rate, exclude: _settings.bad);
      }
    } catch (e) {
      error = '$e';
    }
    if (_disposed || q == null) return;
    final flagsChanged =
        q.length != _quality.length ||
        [
          for (var i = 0; i < q.length; i++) q[i].flag != _quality[i].flag,
        ].any((x) => x);
    _quality = q;
    if (flagsChanged) notifyListeners();
    _frame.ping();
  }

  (double, double)? _levels(PowerData? p) {
    if (p == null) return null;
    final good = averaged;
    final pool = <double>[
      if (_settings.powerStyle != PowerStyle.heatmap)
        for (final c in good)
          if (c < p.perChannel.length) p.perChannel[c],
      if (_settings.powerStyle != PowerStyle.trace)
        for (final c in good)
          if (c < p.binned.length) ...p.binned[c],
    ];
    return percentileLevels(pool);
  }

  /// Heatmap image: one row per lane, one column per bin.
  /// Colour each bin of [env] by its peak-to-peak on a log scale between a
  /// quarter of its channel's median and the 99th percentile, as pixels
  /// (transparent without data), so the overview draws one image instead
  /// of a rectangle per bin.
  Future<void> _setActivity(Envelope? env) async {
    final old = _activity;
    final rows = env == null || env.samples ? 0 : env.min.length;
    final cols = env?.length ?? 0;
    if (rows == 0 || cols == 0) {
      _activity = null;
      old?.dispose();
      return;
    }
    final pixels = Uint8List(rows * cols * 4);
    final tmp = Float64List(cols);
    for (var r = 0; r < rows; r++) {
      final mn = env!.min[r], mx = env.max[r];
      var n = 0;
      for (var b = 0; b < cols; b++) {
        final p = mx[b] - mn[b];
        if (p.isFinite && p > 0) tmp[n++] = p;
      }
      if (n == 0) continue;
      final sorted = Float64List.sublistView(tmp, 0, n).toList()..sort();
      final median = sorted[n ~/ 2];
      final top = sorted[math.min(n - 1, (n * 0.99).floor())];
      final lo = math.log(median / 4);
      final hi = math.log(math.max(top, median * 4));
      for (var b = 0; b < cols; b++) {
        final p = mx[b] - mn[b];
        if (!p.isFinite || p <= 0) continue;
        final c = viridis((math.log(p) - lo) / (hi - lo));
        final o = (r * cols + b) * 4;
        pixels[o] = (c.r * 255).round();
        pixels[o + 1] = (c.g * 255).round();
        pixels[o + 2] = (c.b * 255).round();
        pixels[o + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      cols,
      rows,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    _activity = await completer.future;
    old?.dispose();
  }

  Future<void> _setHeatmap(PowerData? p) async {
    final old = _heatmap;
    if (p == null ||
        _powerLevels == null ||
        _settings.powerStyle == PowerStyle.trace ||
        p.binned.isEmpty) {
      _heatmap = null;
      old?.dispose();
      return;
    }
    final rows = lanes;
    final cols = p.binned.first.length;
    if (rows.isEmpty || cols == 0) {
      _heatmap = null;
      old?.dispose();
      return;
    }
    final (lo, hi) = _powerLevels!;
    final pixels = Uint8List(rows.length * cols * 4);
    for (var r = 0; r < rows.length; r++) {
      final values = rows[r] < p.binned.length ? p.binned[rows[r]] : null;
      for (var b = 0; b < cols; b++) {
        final v = values?[b] ?? double.nan;
        final o = (r * cols + b) * 4;
        if (!v.isFinite) continue; // transparent
        final c = viridis((v - lo) / (hi - lo));
        // Opaque pixels: the painter draws the image translucent.
        pixels[o] = (c.r * 255).round();
        pixels[o + 1] = (c.g * 255).round();
        pixels[o + 2] = (c.b * 255).round();
        pixels[o + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      cols,
      rows.length,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    _heatmap = await completer.future;
    old?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _liveTimer?.cancel();
    _indexTimer?.cancel();
    _settleTimer?.cancel();
    _frame.dispose();
    source.changes.removeListener(_onSourceChanged);
    _heatmap?.dispose();
    _activity?.dispose();
    super.dispose();
  }
}

PowerData _bandPower((List<Float32List>, double, double, String, double) args) {
  final (channels, start, rate, metric, binS) = args;
  final per = Float64List.fromList([
    for (final c in channels) bandPower(Float64List.fromList(c), rate, metric),
  ]);
  if (binS <= 0) return PowerData(metric, per, start, 0, const []);
  final (first, binned) = binnedBandPower(channels, start, rate, metric, binS);
  return PowerData(metric, per, first, binS, binned);
}

class _Frame extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Most bins (points per trace) asked for, whatever the plot's width.
const maxBins = 2000;

/// Runs an async job with at most one in flight; a request made while one
/// runs starts one more afterwards (the newest state wins).
class _Pipe {
  bool _running = false;
  bool _again = false;

  bool get running => _running || _again;

  void run(Future<void> Function() job) {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    job().whenComplete(() {
      _running = false;
      if (_again) {
        _again = false;
        run(job);
      }
    });
  }
}
