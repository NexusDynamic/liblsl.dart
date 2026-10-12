import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timing_core/timing_core.dart';

/// What the report can do about the logs behind it.
class ReportActions {
  const ReportActions({
    required this.hasTrace,
    required this.openTrace,
    required this.closeRuns,
  });

  /// Whether the receiving device's log of [pair] is open and has samples.
  final bool Function(RunReport run, PairReport pair) hasTrace;

  /// Shows the tab with [pair]'s latency over the run.
  final void Function(RunReport run, PairReport pair) openTrace;

  /// Closes the logs of the runs with these ids, or of every run with
  /// null, and gives the report of what is left: null if nothing is.
  final Future<Report?> Function(Set<String>? runIds) closeRuns;
}

/// Shows [report] once it is there: every sender and receiver of every run
/// in one table, which can be narrowed down, and below it the run and the
/// latency distribution of the row that is selected.
void showReport(
  BuildContext context,
  Future<Report> report, {
  ReportActions? actions,
}) => showDialog<void>(
  context: context,
  builder: (_) => Dialog.fullscreen(child: _ReportPage(report, actions)),
);

class _ReportPage extends StatefulWidget {
  const _ReportPage(this.report, this.actions);

  final Future<Report> report;
  final ReportActions? actions;

  @override
  State<_ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<_ReportPage> {
  late Future<Report> _report = widget.report;

  Future<void> _copy(String what, String Function(Report) text) async {
    final report = await _report;
    await Clipboard.setData(ClipboardData(text: text(report)));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied the report as $what')));
  }

  /// Logs are being closed and what is left analysed again.
  bool _closing = false;

  Future<void> _close(Set<String>? runIds) async {
    setState(() => _closing = true);
    final left = await widget.actions!.closeRuns(runIds);
    if (!mounted) return;
    if (left == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _report = Future.value(left);
        _closing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Timing report'),
      leading: const CloseButton(),
      actions: [
        if (widget.actions != null)
          TextButton(
            onPressed: () => _close(null),
            child: const Text('Close all logs'),
          ),
        TextButton(
          onPressed: () => _copy('text', formatReport),
          child: const Text('Copy text'),
        ),
        TextButton(
          onPressed: () => _copy(
            'JSON',
            (r) => const JsonEncoder.withIndent('  ').convert(r.toJson()),
          ),
          child: const Text('Copy JSON'),
        ),
      ],
    ),
    bottomNavigationBar: _closing ? const LinearProgressIndicator() : null,
    body: FutureBuilder<Report>(
      // A new report (logs were closed) starts from a clean state.
      key: ObjectKey(_report),
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('The logs could not be analysed: ${snapshot.error}'),
          );
        }
        final report = snapshot.data;
        if (report == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analysing the logs…'),
              ],
            ),
          );
        }
        return _ReportBody(
          report,
          widget.actions,
          onCloseRun: widget.actions == null ? null : (id) => _close({id}),
          onOpened: () => Navigator.of(context).pop(),
        );
      },
    ),
  );
}

String _ms(double? seconds) =>
    seconds == null ? '–' : (seconds * 1e3).toStringAsFixed(3);

/// A percentile of [s], or a dash when it has too few values for one.
String _percentile(Summary? s, double q, double Function(Summary) value) =>
    s == null || !s.reliable(q) ? '–' : _ms(value(s));

/// A row of the table: one sender and receiver of one run.
class _Row {
  _Row(this.run, this.pair);

  final RunReport run;
  final PairReport pair;

  RunHeader get _receiver => run.devices.firstWhere(
    (d) => d.deviceName == pair.to,
    orElse: () => run.devices.first,
  );

  String get direction => '${pair.from} → ${pair.to}';

  /// How the sender sent, by its own log where that is open.
  String? get sendMode => run.devices
      .firstWhere(
        (d) => d.sourceId == pair.sourceId,
        orElse: () => run.devices.first,
      )
      .sendMode;

  String? get receiveMode => pair.receiveMode;
  int? get repetition => _receiver.extra['repetition'] as int?;
}

/// One condition between two devices, across the runs that repeat it.
///
/// A run's median says how that run went. How far the medians of repeated
/// runs lie apart says how much of that is the condition and how much the
/// moment, which no single run can.
class _Repeated {
  _Repeated(this.condition, this.pair);

  final String condition;
  final String pair;

  /// Each run's median latency, in seconds.
  final List<double> medians = [];

  static List<_Repeated> of(Iterable<_Row> rows) {
    final byKey = <String, _Repeated>{};
    for (final row in rows) {
      final p = row.pair;
      final first = row.run.devices.first;
      final latency = p.latencyFitted ?? p.latency;
      if (latency == null) continue;
      final condition = [
        '${first.test} over ${first.backend}',
        '${first.sampleRate} Hz x ${first.channels} ch',
        if (row.sendMode != null) 'send ${row.sendMode}',
        if (p.receiveMode != null) 'receive ${p.receiveMode}',
        if (p.pollInterval != null) 'every ${_ms(p.pollInterval)} ms',
      ].join(' · ');
      (byKey['$condition\n${row.direction}'] ??= _Repeated(
        condition,
        row.direction,
      )).medians.add(latency.p50);
    }
    return [
      for (final r in byKey.values)
        if (r.medians.length > 1) r..medians.sort(),
    ];
  }

  double get median {
    final n = medians.length;
    return n.isOdd
        ? medians[n ~/ 2]
        : (medians[n ~/ 2 - 1] + medians[n ~/ 2]) / 2;
  }
}

class _RepeatedCard extends StatelessWidget {
  const _RepeatedCard(this.repeated);

  final List<_Repeated> repeated;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repeated runs', style: text.titleMedium),
            Text(
              'The median latency of each run of the same condition. Two '
              'conditions differ by more than chance only if their ranges '
              'here stand apart.',
              style: text.bodySmall,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Condition')),
                  DataColumn(label: Text('From → to')),
                  DataColumn(label: Text('Runs'), numeric: true),
                  DataColumn(label: Text('Median p50 ms'), numeric: true),
                  DataColumn(label: Text('Lowest'), numeric: true),
                  DataColumn(label: Text('Highest'), numeric: true),
                ],
                rows: [
                  for (final r in repeated)
                    DataRow(
                      cells: [
                        DataCell(Text(r.condition)),
                        DataCell(Text(r.pair)),
                        DataCell(Text('${r.medians.length}')),
                        DataCell(Text(_ms(r.median))),
                        DataCell(Text(_ms(r.medians.first))),
                        DataCell(Text(_ms(r.medians.last))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatefulWidget {
  const _ReportBody(
    this.report,
    this.actions, {
    required this.onCloseRun,
    required this.onOpened,
  });

  final Report report;
  final ReportActions? actions;
  final ValueChanged<String>? onCloseRun;

  /// A trace was opened: it is behind the report.
  final VoidCallback onOpened;

  @override
  State<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<_ReportBody> {
  late final List<_Row> _all = [
    for (final run in widget.report.runs)
      for (final pair in run.pairs) _Row(run, pair),
  ];

  /// What is shown of each kind; nothing chosen is everything.
  final Set<String> _directions = {};
  final Set<String> _receive = {};
  final Set<String> _send = {};
  bool _loopback = true;

  _Row? _selected;

  /// Latency with the offset read from the line through the run's
  /// estimates, rather than from whichever estimate was the latest: without
  /// the steps between estimates, which are no part of the transport.
  bool _fitted = true;

  Summary? _latency(PairReport p) =>
      _fitted ? p.latencyFitted ?? p.latency : p.latency;

  bool _passes(_Row row) =>
      (_loopback || !row.pair.loopback) &&
      (_directions.isEmpty || _directions.contains(row.direction)) &&
      (_receive.isEmpty || _receive.contains(row.receiveMode)) &&
      (_send.isEmpty || _send.contains(row.sendMode));

  Widget _filter(String label, Set<String> chosen, Iterable<String?> values) {
    final options = {...values.nonNulls}.toList()..sort();
    if (options.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 72, child: Text(label)),
          for (final option in options)
            FilterChip(
              label: Text(option),
              visualDensity: VisualDensity.compact,
              selected: chosen.contains(option),
              onSelected: (on) => setState(
                () => on ? chosen.add(option) : chosen.remove(option),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final rows = _all.where(_passes).toList();
    final selected = rows.contains(_selected) ? _selected : rows.firstOrNull;
    final repeated = _Repeated.of(rows);
    final several = widget.report.runs.length > 1;
    final warned = [
      for (final run in widget.report.runs)
        if (run.warnings.isNotEmpty) run,
    ];
    final actions = widget.actions;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final run in warned)
          for (final warning in run.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      several ? 'Run ${run.runId}: $warning' : warning,
                      style: text.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        if (warned.isNotEmpty) const SizedBox(height: 8),
        _filter('Direction', _directions, _all.map((r) => r.direction)),
        _filter('Receive', _receive, _all.map((r) => r.receiveMode)),
        _filter('Send', _send, _all.map((r) => r.sendMode)),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_all.any((r) => r.pair.loopback))
              FilterChip(
                label: const Text('A device\'s own samples'),
                visualDensity: VisualDensity.compact,
                selected: _loopback,
                onSelected: (on) => setState(() => _loopback = on),
              ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Fitted clock offset'),
                  tooltip:
                      'The offset from a line through all of the run\'s '
                      'estimates',
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Latest estimate'),
                  tooltip:
                      'The offset as it was known when each sample arrived; '
                      'it steps with every new estimate',
                ),
              ],
              selected: {_fitted},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _fitted = v.single),
            ),
            Text(
              '${rows.length} of ${_all.length} rows',
              style: text.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (repeated.isNotEmpty) _RepeatedCard(repeated),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: [
              if (actions != null) const DataColumn(label: Text('')),
              const DataColumn(label: Text('Run')),
              const DataColumn(label: Text('Rep'), numeric: true),
              const DataColumn(label: Text('Send')),
              const DataColumn(label: Text('Receive')),
              const DataColumn(label: Text('From → to')),
              const DataColumn(label: Text('Received'), numeric: true),
              const DataColumn(
                label: Text('Lost %'),
                numeric: true,
                tooltip:
                    'Of the samples sent between the first and the last '
                    'received; those before or after are in brackets, '
                    'and say how the run started and stopped',
              ),
              const DataColumn(label: Text('p50 ms'), numeric: true),
              const DataColumn(
                label: Text('± ms'),
                numeric: true,
                tooltip:
                    'How well the clock offset is known (median). Every '
                    'latency in the row may be out by this, together',
              ),
              const DataColumn(label: Text('p95 ms'), numeric: true),
              const DataColumn(label: Text('p99 ms'), numeric: true),
              const DataColumn(label: Text('max ms'), numeric: true),
              const DataColumn(
                label: Text('MAD ms'),
                numeric: true,
                tooltip:
                    'Median distance from the median: the spread, '
                    'whatever the few slowest samples did',
              ),
              const DataColumn(label: Text('sd ms'), numeric: true),
              const DataColumn(
                label: Text('Poll adds ms'),
                numeric: true,
                tooltip: 'Mean delay from polling: half the interval',
              ),
              const DataColumn(label: Text('Drift ppm'), numeric: true),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  selected: row == selected,
                  onSelectChanged: (_) => setState(() => _selected = row),
                  cells: [
                    if (actions != null)
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.show_chart, size: 18),
                          visualDensity: VisualDensity.compact,
                          tooltip: actions.hasTrace(row.run, row.pair)
                              ? 'Open the latency of this pair over the run'
                              : 'No samples to show',
                          onPressed: actions.hasTrace(row.run, row.pair)
                              ? () {
                                  actions.openTrace(row.run, row.pair);
                                  widget.onOpened();
                                }
                              : null,
                        ),
                      ),
                    DataCell(Text(row.run.runId)),
                    DataCell(Text('${row.repetition ?? '–'}')),
                    DataCell(Text(row.sendMode ?? '–')),
                    DataCell(Text(row.receiveMode ?? '–')),
                    DataCell(
                      Text(
                        '${row.direction}'
                        '${row.pair.loopback ? ' (loopback)' : ''}',
                      ),
                    ),
                    DataCell(
                      Text(
                        row.pair.sent == null
                            ? '${row.pair.received}'
                            : '${row.pair.received} / ${row.pair.sent}',
                      ),
                    ),
                    DataCell(
                      Text(
                        (row.pair.interiorLossRate * 100).toStringAsFixed(3) +
                            (row.pair.lostEdges == null ||
                                    row.pair.lostEdges == 0
                                ? ''
                                : ' (+${row.pair.lostEdges})'),
                      ),
                    ),
                    DataCell(Text(_ms(_latency(row.pair)?.p50))),
                    DataCell(
                      Text(
                        _ms(
                          row.pair.uncertainty == null
                              ? null
                              : row.pair.uncertainty!.p50 / 2,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(_percentile(_latency(row.pair), 0.95, (s) => s.p95)),
                    ),
                    DataCell(
                      Text(_percentile(_latency(row.pair), 0.99, (s) => s.p99)),
                    ),
                    DataCell(Text(_ms(_latency(row.pair)?.max))),
                    DataCell(Text(_ms(_latency(row.pair)?.mad))),
                    DataCell(Text(_ms(_latency(row.pair)?.sd))),
                    DataCell(
                      Text(
                        _ms(
                          row.pair.pollInterval == null
                              ? null
                              : row.pair.pollInterval! / 2,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(row.pair.clock?.driftPpm?.toStringAsFixed(2) ?? '–'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (selected != null)
          _RunDetail(
            // The histogram is worked out once for what it is given.
            key: ValueKey((selected.run.runId, selected.direction, _fitted)),
            run: selected.run,
            pair: selected.pair,
            latency: _latency(selected.pair),
            fitted: _fitted && selected.pair.latencyFitted != null,
            onClose: widget.onCloseRun == null
                ? null
                : () => widget.onCloseRun!(selected.run.runId),
          ),
      ],
    );
  }
}

/// The run of the selected row, and the row's latency distribution.
class _RunDetail extends StatelessWidget {
  const _RunDetail({
    super.key,
    required this.run,
    required this.pair,
    required this.latency,
    required this.fitted,
    required this.onClose,
  });

  final RunReport run;
  final PairReport pair;
  final Summary? latency;
  final bool fitted;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final first = run.devices.first;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Run ${run.runId}', style: text.titleMedium),
                ),
                if (onClose != null)
                  TextButton(
                    onPressed: onClose,
                    child: const Text('Close this run\'s logs'),
                  ),
              ],
            ),
            Text(
              '${first.test} over ${first.backend} · ${first.sampleRate} Hz '
              'x ${first.channels} ch · '
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
            for (final s in run.symmetry)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${s.a} ↔ ${s.b}: ${_ms(s.latencyP50)} ms p50 averaged '
                  'over the two directions, which no clock offset enters; '
                  'the two offset estimates disagree by '
                  '${_ms(s.offsetInconsistency)} ms',
                  style: text.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            Text('Latency, ${pair.from} → ${pair.to}', style: text.titleSmall),
            _Histogram(
              summary: latency,
              values: [
                for (final v
                    in fitted ? pair.series.latencyFitted : pair.series.latency)
                  if (v.isFinite) v * 1e3,
              ],
            ),
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
  const _Histogram({required this.values, required this.summary});

  final List<double> values;

  /// Of [values], in seconds: the same figures as the table's.
  final Summary? summary;

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
    final summary = widget.summary;
    if (widget.values.isEmpty || summary == null) {
      _low = _high = _median = 0;
      return;
    }
    _low = summary.min * 1e3;
    final p99 = summary.p99 * 1e3;
    _high = p99 > _low ? p99 : _low + 1e-6;
    _median = summary.p50 * 1e3;
    for (final v in widget.values) {
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
    if (widget.values.isEmpty || widget.summary == null) {
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
