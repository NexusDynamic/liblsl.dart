import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:signal_core/signal_core.dart';

import '../stream_controller.dart';
import 'trace_painter.dart';

/// The whole recording at a glance: one row per lane, coloured by the
/// signal's peak-to-peak range in each column relative to that channel's
/// typical range (bright = unusually large, e.g. artefacts). The current
/// window is outlined; click or drag to move it.
class OverviewStrip extends StatelessWidget {
  final StreamController controller;
  final PlotStyle style;

  const OverviewStrip({
    super.key,
    required this.controller,
    required this.style,
  });

  void _moveTo(double x, double width) {
    final c = controller;
    final left = PlotGeometry.leftAxis;
    final w = width - left - 8;
    if (w <= 0) return;
    final f = ((x - left) / w).clamp(0.0, 1.0);
    final start = c.source.start, end = c.source.end;
    c.scrollTo(start + f * (end - start) - c.windowS / 2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) => _moveTo(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _moveTo(d.localPosition.dx, width),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: CustomPaint(
              size: Size(width, 40),
              painter: _OverviewPainter(controller, style),
            ),
          ),
        );
      },
    );
  }
}

class _OverviewPainter extends CustomPainter {
  final StreamController c;
  final PlotStyle style;

  _OverviewPainter(this.c, this.style) : super(repaint: c.repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      PlotGeometry.leftAxis,
      4,
      size.width - 8,
      size.height - 4,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = style.background);
    canvas.drawRect(
      r,
      Paint()..color = style.foreground.withValues(alpha: 0.05),
    );
    final start = c.source.start;
    final end = math.max(start + 1e-6, c.source.end);
    double x(double t) => r.left + (t - start) / (end - start) * r.width;

    final env = c.overview;
    final lanes = c.lanes;
    final activity = c.activity;
    if (env != null && !env.samples && lanes.isNotEmpty && activity != null) {
      _paintActivity(canvas, r, env, activity, lanes, x);
    } else if (c.info.irregular) {
      final e = c.events();
      final tick = Paint()
        ..color = style.foreground.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      // One call for all ticks: there can be tens of thousands.
      final pts = Float32List(e.length * 4);
      for (var i = 0; i < e.length; i++) {
        final xi = x(e.times[i]);
        pts
          ..[i * 4] = xi
          ..[i * 4 + 1] = r.top
          ..[i * 4 + 2] = xi
          ..[i * 4 + 3] = r.bottom;
      }
      canvas.drawRawPoints(ui.PointMode.lines, pts, tick);
    }

    // The window.
    final w = Rect.fromLTRB(
      x(c.t0).clamp(r.left, r.right),
      r.top - 2,
      math.max(x(c.t1).clamp(r.left, r.right), x(c.t0) + 2),
      r.bottom + 2,
    );
    canvas.drawRect(
      w,
      Paint()..color = style.foreground.withValues(alpha: 0.12),
    );
    canvas.drawRect(
      w,
      Paint()
        ..color = style.foreground.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final label = TracePainter.plotText(
      'overview',
      style.foreground.withValues(alpha: 0.6),
      size: 10,
      fontFamily: style.fontFamily,
    );
    label.paint(
      canvas,
      Offset(r.left - label.width - 8, r.center.dy - label.height / 2),
    );
  }

  /// The rows of [activity] (see [StreamController.activity]) for the
  /// shown lanes, stretched over the overview's time span.
  void _paintActivity(
    Canvas canvas,
    Rect r,
    Envelope env,
    ui.Image activity,
    List<int> lanes,
    double Function(double) x,
  ) {
    final rowH = r.height / lanes.length;
    final x0 = x(env.start);
    final x1 = x(env.start + env.length * env.step);
    final paint = Paint()..filterQuality = FilterQuality.none;
    final width = activity.width.toDouble();
    for (var row = 0; row < lanes.length; row++) {
      final ch = lanes[row];
      if (ch >= activity.height) continue;
      final y = r.top + row * rowH;
      canvas.drawImageRect(
        activity,
        Rect.fromLTWH(0, ch.toDouble(), width, 1),
        Rect.fromLTRB(x0, y, x1, y + rowH + 0.3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OverviewPainter old) => old.c != c || old.style != style;
}
