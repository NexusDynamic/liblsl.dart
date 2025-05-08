import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

class ClockSyncReportPage extends StatefulWidget {
  final TimingManager timingManager;
  final String testName;

  const ClockSyncReportPage({
    super.key,
    required this.timingManager,
    required this.testName,
  });

  @override
  State<ClockSyncReportPage> createState() => _ClockSyncReportPageState();
}

class _ClockSyncReportPageState extends State<ClockSyncReportPage> {
  final ScrollController _scrollController = ScrollController();
  String _selectedDevice = '';
  Map<String, dynamic>? _selectedAnalysis;

  @override
  void initState() {
    super.initState();
    _processClockSyncData();
  }

  void _processClockSyncData() {
    // Find all clock sync analysis events
    final analysisEvents = widget.timingManager.events
        .where((e) => e.eventType == 'clock_sync_analysis')
        .toList();

    if (analysisEvents.isNotEmpty) {
      setState(() {
        _selectedDevice = analysisEvents.first.metadata?['deviceKey'] ?? '';
        _selectedAnalysis = analysisEvents.first.metadata;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Find all clock sync analysis events
    final analysisEvents = widget.timingManager.events
        .where((e) => e.eventType == 'clock_sync_analysis')
        .toList();

    // Get unique device keys
    final deviceKeys = analysisEvents
        .map((e) => e.metadata?['deviceKey'] as String? ?? '')
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.testName} Results'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text('Select Device: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: deviceKeys.contains(_selectedDevice)
                      ? _selectedDevice
                      : null,
                  hint: const Text('Select a device'),
                  items: deviceKeys.map((key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(key),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedDevice = value;
                        _selectedAnalysis = analysisEvents
                            .firstWhere(
                              (e) => e.metadata?['deviceKey'] == value,
                            )
                            .metadata;
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          // Analysis visualization
          Expanded(
            child: _selectedAnalysis != null
                ? _buildAnalysisView(_selectedAnalysis!)
                : const Center(child: Text('No analysis data available')),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSeriesChart(Map<String, dynamic> analysis) {
    // Extract time series data if available
    final measurements = analysis['measurements'] as int? ?? 0;
    if (measurements <= 1) {
      return const Center(child: Text('Insufficient data for time series'));
    }

    // Get raw measurements if available (could be stored in the analysis metadata)
    final timeSeriesEvents = widget.timingManager.events
        .where(
          (e) =>
              e.eventType == 'time_sync_measurement' &&
              (e.metadata?['streamName'] == _selectedDevice),
        )
        .toList();

    if (timeSeriesEvents.isEmpty) {
      return const Center(child: Text('No time series data available'));
    }

    // Extract data points
    final times = <double>[];
    final corrections = <double>[];
    final offsets = <double>[];

    // Starting time for relative timestamps
    final startTime = timeSeriesEvents.first.timestamp;

    for (final event in timeSeriesEvents) {
      // Use relative time from start of test
      times.add(event.timestamp - startTime);
      corrections.add(event.metadata?['timeCorrection'] ?? 0.0);
      offsets.add(event.metadata?['estimatedOffset'] ?? 0.0);
    }

    return SizedBox(
      height: 200,
      child: TimeSeriesChart(
        times: times,
        corrections: corrections,
        offsets: offsets,
      ),
    );
  }

  Widget _buildAnalysisView(Map<String, dynamic> analysis) {
    final lslDiffStats = analysis['lslTimeDiffStats'] as Map<String, dynamic>?;
    final localDiffStats =
        analysis['localTimeDiffStats'] as Map<String, dynamic>?;
    final offsetDiffStats =
        analysis['offsetDiffStats'] as Map<String, dynamic>?;
    final lslDriftRate = analysis['lslDriftRate'] as double?;
    final localDriftRate = analysis['localDriftRate'] as double?;
    final timeSpan = analysis['timeSpan'] as double?;
    final measurements = analysis['measurements'] as int? ?? 0;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clock Synchronization Summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Device: $_selectedDevice'),
                  Text('Measurements: $measurements'),
                  if (timeSpan != null)
                    Text('Time Span: ${_formatTime(timeSpan)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Clock drift visualization
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clock Drift Analysis',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (lslDriftRate != null)
                    _buildStatRow(
                      'LSL Time Drift Rate:',
                      '${(lslDriftRate * 1000000).toStringAsFixed(2)} μs/s',
                      lslDriftRate.abs() < 0.000001
                          ? Colors.green
                          : (lslDriftRate.abs() < 0.00001
                                ? Colors.orange
                                : Colors.red),
                    ),
                  if (localDriftRate != null)
                    _buildStatRow(
                      'System Time Drift Rate:',
                      '${(localDriftRate * 1000000).toStringAsFixed(2)} μs/s',
                      localDriftRate.abs() < 0.000001
                          ? Colors.green
                          : (localDriftRate.abs() < 0.00001
                                ? Colors.orange
                                : Colors.red),
                    ),
                  const SizedBox(height: 16),

                  // LSL time differences stats
                  if (lslDiffStats != null) ...[
                    Text(
                      'LSL Time Synchronization',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildStatsTable(lslDiffStats),
                  ],
                  const SizedBox(height: 16),

                  // Local time differences stats
                  if (localDiffStats != null) ...[
                    Text(
                      'System Time Synchronization',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildStatsTable(localDiffStats),
                  ],
                  const SizedBox(height: 16),

                  // System/LSL offset differences
                  if (offsetDiffStats != null) ...[
                    Text(
                      'System-to-LSL Offset Differences',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildStatsTable(offsetDiffStats),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Time Synchronization Over Time',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _buildTimeSeriesChart(analysis),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Interpretation guide
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interpretation Guide',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• LSL Time Drift Rate: Shows how fast the LSL clocks are drifting apart (μs/s)',
                  ),
                  const Text(
                    '• System Time Drift Rate: Shows how fast the system clocks are drifting apart (μs/s)',
                  ),
                  const Text('• Mean: Average time offset between devices'),
                  const Text(
                    '• StdDev: Standard deviation of offsets (lower is better)',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Good time synchronization has low drift rates (<1 μs/s) and low standard deviation (<1 ms)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTable(Map<String, dynamic> stats) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
      children: [
        TableRow(
          children: [
            const Padding(
              padding: EdgeInsets.all(4.0),
              child: Text('Statistic'),
            ),
            const Padding(padding: EdgeInsets.all(4.0), child: Text('Value')),
          ],
        ),
        TableRow(
          children: [
            const Padding(padding: EdgeInsets.all(4.0), child: Text('Mean')),
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(_formatTime(stats['mean'] ?? 0.0)),
            ),
          ],
        ),
        TableRow(
          children: [
            const Padding(padding: EdgeInsets.all(4.0), child: Text('Min')),
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(_formatTime(stats['min'] ?? 0.0)),
            ),
          ],
        ),
        TableRow(
          children: [
            const Padding(padding: EdgeInsets.all(4.0), child: Text('Max')),
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(_formatTime(stats['max'] ?? 0.0)),
            ),
          ],
        ),
        TableRow(
          children: [
            const Padding(padding: EdgeInsets.all(4.0), child: Text('StdDev')),
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(_formatTime(stats['stdDev'] ?? 0.0)),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(double timeInSeconds) {
    // Convert to milliseconds for display
    final ms = timeInSeconds * 1000;

    if (ms < 1) {
      // Show microseconds for very small values
      return '${(ms * 1000).toStringAsFixed(2)} μs';
    } else if (ms < 1000) {
      // Show milliseconds
      return '${ms.toStringAsFixed(2)} ms';
    } else {
      // Show seconds
      return '${(ms / 1000).toStringAsFixed(3)} s';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// Add this class for the chart
class TimeSeriesChart extends StatelessWidget {
  final List<double> times;
  final List<double> corrections;
  final List<double> offsets;

  const TimeSeriesChart({
    Key? key,
    required this.times,
    required this.corrections,
    required this.offsets,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: TimeSeriesChartPainter(
        times: times,
        corrections: corrections,
        offsets: offsets,
      ),
      size: Size.infinite,
    );
  }
}

class TimeSeriesChartPainter extends CustomPainter {
  final List<double> times;
  final List<double> corrections;
  final List<double> offsets;

  TimeSeriesChartPainter({
    required this.times,
    required this.corrections,
    required this.offsets,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Padding
    const double padding = 20;
    final chartWidth = width - (padding * 2);
    final chartHeight = height - (padding * 2);

    // Grid paint
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1;

    // Axis paint
    final axisPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;

    // Draw axes
    canvas.drawLine(
      Offset(padding, padding),
      Offset(padding, height - padding),
      axisPaint,
    );
    canvas.drawLine(
      Offset(padding, height - padding),
      Offset(width - padding, height - padding),
      axisPaint,
    );

    // Find min/max for correction values
    double minCorrection = 0;
    double maxCorrection = 0;

    if (corrections.isNotEmpty) {
      minCorrection = corrections.reduce(math.min);
      maxCorrection = corrections.reduce(math.max);
    }

    // Ensure range is not zero
    if (maxCorrection - minCorrection < 0.0001) {
      maxCorrection = minCorrection + 0.0001;
    }

    // Find max time
    final maxTime = times.isNotEmpty ? times.last : 1.0;

    // Draw correction line
    final correctionPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final correctionPath = Path();

    for (int i = 0; i < times.length; i++) {
      final x = padding + (times[i] / maxTime) * chartWidth;
      final y =
          padding +
          chartHeight -
          ((corrections[i] - minCorrection) /
              (maxCorrection - minCorrection) *
              chartHeight);

      if (i == 0) {
        correctionPath.moveTo(x, y);
      } else {
        correctionPath.lineTo(x, y);
      }
    }

    canvas.drawPath(correctionPath, correctionPaint);

    // Draw offset line
    final offsetPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final offsetPath = Path();

    // Find min/max for offset values
    double minOffset = 0;
    double maxOffset = 0;

    if (offsets.isNotEmpty) {
      minOffset = offsets.reduce(math.min);
      maxOffset = offsets.reduce(math.max);
    }

    // Ensure range is not zero
    if (maxOffset - minOffset < 0.0001) {
      maxOffset = minOffset + 0.0001;
    }

    for (int i = 0; i < times.length; i++) {
      final x = padding + (times[i] / maxTime) * chartWidth;
      final y =
          padding +
          chartHeight -
          ((offsets[i] - minOffset) / (maxOffset - minOffset) * chartHeight);

      if (i == 0) {
        offsetPath.moveTo(x, y);
      } else {
        offsetPath.lineTo(x, y);
      }
    }

    canvas.drawPath(offsetPath, offsetPaint);

    // Add legend
    final textStyle = TextStyle(color: Colors.black, fontSize: 10);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    // Correction legend
    textPainter.text = TextSpan(
      text: 'Time Correction',
      style: textStyle.copyWith(color: Colors.blue),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(padding, padding));

    // Offset legend
    textPainter.text = TextSpan(
      text: 'Estimated Offset',
      style: textStyle.copyWith(color: Colors.red),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(padding + 100, padding));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
