import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timing_core/timing_core.dart';

/// Shows [report]: each run's senders and receivers as a table, and the
/// latency distribution of the row that is selected.
void showReport(BuildContext context, Report report) => showDialog<void>(
  context: context,
  builder: (_) => Dialog.fullscreen(child: _ReportPage(report)),
);

class _ReportPage extends StatelessWidget {
  const _ReportPage(this.report);

  final Report report;

  Future<void> _copy(BuildContext context, String what, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied the report as $what')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Timing report'),
      leading: const CloseButton(),
      actions: [
        TextButton(
          onPressed: () => _copy(context, 'text', formatReport(report)),
          child: const Text('Copy text'),
        ),
        TextButton(
          onPressed: () => _copy(
            context,
            'JSON',
            const JsonEncoder.withIndent('  ').convert(report.toJson()),
          ),
          child: const Text('Copy JSON'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final run in report.runs) _RunCard(run)],
    ),
  );
}

String _ms(double? seconds) =>
    seconds == null ? '–' : (seconds * 1e3).toStringAsFixed(3);

class _RunCard extends StatefulWidget {
  const _RunCard(this.run);

  final RunReport run;

  @override
  State<_RunCard> createState() => _RunCardState();
}

class _RunCardState extends State<_RunCard> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final first = run.devices.first;
    final text = Theme.of(context).textTheme;
    final pair = run.pairs.isEmpty ? null : run.pairs[_selected];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Run ${run.runId}', style: text.titleMedium),
            Text(
              '${first.test} over ${first.backend} · ${first.sampleRate} Hz · '
              '${run.devices.map((d) => d.deviceName).join(', ')}',
              style: text.bodySmall,
            ),
            for (final sender in run.senders)
              Text(
                '${sender.device} sent ${sender.sent}'
                '${sender.sendMode == null ? '' : ' (${sender.sendMode})'} at '
                '${sender.achievedRate.toStringAsFixed(2)} Hz, interval sd '
                '${_ms(sender.sendInterval?.sd)} ms',
                style: text.bodySmall,
              ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('From → to')),
                  DataColumn(label: Text('Receive')),
                  DataColumn(label: Text('Received'), numeric: true),
                  DataColumn(label: Text('Lost %'), numeric: true),
                  DataColumn(label: Text('p50 ms'), numeric: true),
                  DataColumn(label: Text('p95 ms'), numeric: true),
                  DataColumn(label: Text('p99 ms'), numeric: true),
                  DataColumn(label: Text('max ms'), numeric: true),
                  DataColumn(label: Text('sd ms'), numeric: true),
                  DataColumn(
                    label: Text('± ms'),
                    numeric: true,
                    tooltip: 'How well the clock offset is known (median)',
                  ),
                  DataColumn(
                    label: Text('Poll adds ms'),
                    numeric: true,
                    tooltip: 'Mean delay from polling: half the interval',
                  ),
                  DataColumn(label: Text('Drift ppm'), numeric: true),
                ],
                rows: [
                  for (final (index, p) in run.pairs.indexed)
                    DataRow(
                      selected: index == _selected,
                      onSelectChanged: (_) => setState(() => _selected = index),
                      cells: [
                        DataCell(
                          Text(
                            '${p.from} → ${p.to}'
                            '${p.loopback ? ' (loopback)' : ''}',
                          ),
                        ),
                        DataCell(Text(p.receiveMode ?? '–')),
                        DataCell(
                          Text(
                            p.sent == null
                                ? '${p.received}'
                                : '${p.received} / ${p.sent}',
                          ),
                        ),
                        DataCell(Text((p.lossRate * 100).toStringAsFixed(3))),
                        DataCell(Text(_ms(p.latency?.p50))),
                        DataCell(Text(_ms(p.latency?.p95))),
                        DataCell(Text(_ms(p.latency?.p99))),
                        DataCell(Text(_ms(p.latency?.max))),
                        DataCell(Text(_ms(p.latency?.sd))),
                        DataCell(
                          Text(
                            _ms(
                              p.uncertainty == null
                                  ? null
                                  : p.uncertainty!.p50 / 2,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _ms(
                              p.pollInterval == null
                                  ? null
                                  : p.pollInterval! / 2,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(p.clock?.driftPpm?.toStringAsFixed(2) ?? '–'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (pair != null) ...[
              const SizedBox(height: 16),
              Text(
                'Latency, ${pair.from} → ${pair.to}',
                style: text.titleSmall,
              ),
              _Histogram(
                key: ValueKey(_selected),
                values: [
                  for (final v in pair.series.latency)
                    if (v.isFinite) v * 1e3,
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The distribution of [values] (ms) up to their 99th percentile; the rest
/// are counted in a line of text, so a few outliers do not flatten the
/// shape of everything else.
class _Histogram extends StatefulWidget {
  const _Histogram({super.key, required this.values});

  final List<double> values;

  @override
  State<_Histogram> createState() => _HistogramState();
}

class _HistogramState extends State<_Histogram> {
  static const _bins = 60;

  late final double _low;
  late final double _high;
  late final double _median;
  late final List<int> _counts = List.filled(_bins, 0);
  int _above = 0;
  int? _hover;

  @override
  void initState() {
    super.initState();
    final sorted = [...widget.values]..sort();
    if (sorted.isEmpty) {
      _low = _high = _median = 0;
      return;
    }
    _low = sorted.first;
    final p99 = sorted[((sorted.length - 1) * 0.99).round()];
    _high = p99 > _low ? p99 : _low + 1e-6;
    _median = sorted[(sorted.length - 1) ~/ 2];
    for (final v in sorted) {
      if (v > _high) {
        _above++;
      } else {
        _counts[math.min(_bins - 1, ((v - _low) / _width).floor())]++;
      }
    }
  }

  double get _width => (_high - _low) / _bins;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall;
    if (widget.values.isEmpty) {
      return Text('No timed samples (no clock offset was known).', style: text);
    }
    final hover = _hover;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => MouseRegion(
            onHover: (event) => setState(
              () => _hover =
                  (event.localPosition.dx / constraints.maxWidth * _bins)
                      .floor()
                      .clamp(0, _bins - 1),
            ),
            onExit: (_) => setState(() => _hover = null),
            child: CustomPaint(
              size: Size(constraints.maxWidth, 180),
              painter: _HistogramPainter(
                counts: _counts,
                hover: hover,
                median: (_median - _low) / (_high - _low),
                low: _low,
                high: _high,
                scheme: Theme.of(context).colorScheme,
                textStyle: text!,
              ),
            ),
          ),
        ),
        Text(
          hover == null
              ? 'Median ${_median.toStringAsFixed(3)} ms · '
                    '$_above of ${widget.values.length} above '
                    '${_high.toStringAsFixed(3)} ms (the 99th percentile) '
                    'not shown'
              : '${(_low + hover * _width).toStringAsFixed(3)} to '
                    '${(_low + (hover + 1) * _width).toStringAsFixed(3)} ms: '
                    '${_counts[hover]} samples',
          style: text,
        ),
      ],
    );
  }
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter({
    required this.counts,
    required this.hover,
    required this.median,
    required this.low,
    required this.high,
    required this.scheme,
    required this.textStyle,
  });

  final List<int> counts;
  final int? hover;

  /// Where the median is between [low] and [high], 0 to 1.
  final double median;
  final double low;
  final double high;
  final ColorScheme scheme;
  final TextStyle textStyle;

  void _label(Canvas canvas, String label, Offset at, {double align = 0}) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: textStyle.copyWith(color: scheme.onSurfaceVariant),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawText(painter, at - Offset(painter.width * align, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const axis = 20.0;
    final plot = size.height - axis;
    final peak = counts.reduce(math.max);
    final step = size.width / counts.length;
    final gap = step > 6 ? 2.0 : 0.0;
    final radius = Radius.circular(math.min(4, (step - gap) / 2));

    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final height = math.max(1.0, counts[i] / peak * (plot - 8));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(i * step + gap / 2, plot - height, step - gap, height),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()
          ..color = i == hover
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0.7),
      );
    }

    final muted = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, plot), Offset(size.width, plot), muted);
    final x = median.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, plot),
      Paint()
        ..color = scheme.onSurfaceVariant
        ..strokeWidth = 1,
    );
    _label(canvas, 'median', Offset(x + 4, 0));
    _label(canvas, '${low.toStringAsFixed(3)} ms', Offset(0, plot + 4));
    _label(
      canvas,
      '${high.toStringAsFixed(3)} ms',
      Offset(size.width, plot + 4),
      align: 1,
    );
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.hover != hover || old.counts != counts || old.scheme != scheme;
}

extension on Canvas {
  void drawText(TextPainter painter, Offset at) => painter.paint(this, at);
}
