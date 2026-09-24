import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:signal_core/signal_core.dart';

import '../../model/stream_info.dart';
import '../../model/view_settings.dart';
import '../stream_controller.dart';
import 'trace_painter.dart';

/// The trace plot of one tab, with mouse, trackpad and touch navigation:
///
/// - wheel: amplitude scale (1-2-5 steps)
/// - Ctrl + wheel, pinch: time window
/// - Shift + wheel, sideways scroll, drag: scroll through time
/// - tap a channel's label: exclude it (bad channel) or include it again
/// - right-click or long-press a trace: hide, exclude, reference to it,
///   name it
class StreamPlot extends StatefulWidget {
  final StreamController controller;
  final PlotStyle style;

  /// Ask for a name for channel [channel] (e.g. its cap position).
  final void Function(int channel)? onRename;

  const StreamPlot({
    super.key,
    required this.controller,
    required this.style,
    this.onRename,
  });

  @override
  State<StreamPlot> createState() => _StreamPlotState();
}

class _StreamPlotState extends State<StreamPlot> {
  double _startT0 = 0;
  double _startWindow = 1;
  double _startFocusX = 0;
  Size _size = Size.zero;

  StreamController get c => widget.controller;

  PlotGeometry get _geo => PlotGeometry(
    _size,
    c.meanMode ? 1 : c.lanes.length,
    colourBar: c.powerActive && c.powerLevels != null,
  );

  double _timeAt(double x) => _geo.time(x, c.t0, c.t1);

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    final dx = e.scrollDelta.dx, dy = e.scrollDelta.dy;
    if (keys.isControlPressed || keys.isMetaPressed) {
      if (dy != 0) {
        c.zoom(dy > 0 ? 1.25 : 0.8, _timeAt(e.localPosition.dx));
      }
    } else if (keys.isShiftPressed || dx.abs() > dy.abs()) {
      final d = dx.abs() > dy.abs() ? dx : dy;
      c.scrollBy(d.sign * 0.1);
    } else if (dy != 0) {
      c.stepAmplitude(dy < 0 ? -1 : 1);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startT0 = c.t0;
    _startWindow = c.windowS;
    _startFocusX = d.localFocalPoint.dx;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final plotW = _geo.plot.width;
    if (plotW <= 0) return;
    if (d.pointerCount > 1 || d.horizontalScale != 1) {
      // Pinch: zoom around the starting focal point.
      final scale = d.horizontalScale == 1 ? d.scale : d.horizontalScale;
      if (scale <= 0) return;
      final anchorF = (_startFocusX - _geo.plot.left) / plotW;
      final anchor = _startT0 + anchorF * _startWindow;
      final w = _startWindow / scale;
      c.setWindow(w);
      c.scrollTo(
        anchor -
            anchorF * c.windowS -
            (d.localFocalPoint.dx - _startFocusX) / plotW * c.windowS,
      );
    } else {
      final dt = -(d.localFocalPoint.dx - _startFocusX) / plotW * _startWindow;
      c.scrollTo(_startT0 + dt);
    }
  }

  /// A tap on a channel's label excludes it (or includes it again).
  void _labelTap(Offset local) {
    if (c.meanMode || !c.info.badChannels) return;
    if (local.dx > PlotGeometry.leftAxis) return;
    final lane = _geo.laneAt(local.dy);
    if (lane == null) return;
    c.toggleExcluded(c.lanes[lane]);
  }

  Future<void> _laneMenu(Offset local, Offset global) async {
    if (c.meanMode) return;
    final lane = _geo.laneAt(local.dy);
    if (lane == null) return;
    final ch = c.lanes[lane];
    final info = c.info;
    final s = c.settings;
    final label = info.labels[ch];
    final bad = s.bad.contains(ch);
    final isEvent = info.kind == Kind.event || info.irregular;
    final decoded = s.decoded.contains(ch);
    final q = c.qualityOf(ch);
    final refs = s.refMode == RefMode.subset ? s.refChannels : const <int>{};
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        global.dx,
        global.dy,
      ),
      items: [
        if (q.flag != ChannelFlag.ok)
          PopupMenuItem(enabled: false, child: Text('$label: ${q.reason}')),
        PopupMenuItem(value: 'hide', child: Text('Hide $label')),
        if (widget.onRename != null)
          PopupMenuItem(value: 'rename', child: Text('Name $label…')),
        if (info.badChannels)
          PopupMenuItem(
            value: 'bad',
            child: Text(
              bad ? 'Include $label again' : 'Exclude $label (bad channel)',
            ),
          ),
        if (info.canReference) ...[
          PopupMenuItem(value: 'ref', child: Text('Reference to $label')),
          PopupMenuItem(
            value: 'refset',
            child: Text(
              refs.contains(ch)
                  ? 'Remove $label from reference set'
                  : 'Add $label to reference set',
            ),
          ),
        ],
        if (isEvent)
          PopupMenuItem(
            value: 'decode',
            child: Text(
              decoded ? 'Stop decoding $label' : 'Decode $label as triggers',
            ),
          ),
      ],
    );
    switch (choice) {
      case 'hide':
        c.update(s.copyWith(hidden: {...s.hidden, ch}));
      case 'rename':
        widget.onRename?.call(ch);
      case 'bad':
        c.toggleExcluded(ch);
      case 'ref':
        c.useAsReference(ch);
      case 'refset':
        c.toggleInReferenceSet(ch);
      case 'decode':
        c.update(
          s.copyWith(
            decoded: decoded
                ? ({...s.decoded}..remove(ch))
                : {...s.decoded, ch},
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final width = _geo.plot.width;
        // Up to 1.5 points per logical pixel: sharper gains little and
        // costs a lot on high-density phone screens.
        final bins = math.max(16, (width * math.min(dpr, 1.5)).round());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) c.setBins(bins);
        });
        return Listener(
          onPointerSignal: _onSignal,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onTapUp: (d) => _labelTap(d.localPosition),
            onSecondaryTapUp: (d) =>
                _laneMenu(d.localPosition, d.globalPosition),
            onLongPressStart: (d) =>
                _laneMenu(d.localPosition, d.globalPosition),
            child: RepaintBoundary(
              child: CustomPaint(
                size: _size,
                painter: TracePainter(c, widget.style),
              ),
            ),
          ),
        );
      },
    );
  }
}
