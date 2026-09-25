import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fftea/fftea.dart';
import 'package:flutter/material.dart';
import 'package:signal_core/signal_core.dart';

import '../../display/colors.dart';
import '../../model/stream_info.dart';
import '../stream_controller.dart';
import 'stream_plot.dart';
import 'trace_painter.dart';

/// A tab's plot in its current view ([StreamController.view]).
class TabPlot extends StatelessWidget {
  final StreamController controller;
  final PlotStyle style;
  final void Function(int channel)? onRename;

  const TabPlot({
    super.key,
    required this.controller,
    required this.style,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => switch (controller.view) {
      PlotView.traces => StreamPlot(
        key: ObjectKey(controller),
        controller: controller,
        style: style,
        onRename: onRename,
      ),
      PlotView.spectrogram => SpectrogramView(
        key: ValueKey((controller, 'spectrogram')),
        controller: controller,
        style: style,
      ),
      PlotView.xy => XyView(
        key: ValueKey((controller, 'xy')),
        controller: controller,
        style: style,
      ),
    },
  );
}

/// Keeps the full-resolution samples of the controller's window up to date
/// (throttled to [interval]).
mixin _WindowSamples<T extends StatefulWidget> on State<T> {
  StreamController get controller;
  Duration get interval;

  SignalWindow? samples;
  bool _busy = false;
  bool _again = false;
  Timer? _throttle;
  (double, double, DerivedSpec)? _last;

  void startSamples() {
    controller.addListener(_changed);
    _fetch();
  }

  void stopSamples() {
    controller.removeListener(_changed);
    _throttle?.cancel();
  }

  void _changed() {
    final key = (controller.t0, controller.t1, controller.spec);
    if (!controller.live && key == _last) return;
    if (_throttle != null) return;
    _throttle = Timer(interval, () {
      _throttle = null;
      _fetch();
    });
  }

  Future<void> _fetch() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      final c = controller;
      _last = (c.t0, c.t1, c.spec);
      final w = await c.source.read(c.t0, c.t1, c.spec);
      if (!mounted) return;
      samples = w;
      onSamples();
      setState(() {});
    } catch (_) {
      // Nothing to show for this window.
    } finally {
      _busy = false;
      if (_again && mounted) {
        _again = false;
        unawaited(_fetch());
      }
    }
  }

  /// New [samples] arrived.
  void onSamples() {}
}

TextPainter _text(String s, PlotStyle style, {double size = 11}) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(
      color: style.dark ? Colors.white70 : Colors.black87,
      fontSize: size,
      fontFamily: style.fontFamily,
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();

String _hz(double v) => v >= 1000
    ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)} kHz'
    : '${v.toStringAsFixed(0)} Hz';

// -- spectrogram --------------------------------------------------------------

/// A spectrogram of one channel over the window: frequency up, time right,
/// power in dB as colour (viridis, the top 70 dB).
class SpectrogramView extends StatefulWidget {
  final StreamController controller;
  final PlotStyle style;

  const SpectrogramView({
    super.key,
    required this.controller,
    required this.style,
  });

  @override
  State<SpectrogramView> createState() => _SpectrogramViewState();
}

class _SpectrogramViewState extends State<SpectrogramView>
    with _WindowSamples<SpectrogramView> {
  @override
  StreamController get controller => widget.controller;

  @override
  Duration get interval => const Duration(milliseconds: 150);

  ui.Image? _image;
  double _rate = 0;

  /// Times of the centres of the first and last frames.
  double _from = 0, _to = 0;
  int _columns = 600;

  @override
  void initState() {
    super.initState();
    startSamples();
  }

  @override
  void dispose() {
    stopSamples();
    _image?.dispose();
    super.dispose();
  }

  @override
  void onSamples() => _render();

  Future<void> _render() async {
    final w = samples;
    if (w == null || w.length < 16) return;
    final ch = controller.spectrogramChannel.clamp(0, w.channels.length - 1);
    final x = w.channels[ch];
    final rate = w.samplingRate;
    // Frames of about a quarter second (EEG) down to ~40 ms (audio).
    var n = 64;
    while (n < rate / 4 && n < 2048) {
      n *= 2;
    }
    if (x.length < n) {
      n = math.max(16, 1 << (math.log(x.length) / math.ln2).floor());
    }
    final frames = math.min(_columns, math.max(1, x.length - n + 1));
    final hop = frames > 1 ? (x.length - n) / (frames - 1) : 0.0;
    final rows = n ~/ 2;
    final fft = FFT(n);
    final hann = Float64List(n);
    for (var i = 0; i < n; i++) {
      hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    }
    final db = Float64List(frames * rows);
    final frame = Float64List(n);
    var top = double.negativeInfinity;
    for (var f = 0; f < frames; f++) {
      final start = (f * hop).round();
      var mean = 0.0, count = 0;
      for (var i = 0; i < n; i++) {
        final v = x[start + i];
        if (v.isFinite) {
          mean += v;
          count++;
        }
      }
      mean = count > 0 ? mean / count : 0;
      for (var i = 0; i < n; i++) {
        final v = x[start + i];
        frame[i] = (v.isFinite ? v - mean : 0) * hann[i];
      }
      final spec = fft.realFft(frame);
      for (var r = 0; r < rows; r++) {
        final c = spec[r + 1];
        final p = c.x * c.x + c.y * c.y;
        final v = 10 * math.log(p + 1e-20) / math.ln10;
        db[f * rows + r] = v;
        if (v > top) top = v;
      }
    }
    const range = 70.0;
    final pixels = Uint8List(frames * rows * 4);
    for (var f = 0; f < frames; f++) {
      for (var r = 0; r < rows; r++) {
        final t = ((db[f * rows + r] - (top - range)) / range).clamp(0.0, 1.0);
        final c = viridis(t);
        // Low frequencies at the bottom.
        final o = ((rows - 1 - r) * frames + f) * 4;
        pixels[o] = (c.r * 255).round();
        pixels[o + 1] = (c.g * 255).round();
        pixels[o + 2] = (c.b * 255).round();
        pixels[o + 3] = 255;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      frames,
      rows,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    final image = await done.future;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _rate = rate;
      _from = w.start + (n / 2) / rate;
      _to = w.start + ((frames - 1) * hop + n / 2) / rate;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _columns = math.max(64, math.min(1200, box.maxWidth.round()));
      final c = controller;
      return CustomPaint(
        size: Size.infinite,
        painter: _SpectrogramPainter(
          _image,
          _rate,
          _from,
          _to,
          c.t0,
          c.t1,
          c.info.labels[c.spectrogramChannel.clamp(0, c.info.channelCount - 1)],
          widget.style,
        ),
      );
    },
  );
}

class _SpectrogramPainter extends CustomPainter {
  final ui.Image? image;
  final double rate;

  /// Times the image spans (frame centres), and of the window.
  final double from, to;
  final double t0, t1;
  final String channel;
  final PlotStyle style;

  _SpectrogramPainter(
    this.image,
    this.rate,
    this.from,
    this.to,
    this.t0,
    this.t1,
    this.channel,
    this.style,
  );

  static const _left = 64.0, _bottom = 22.0, _top = 8.0, _right = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;
    final img = image;
    if (img != null && t1 > t0) {
      // Each column covers a frame: half a column beyond the centres.
      final col = img.width > 1 ? (to - from) / (img.width - 1) : to - from;
      double x(double t) => plot.left + (t - t0) / (t1 - t0) * plot.width;
      canvas.save();
      canvas.clipRect(plot);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTRB(
          x(from - col / 2),
          plot.top,
          x(to + col / 2),
          plot.bottom,
        ),
        Paint()..filterQuality = FilterQuality.low,
      );
      canvas.restore();
    }
    final line = Paint()
      ..color = style.dark ? Colors.white24 : Colors.black26
      ..strokeWidth = 1;
    canvas.drawRect(plot, line..style = PaintingStyle.stroke);
    if (rate > 0) {
      for (final f in [0.0, rate / 8, rate / 4, rate * 3 / 8, rate / 2]) {
        final y = plot.bottom - f / (rate / 2) * plot.height;
        final tp = _text(_hz(f), style, size: 10);
        tp.paint(canvas, Offset(_left - tp.width - 6, y - tp.height / 2));
      }
    }
    for (var k = 0; k <= 4; k++) {
      final t = t0 + (t1 - t0) * k / 4;
      final x = plot.left + plot.width * k / 4;
      final tp = _text(
        t.toStringAsFixed(t1 - t0 < 10 ? 2 : 1),
        style,
        size: 10,
      );
      tp.paint(canvas, Offset(x - tp.width / 2, plot.bottom + 4));
    }
    final label = _text(channel, style);
    label.paint(canvas, Offset(plot.left + 6, plot.top + 4));
  }

  @override
  bool shouldRepaint(_SpectrogramPainter old) =>
      old.image != image ||
      old.from != from ||
      old.t0 != t0 ||
      old.t1 != t1 ||
      old.channel != channel ||
      old.style.dark != style.dark;
}

// -- XY -------------------------------------------------------------------------

/// Two channels against each other over the window (e.g. gaze or a
/// position): a trail that fades from the oldest sample to the newest.
class XyView extends StatefulWidget {
  final StreamController controller;
  final PlotStyle style;

  const XyView({super.key, required this.controller, required this.style});

  @override
  State<XyView> createState() => _XyViewState();
}

class _XyViewState extends State<XyView> with _WindowSamples<XyView> {
  @override
  StreamController get controller => widget.controller;

  @override
  Duration get interval => const Duration(milliseconds: 33);

  @override
  void initState() {
    super.initState();
    startSamples();
  }

  @override
  void dispose() {
    stopSamples();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final w = samples;
    final n = c.info.channelCount;
    final xc = c.xChannel.clamp(0, n - 1), yc = c.yChannel.clamp(0, n - 1);
    return CustomPaint(
      size: Size.infinite,
      painter: _XyPainter(
        w == null || xc >= w.channels.length ? null : w.channels[xc],
        w == null || yc >= w.channels.length ? null : w.channels[yc],
        c.info.labels[xc],
        c.info.labels[yc],
        prettyUnit(c.info.unit(xc)),
        widget.style,
      ),
    );
  }
}

class _XyPainter extends CustomPainter {
  final Float32List? x, y;
  final String xLabel, yLabel, unit;
  final PlotStyle style;

  _XyPainter(this.x, this.y, this.xLabel, this.yLabel, this.unit, this.style);

  static const _pad = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _pad,
      12,
      size.width - 16,
      size.height - _pad * 0.6,
    );
    if (plot.width <= 0 || plot.height <= 0) return;
    final grid = Paint()
      ..color = style.dark ? Colors.white24 : Colors.black26
      ..style = PaintingStyle.stroke;
    canvas.drawRect(plot, grid);
    final xs = x, ys = y;
    if (xs == null || ys == null) return;
    var x0 = double.infinity, x1 = double.negativeInfinity;
    var y0 = double.infinity, y1 = double.negativeInfinity;
    final n = math.min(xs.length, ys.length);
    for (var i = 0; i < n; i++) {
      final a = xs[i], b = ys[i];
      if (!a.isFinite || !b.isFinite) continue;
      x0 = math.min(x0, a);
      x1 = math.max(x1, a);
      y0 = math.min(y0, b);
      y1 = math.max(y1, b);
    }
    if (!x0.isFinite) return;
    if (x1 - x0 < 1e-9) {
      x0 -= 1;
      x1 += 1;
    }
    if (y1 - y0 < 1e-9) {
      y0 -= 1;
      y1 += 1;
    }
    final px = (x1 - x0) * 0.05, py = (y1 - y0) * 0.05;
    x0 -= px;
    x1 += px;
    y0 -= py;
    y1 += py;
    Offset at(double a, double b) => Offset(
      plot.left + (a - x0) / (x1 - x0) * plot.width,
      plot.bottom - (b - y0) / (y1 - y0) * plot.height,
    );
    final base = style.dark ? const Color(0xFF7FD4FF) : const Color(0xFF1565C0);
    final stroke = Paint()
      ..strokeWidth = style.lineWidth
      ..isAntiAlias = style.antialias;
    // Draw in slices, older ones fainter.
    const slices = 16;
    Offset? prev;
    for (var s = 0; s < slices; s++) {
      final path = Path();
      final from = n * s ~/ slices, to = n * (s + 1) ~/ slices;
      var started = false;
      if (prev != null) {
        path.moveTo(prev.dx, prev.dy);
        started = true;
      }
      for (var i = from; i < to; i++) {
        final a = xs[i], b = ys[i];
        if (!a.isFinite || !b.isFinite) {
          started = false;
          prev = null;
          continue;
        }
        final o = at(a, b);
        if (started) {
          path.lineTo(o.dx, o.dy);
        } else {
          path.moveTo(o.dx, o.dy);
          started = true;
        }
        prev = o;
      }
      canvas.drawPath(
        path,
        stroke
          ..style = PaintingStyle.stroke
          ..color = base.withValues(alpha: 0.15 + 0.85 * (s + 1) / slices),
      );
    }
    if (prev != null) {
      canvas.drawCircle(prev, 4, Paint()..color = base);
    }
    String num(double v) => v.abs() >= 100 || v == 0
        ? v.toStringAsFixed(0)
        : v.toStringAsPrecision(3);
    final u = unit.isEmpty ? '' : ' $unit';
    _text(
      '$xLabel$u',
      style,
    ).paint(canvas, Offset(plot.center.dx - 20, plot.bottom + 12));
    _text(
      num(x0 + px),
      style,
      size: 10,
    ).paint(canvas, Offset(plot.left, plot.bottom + 2));
    final xr = _text(num(x1 - px), style, size: 10);
    xr.paint(canvas, Offset(plot.right - xr.width, plot.bottom + 2));
    canvas.save();
    canvas.translate(4, plot.center.dy + 20);
    canvas.rotate(-math.pi / 2);
    _text('$yLabel$u', style).paint(canvas, Offset.zero);
    canvas.restore();
    final yt = _text(num(y1 - py), style, size: 10);
    yt.paint(canvas, Offset(plot.left - yt.width - 4, plot.top));
    final yb = _text(num(y0 + py), style, size: 10);
    yb.paint(canvas, Offset(plot.left - yb.width - 4, plot.bottom - yb.height));
  }

  @override
  bool shouldRepaint(_XyPainter old) => true;
}
