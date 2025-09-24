// lib/src/ui/results_page.dart
import 'package:flutter/material.dart';
import '../data/timing_manager.dart';
import '../data/data_exporter.dart';

class ResultsPage extends StatefulWidget {
  final TimingManager timingManager;
  final DataExporter dataExporter;

  const ResultsPage({
    super.key,
    required this.timingManager,
    required this.dataExporter,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Results'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _exportData),
        ],
      ),
      body: widget.timingManager.events.isEmpty
          ? const Center(child: Text('No test data available'))
          : _buildResultsView(),
    );
  }

  Widget _buildResultsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent events
          Text(
            'Recent Events:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildRecentEvents(),
        ],
      ),
    );
  }

  Widget _buildRecentEvents() {
    final events = widget.timingManager.events;
    final displayedEvents =
        events.length > 100 ? events.sublist(events.length - 100) : events;

    return SizedBox(
      height: 200,
      child: ListView.builder(
        itemCount: displayedEvents.length,
        itemBuilder: (context, index) {
          final event = displayedEvents[index];
          return ListTile(
            dense: true,
            title: Text(
              '${event.eventType}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(event.description ?? ''),
            trailing: Text(_formatTime(event.timestamp)),
          );
        },
      ),
    );
  }

  String _formatTime(double timeInSeconds) {
    final ms = timeInSeconds * 1000;

    if (ms < 1) {
      return '${(ms * 1000).toStringAsFixed(2)} μs';
    } else if (ms < 1000) {
      return '${ms.toStringAsFixed(2)} ms';
    } else {
      return '${(ms / 1000).toStringAsFixed(3)} s';
    }
  }

  Future<void> _exportData() async {
    try {
      final eventsPath = await widget.dataExporter.exportEventsToTSV();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data exported to:\n$eventsPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    }
  }
}

class HistogramPainter extends CustomPainter {
  final List<double> values;

  HistogramPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    // Calculate min/max
    double min = values.first;
    double max = values.first;

    for (final value in values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }

    // Ensure range isn't zero
    if (max - min < 0.0001) {
      max = min + 0.0001;
    }

    // Create bins
    const numBins = 20;
    final binSize = (max - min) / numBins;
    final bins = List<int>.filled(numBins, 0);

    for (final value in values) {
      final binIndex = ((value - min) / binSize).floor();
      if (binIndex >= 0 && binIndex < numBins) {
        bins[binIndex]++;
      }
    }

    // Find the maximum bin count for scaling
    int maxCount = 0;
    for (final count in bins) {
      if (count > maxCount) maxCount = count;
    }

    if (maxCount == 0) return;

    // Draw the histogram
    final barWidth = size.width / numBins;

    for (int i = 0; i < numBins; i++) {
      final barHeight = size.height * bins[i] / maxCount;

      final rect = Rect.fromLTWH(
        i * barWidth,
        size.height - barHeight,
        barWidth,
        barHeight,
      );

      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
