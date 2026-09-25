import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:signal_core/signal_core.dart';

import '../../display/colors.dart';
import '../../display/power.dart';
import '../../model/stream_info.dart';
import '../../model/view_settings.dart';
import '../../sources/stream_source.dart';
import '../stream_controller.dart';

/// Look of the plots (Preferences).
class PlotStyle {
  final double lineWidth;
  final bool antialias;
  final bool dark;

  /// Font of the plot's text (the app's font).
  final String? fontFamily;

  const PlotStyle({
    this.lineWidth = 1,
    this.antialias = true,
    required this.dark,
    this.fontFamily,
  });

  Color get background =>
      dark ? const Color(0xFF19191C) : const Color(0xFFFFFFFF);
  Color get foreground =>
      dark ? const Color(0xFFDCDCDC) : const Color(0xFF000000);
  Color get grid => foreground.withValues(alpha: 0.12);

  @override
  bool operator ==(Object other) =>
      other is PlotStyle &&
      other.lineWidth == lineWidth &&
      other.antialias == antialias &&
      other.dark == dark &&
      other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(lineWidth, antialias, dark, fontFamily);
}

/// Where things are in the plot.
class PlotGeometry {
  static const double leftAxis = 88;
  static const double bottomAxis = 26;
  static const double top = 6;

  final Size size;
  final int laneCount;
  final bool colourBar;

  PlotGeometry(this.size, this.laneCount, {this.colourBar = false});

  double get right => size.width - (colourBar ? 72 : 8);

  Rect get plot => Rect.fromLTRB(
    leftAxis,
    top,
    math.max(leftAxis + 1, right),
    math.max(top + 1, size.height - bottomAxis),
  );

  /// Height of one lane in pixels. Lanes sit one unit apart with 0.6 of a
  /// lane of margin above the first and below the last.
  double get unit => plot.height / (math.max(laneCount, 1) - 1 + 1.2);

  double laneCentre(int lane) => plot.top + (0.6 + lane) * unit;

  /// The lane under [y], or null.
  int? laneAt(double y) {
    final lane = ((y - plot.top) / unit - 0.6).round();
    return lane >= 0 && lane < laneCount ? lane : null;
  }

  double x(double t, double t0, double t1) =>
      plot.left + (t - t0) / (t1 - t0) * plot.width;

  double time(double x, double t0, double t1) =>
      t0 + (x - plot.left) / plot.width * (t1 - t0);
}

class TracePainter extends CustomPainter {
  final StreamController c;
  final PlotStyle style;

  TracePainter(this.c, this.style) : super(repaint: c.repaint);

  static final Map<String, TextPainter> _labels = {};

  TextPainter _text(String s, Color color, {double size = 11}) =>
      plotText(s, color, size: size, fontFamily: style.fontFamily);

  /// Laid-out text, cached across frames.
  static TextPainter plotText(
    String s,
    Color color, {
    double size = 11,
    String? fontFamily,
  }) {
    final key = '$s|${color.toARGB32()}|$size|$fontFamily';
    return _labels.putIfAbsent(key, () {
      if (_labels.length > 4000) _labels.clear();
      return TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 200);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final info = c.info;
    final s = c.settings;
    final mean = c.meanMode;
    final lanes = mean ? [info.channelCount] : c.lanes;
    final geo = PlotGeometry(
      size,
      lanes.length,
      colourBar: c.powerActive && c.powerLevels != null,
    );
    final plot = geo.plot;
    final t0 = c.t0, t1 = c.t1;
    canvas.drawRect(Offset.zero & size, Paint()..color = style.background);

    _drawTimeAxis(canvas, geo, t0, t1);
    _drawLaneLabels(canvas, geo, lanes, mean);

    canvas.save();
    canvas.clipRect(plot);
    final heat = c.heatmap;
    final power = c.power;
    if (heat != null && power != null && !mean && lanes.isNotEmpty) {
      final x0 = geo.x(power.binStart, t0, t1);
      final x1 = geo.x(power.binStart + power.binS * heat.width, t0, t1);
      final top = geo.laneCentre(0) - geo.unit / 2;
      final bottom = geo.laneCentre(lanes.length - 1) + geo.unit / 2;
      canvas.drawImageRect(
        heat,
        Rect.fromLTWH(0, 0, heat.width.toDouble(), heat.height.toDouble()),
        Rect.fromLTRB(x0, top, x1, bottom),
        Paint()
          ..filterQuality = FilterQuality.none
          ..color = const Color.fromRGBO(0, 0, 0, 80 / 255),
      );
    }

    if (info.kind == Kind.event || info.irregular) {
      _drawEvents(canvas, geo, lanes, t0, t1);
    } else {
      _drawTraces(canvas, geo, lanes, t0, t1, mean);
    }
    canvas.restore();

    _drawScaleBar(canvas, geo, info, s);
    if (geo.colourBar) _drawColourBar(canvas, geo);
    if (c.data?.approximate ?? false) {
      final p = c.source.derivedProgress;
      final label = p == null
          ? 'Filtering…'
          : 'Filtering… ${(p * 100).toStringAsFixed(0)}%';
      final tp = _text(label, style.foreground, size: 11);
      final r = Rect.fromLTWH(
        plot.right - tp.width - 16,
        plot.top + 4,
        tp.width + 12,
        tp.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()..color = style.background.withValues(alpha: 0.85),
      );
      tp.paint(canvas, r.topLeft + const Offset(6, 3));
    }
  }

  void _drawTimeAxis(Canvas canvas, PlotGeometry geo, double t0, double t1) {
    final plot = geo.plot;
    final span = t1 - t0;
    if (span <= 0) return;
    // About one tick per 90 px, on a 1-2-5 step.
    final raw = span / math.max(1, plot.width / 90);
    final decade = math.pow(10, (math.log(raw) / math.ln10).floor());
    var step = decade.toDouble();
    for (final m in [1, 2, 5, 10]) {
      if (m * decade >= raw) {
        step = m * decade.toDouble();
        break;
      }
    }
    final digits = step >= 1 ? 0 : (-(math.log(step) / math.ln10).floor());
    final gridPaint = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    final axis = Paint()
      ..color = style.foreground.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    for (var t = (t0 / step).ceil() * step; t <= t1 + 1e-9; t += step) {
      final x = geo.x(t, t0, t1);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(x, plot.bottom), Offset(x, plot.bottom + 4), axis);
      final tp = _text(_formatTime(t, digits), style.foreground, size: 10);
      tp.paint(canvas, Offset(x - tp.width / 2, plot.bottom + 6));
    }
    final unit = _text(
      'time (s)',
      style.foreground.withValues(alpha: 0.6),
      size: 10,
    );
    unit.paint(canvas, Offset(8, plot.bottom + 6));
  }

  static String _formatTime(double t, int digits) {
    if (digits == 0 && t.abs() >= 3600) {
      final h = t ~/ 3600;
      final m = (t % 3600) ~/ 60;
      final sec = (t % 60).round();
      return '$h:${m.toString().padLeft(2, '0')}:'
          '${sec.toString().padLeft(2, '0')}';
    }
    return t.toStringAsFixed(digits);
  }

  void _drawLaneLabels(
    Canvas canvas,
    PlotGeometry geo,
    List<int> lanes,
    bool mean,
  ) {
    final info = c.info;
    final s = c.settings;
    final refs = s.refMode == RefMode.channel
        ? s.refChannels.take(1).toSet()
        : s.refMode == RefMode.subset
        ? s.refChannels
        : const <int>{};
    final dot = Paint();
    final cross = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var lane = 0; lane < lanes.length; lane++) {
      final ch = lanes[lane];
      final String label;
      final bad = !mean && s.bad.contains(ch);
      if (mean) {
        label = 'Mean (${c.averaged.length} ch)';
      } else {
        label = '${info.labels[ch]}${refs.contains(ch) ? ' (ref)' : ''}';
      }
      final color = mean ? style.foreground : c.laneColor(ch, dark: style.dark);
      final tp = _text(label, color, size: 11);
      final y = geo.laneCentre(lane);
      final x = PlotGeometry.leftAxis - tp.width - 8;
      tp.paint(canvas, Offset(x, y - tp.height / 2));
      // Bad channels get a cross before the label, drawn rather than a
      // glyph: the web's default font has no ✕.
      if (bad) {
        const r = 3.0;
        final cx = x - r - 4;
        cross.color = color;
        canvas
          ..drawLine(Offset(cx - r, y - r), Offset(cx + r, y + r), cross)
          ..drawLine(Offset(cx - r, y + r), Offset(cx + r, y - r), cross);
      }
      // Quality flag: a dot at the left edge.
      if (mean) continue;
      final flag = c.qualityOf(ch).flag;
      if (flag == ChannelFlag.ok) continue;
      dot.color = flag == ChannelFlag.bad ? flagBadColor : flagWarnColor;
      canvas.drawCircle(Offset(7, y), 4, dot);
    }
  }

  void _drawTraces(
    Canvas canvas,
    PlotGeometry geo,
    List<int> lanes,
    double t0,
    double t1,
    bool mean,
  ) {
    final d = c.data;
    if (d == null || d.min.isEmpty) return;
    final plot = geo.plot;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.lineWidth * (mean ? 1.5 : 1)
      ..isAntiAlias = style.antialias
      // Round joins cost far more to draw (every frame under Impeller).
      ..strokeJoin = StrokeJoin.bevel;
    for (var lane = 0; lane < lanes.length; lane++) {
      final ch = lanes[lane];
      if (ch >= d.min.length) continue;
      final scale = c.scaleFor(ch);
      final base = c.baselineFor(ch);
      final centre = geo.laneCentre(lane);
      final k = geo.unit / scale;
      paint.color = mean ? style.foreground : c.laneColor(ch, dark: style.dark);
      if (c.settings.bad.contains(ch)) {
        paint.color = badChannelColor.withValues(alpha: 0.8);
      }
      if (d.samples) {
        final pts = _samplePoints(d, ch, geo, t0, t1, centre, base, k, plot);
        for (final run in pts) {
          canvas.drawRawPoints(ui.PointMode.polygon, run, paint);
        }
      } else {
        final bars = _binBars(d, ch, geo, t0, t1, centre, base, k, paint);
        if (bars != null) canvas.drawVertices(bars, BlendMode.srcOver, paint);
      }
    }
  }

  /// Polylines through the samples, split where data is missing.
  List<Float32List> _samplePoints(
    Envelope d,
    int ch,
    PlotGeometry geo,
    double t0,
    double t1,
    double centre,
    double base,
    double k,
    Rect plot,
  ) {
    final values = d.min[ch];
    final n = values.length;
    if (n == 0) return const [];
    // Only samples in the window, plus one on each side.
    final i0 = math.max(0, ((t0 - d.start) / d.step).floor() - 1);
    final i1 = math.min(n, ((t1 - d.start) / d.step).ceil() + 2);
    final runs = <Float32List>[];
    var buf = Float32List(math.max(0, (i1 - i0) * 2));
    var len = 0;
    final sx = plot.width / (t1 - t0);
    for (var i = i0; i < i1; i++) {
      final v = values[i];
      if (v.isNaN) {
        if (len > 2) runs.add(Float32List.sublistView(buf, 0, len));
        buf = Float32List(buf.length);
        len = 0;
        continue;
      }
      buf[len++] = plot.left + (d.start + i * d.step - t0) * sx;
      buf[len++] = centre - (v - base) * k;
    }
    if (len > 2) runs.add(Float32List.sublistView(buf, 0, len));
    return runs;
  }

  /// One bar per bin from its min to its max, as triangles: filled
  /// columns where the signal is dense, a line where it is not. Bars that
  /// do not overlap their neighbour both reach the midpoint between them,
  /// so the trace is continuous, and every bar is at least the line width
  /// tall. Triangles cost the renderer little, unlike a polyline of
  /// thousands of points (whose joins are rebuilt every frame under
  /// Impeller). Null if there is nothing to draw.
  ui.Vertices? _binBars(
    Envelope d,
    int ch,
    PlotGeometry geo,
    double t0,
    double t1,
    double centre,
    double base,
    double k,
    Paint paint,
  ) {
    final mins = d.min[ch], maxs = d.max[ch];
    final n = mins.length;
    if (n == 0) return null;
    final plot = geo.plot;
    final sx = plot.width / (t1 - t0);
    final half = d.step * sx / 2;
    // Screen y of each bin's top (max) and bottom (min); NaN for no data.
    final top = Float64List(n), bottom = Float64List(n);
    for (var b = 0; b < n; b++) {
      top[b] = centre - (maxs[b] - base) * k;
      bottom[b] = centre - (mins[b] - base) * k;
    }
    // Close the gaps between neighbours, from the original extents.
    final up = Float64List.fromList(top), down = Float64List.fromList(bottom);
    for (var b = 0; b + 1 < n; b++) {
      if (top[b].isNaN || top[b + 1].isNaN) continue;
      if (top[b] > bottom[b + 1]) {
        // The next bin is entirely above this one.
        final mid = (top[b] + bottom[b + 1]) / 2;
        up[b] = math.min(up[b], mid);
        down[b + 1] = math.max(down[b + 1], mid);
      } else if (bottom[b] < top[b + 1]) {
        // The next bin is entirely below.
        final mid = (bottom[b] + top[b + 1]) / 2;
        down[b] = math.max(down[b], mid);
        up[b + 1] = math.min(up[b + 1], mid);
      }
    }
    final minHeight = paint.strokeWidth;
    final pos = Float32List(n * 8);
    // Four corners per bar; at most 2000 bins, so indices fit 16 bits.
    final idx = Uint16List(n * 6);
    var v = 0, i = 0;
    for (var b = 0; b < n; b++) {
      var y0 = up[b], y1 = down[b];
      if (y0.isNaN || y1.isNaN) continue;
      if (y1 - y0 < minHeight) {
        final m = (y0 + y1) / 2;
        y0 = m - minHeight / 2;
        y1 = m + minHeight / 2;
      }
      final x = plot.left + (d.start + (b + 0.5) * d.step - t0) * sx;
      final x0 = x - half, x1 = x + half;
      final o = v * 2;
      pos
        ..[o] = x0
        ..[o + 1] = y0
        ..[o + 2] = x1
        ..[o + 3] = y0
        ..[o + 4] = x1
        ..[o + 5] = y1
        ..[o + 6] = x0
        ..[o + 7] = y1;
      idx
        ..[i] = v
        ..[i + 1] = v + 1
        ..[i + 2] = v + 2
        ..[i + 3] = v
        ..[i + 4] = v + 2
        ..[i + 5] = v + 3;
      v += 4;
      i += 6;
    }
    if (v == 0) return null;
    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(pos, 0, v * 2),
      indices: Uint16List.sublistView(idx, 0, i),
    );
  }

  void _drawEvents(
    Canvas canvas,
    PlotGeometry geo,
    List<int> lanes,
    double t0,
    double t1,
  ) {
    final e = c.events();
    if (e.length == 0) return;
    final peaks = c.eventPeaks(e);
    final times = e.times;
    // First sample in the window, minus one to carry the level at t0.
    var lo = 0, hi = times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (times[mid] < t0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i0 = math.max(0, lo - 1);
    var i1 = i0;
    while (i1 < times.length && times[i1] <= t1) {
      i1++;
    }
    final end = c.live ? math.min(t1, c.source.end) : t1;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.lineWidth
      ..isAntiAlias = style.antialias;
    if (e.markers) {
      _drawMarkers(canvas, geo, lanes, e, i0, i1, t0, t1, paint);
      return;
    }
    final words = c.words();
    for (var lane = 0; lane < lanes.length; lane++) {
      final ch = lanes[lane];
      if (ch >= e.channels.length) continue;
      final values = e.channels[ch];
      final centre = geo.laneCentre(lane);
      final k = geo.unit * eventHeight / peaks[ch];
      final baseY = centre + geo.unit * eventHeight / 2;
      final pts = Float32List((i1 - i0 + 1) * 4);
      var len = 0;
      for (var i = i0; i < i1; i++) {
        final x = geo.x(math.max(times[i], t0), t0, t1);
        final nextT = i + 1 < i1 ? times[i + 1] : end;
        final x2 = geo.x(math.min(nextT, t1), t0, t1);
        final y = baseY - values[i] * k;
        pts[len++] = x;
        pts[len++] = y;
        pts[len++] = x2;
        pts[len++] = y;
      }
      paint.color = c.laneColor(ch, dark: style.dark);
      if (len > 2) {
        canvas.drawRawPoints(
          ui.PointMode.polygon,
          Float32List.sublistView(pts, 0, len),
          paint,
        );
      }
      if (ch < words.length) {
        var shown = 0;
        for (final w in words[ch]) {
          if (w.t < t0 || w.t > t1) continue;
          if (++shown > 300) break;
          final tp = _text(w.text, paint.color, size: 11);
          tp.paint(
            canvas,
            Offset(geo.x(w.t, t0, t1) + 2, centre - geo.unit * 0.5),
          );
        }
      }
    }
  }

  /// String samples (LSL markers): a tick across the lane at each, with its
  /// text.
  void _drawMarkers(
    Canvas canvas,
    PlotGeometry geo,
    List<int> lanes,
    EventSamples e,
    int i0,
    int i1,
    double t0,
    double t1,
    Paint paint,
  ) {
    final times = e.times;
    final text = e.text;
    for (var lane = 0; lane < lanes.length; lane++) {
      final ch = lanes[lane];
      if (ch >= e.channels.length) continue;
      final centre = geo.laneCentre(lane);
      final half = geo.unit * eventHeight / 2;
      paint.color = c.laneColor(ch, dark: style.dark);
      final pts = Float32List((i1 - i0) * 4);
      var len = 0;
      for (var i = i0; i < i1; i++) {
        if (times[i] < t0) continue;
        final x = geo.x(times[i], t0, t1);
        pts[len++] = x;
        pts[len++] = centre - half;
        pts[len++] = x;
        pts[len++] = centre + half;
      }
      if (len > 0) {
        canvas.drawRawPoints(
          ui.PointMode.lines,
          Float32List.sublistView(pts, 0, len),
          paint,
        );
      }
      if (text == null || ch >= text.length) continue;
      // Labels only where there is room for them.
      final labels = text[ch];
      var shown = 0;
      var nextX = double.negativeInfinity;
      for (var i = i0; i < i1 && shown < 300; i++) {
        if (times[i] < t0 || i >= labels.length || labels[i].isEmpty) continue;
        final x = geo.x(times[i], t0, t1) + 2;
        if (x < nextX) continue;
        final tp = _text(labels[i], paint.color, size: 11);
        tp.paint(canvas, Offset(x, centre - half));
        nextX = x + tp.width + 4;
        shown++;
      }
    }
  }

  void _drawScaleBar(
    Canvas canvas,
    PlotGeometry geo,
    StreamInfo info,
    ViewSettings s,
  ) {
    final scale = c.sharedScale;
    if (scale == null || info.kind == Kind.event || info.irregular) return;
    if (c.lanes.isEmpty && !c.meanMode) return;
    final plot = geo.plot;
    final x = plot.right - plot.width * 0.01 - 2;
    final y0 = geo.laneCentre(0) - geo.unit / 2;
    final paint = Paint()
      ..color = style.foreground
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, y0), Offset(x, y0 + geo.unit), paint);
    canvas.drawLine(Offset(x - 4, y0), Offset(x + 4, y0), paint);
    canvas.drawLine(
      Offset(x - 4, y0 + geo.unit),
      Offset(x + 4, y0 + geo.unit),
      paint,
    );
    final unit = prettyUnit(info.unit());
    final tp = _text(
      '${formatNumber(scale)} $unit'.trim(),
      style.foreground,
      size: 10,
    );
    final r = Rect.fromLTWH(
      x - tp.width - 10,
      y0 + geo.unit / 2 - tp.height / 2 - 1,
      tp.width + 4,
      tp.height + 2,
    );
    canvas.drawRect(
      r,
      Paint()..color = style.background.withValues(alpha: 0.7),
    );
    tp.paint(canvas, r.topLeft + const Offset(2, 1));
  }

  void _drawColourBar(Canvas canvas, PlotGeometry geo) {
    final (lo, hi) = c.powerLevels!;
    final plot = geo.plot;
    final bar = Rect.fromLTWH(
      plot.right + 10,
      plot.top + 20,
      12,
      math.max(20, plot.height - 60),
    );
    const stops = 32;
    for (var i = 0; i < stops; i++) {
      final y = bar.bottom - (i + 1) * bar.height / stops;
      canvas.drawRect(
        Rect.fromLTWH(bar.left, y, bar.width, bar.height / stops + 0.5),
        Paint()..color = viridis(i / (stops - 1)),
      );
    }
    String fmt(double v) => v.abs() >= 100 || v == 0
        ? v.toStringAsFixed(0)
        : v.toStringAsPrecision(2);
    final top = _text(fmt(hi), style.foreground, size: 10);
    top.paint(canvas, Offset(bar.right + 3, bar.top - 2));
    final bottom = _text(fmt(lo), style.foreground, size: 10);
    bottom.paint(canvas, Offset(bar.right + 3, bar.bottom - bottom.height + 2));
    final unit = prettyUnit(c.info.unit());
    final label = _text(
      '${metricLabel(c.settings.powerMetric).split(' ').first} $unit',
      style.foreground,
      size: 10,
    );
    label.paint(canvas, Offset(bar.left - 4, plot.top + 2));
  }

  @override
  bool shouldRepaint(TracePainter old) => old.c != c || old.style != style;
}
