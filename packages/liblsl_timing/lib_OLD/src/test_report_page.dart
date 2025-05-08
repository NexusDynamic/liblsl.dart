import 'package:flutter/material.dart';
import 'package:liblsl_timing/src/timing_manager.dart';
import 'package:liblsl_timing/src/utils/timing_data_exporter.dart';

import 'dart:math';

class TestReportPage extends StatefulWidget {
  final TimingManager timingManager;
  final String testName;

  const TestReportPage({
    super.key,
    required this.timingManager,
    required this.testName,
  });

  @override
  State<TestReportPage> createState() => _TestReportPageState();
}

class _TestReportPageState extends State<TestReportPage> {
  bool _isExporting = false;
  String? _exportPath;

  @override
  Widget build(BuildContext context) {
    final metrics = widget.timingManager.timingMetrics;
    final events = widget.timingManager.events;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.testName} Results'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _exportData),
          IconButton(icon: const Icon(Icons.share), onPressed: _shareResults),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Export status
            if (_isExporting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_exportPath != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Data exported to: $_exportPath',
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              ),

            // Summary section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Summary',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Test: ${widget.testName}'),
                    Text('Total events: ${events.length}'),
                    Text('Metrics collected: ${metrics.length}'),
                    Text('Test completed: ${_formatDateTime(DateTime.now())}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Metrics summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Timing Metrics',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),

                    for (final metricName in metrics.keys)
                      _buildMetricSummary(context, metricName),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Event timeline (simplified)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Event Timeline',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),

                    // Only show the first few events to avoid overwhelming the UI
                    for (int i = 0; i < min(20, events.length); i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(
                          '${_formatTime(events[i].timestamp)}: ${events[i].eventType} - ${events[i].description ?? ""}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),

                    if (events.length > 20)
                      Text(
                        '... and ${events.length - 20} more events',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricSummary(BuildContext context, String metricName) {
    final stats = widget.timingManager.getMetricStats(metricName);
    final values = widget.timingManager.timingMetrics[metricName] ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: ExpansionTile(
        title: Text(_formatMetricName(metricName)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats summary
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mean: ${_formatTime(stats['mean'] ?? 0)}'),
                        Text('Min: ${_formatTime(stats['min'] ?? 0)}'),
                        Text('Max: ${_formatTime(stats['max'] ?? 0)}'),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Std Dev: ${_formatTime(stats['stdDev'] ?? 0)}'),
                        Text('Count: ${values.length}'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Mini visualization
                if (values.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: CustomPaint(
                      painter: TimeSeriesPainter(values),
                      size: const Size(double.infinity, 100),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatMetricName(String metric) {
    // Same implementation as in ResultsView
    switch (metric) {
      case 'end_to_end':
        return 'End-to-End Latency';
      case 'ui_to_sample':
        return 'UI to Sample Creation';
      case 'sample_to_lsl':
        return 'Sample to LSL Timestamp';
      case 'lsl_to_receive':
        return 'LSL to Sample Reception';
      case 'frame_latency':
        return 'Frame Rendering Latency';
      default:
        return metric;
    }
  }

  String _formatTime(double timeInSeconds) {
    // Same implementation as in ResultsView
    final ms = timeInSeconds * 1000;

    if (ms < 1) {
      return '${(ms * 1000).toStringAsFixed(1)} μs';
    } else if (ms < 1000) {
      return '${ms.toStringAsFixed(1)} ms';
    } else {
      return '${(ms / 1000).toStringAsFixed(2)} s';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  Future<void> _exportData() async {
    setState(() {
      _isExporting = true;
      _exportPath = null;
    });

    try {
      final exporter = TimingDataExporter(widget.timingManager);
      final eventsPath = await exporter.exportEventsToCSV();
      final metricsPath = await exporter.exportMetricsToCSV();

      setState(() {
        _exportPath = 'Events: $eventsPath\nMetrics: $metricsPath';
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  Future<void> _shareResults() async {
    if (_exportPath == null) {
      await _exportData();
    }

    // This would normally use a share plugin like share_plus
    // but for simplicity, we'll just show a message
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sharing results...')));
  }
}

class TimeSeriesPainter extends CustomPainter {
  final List<double> values;

  TimeSeriesPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();

    // Find min/max for scaling
    final maxValue = values.reduce(max);
    final minValue = values.reduce(min);
    final range = maxValue - minValue;

    // Create points for the path
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final normalizedValue = range > 0
          ? (values[i] - minValue) / range
          : 0.5; // If all values are the same
      final y = size.height - (normalizedValue * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
