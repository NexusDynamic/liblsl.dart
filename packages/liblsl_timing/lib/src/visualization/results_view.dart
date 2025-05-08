import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

class ResultsView extends StatefulWidget {
  final TimingManager timingManager;

  const ResultsView({super.key, required this.timingManager});

  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  String _selectedMetric = 'end_to_end';
  bool _showRawData = false;
  bool _useCorrectedMetrics = true; // Add this

  final List<String> _baseMetrics = [
    'end_to_end',
    'ui_to_sample',
    'sample_to_lsl',
    'lsl_to_receive',
    'frame_latency',
  ];

  // Compute the available metrics based on what's in the timing manager
  List<String> get _availableMetrics {
    final metrics = List<String>.from(_baseMetrics);

    // Add corrected metrics if they exist
    if (_useCorrectedMetrics) {
      for (final metric in _baseMetrics) {
        final correctedMetric = '${metric}_corrected';
        if (widget.timingManager.timingMetrics.containsKey(correctedMetric)) {
          if (!metrics.contains(correctedMetric)) {
            metrics.add(correctedMetric);
          }
        }
      }
    }

    // Add any other metrics that might exist
    for (final metric in widget.timingManager.timingMetrics.keys) {
      if (!metrics.contains(metric) && !metric.endsWith('_corrected')) {
        metrics.add(metric);
      }
    }

    return metrics;
  }

  @override
  Widget build(BuildContext context) {
    // Update UI to include toggle for corrected metrics
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Results', style: Theme.of(context).textTheme.titleLarge),
                Row(
                  children: [
                    const Text('Metric:'),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _availableMetrics.contains(_selectedMetric)
                          ? _selectedMetric
                          : (_availableMetrics.isNotEmpty
                                ? _availableMetrics.first
                                : null),
                      items: _availableMetrics.map((metric) {
                        return DropdownMenuItem<String>(
                          value: metric,
                          child: Text(_formatMetricName(metric)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedMetric = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Add toggle for corrected metrics if we have them
            if (widget.timingManager.timingMetrics.keys.any(
              (k) => k.endsWith('_corrected'),
            ))
              Row(
                children: [
                  Checkbox(
                    value: _useCorrectedMetrics,
                    onChanged: (value) {
                      setState(() {
                        _useCorrectedMetrics = value ?? true;

                        // If we're turning off corrected metrics and using one, switch to base
                        if (!_useCorrectedMetrics &&
                            _selectedMetric.endsWith('_corrected')) {
                          _selectedMetric = _selectedMetric.substring(
                            0,
                            _selectedMetric.length - '_corrected'.length,
                          );
                        }
                      });
                    },
                  ),
                  const Text('Use corrected metrics'),
                  Tooltip(
                    message:
                        'Time-corrected metrics compensate for system clock differences between LSL and Flutter',
                    child: Icon(Icons.info_outline, size: 16),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _showRawData,
                        onChanged: (value) {
                          setState(() {
                            _showRawData = value ?? false;
                          });
                        },
                      ),
                      const Text('Show Raw Data'),
                    ],
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Summary statistics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _buildStatCards(context),
            ),
            const SizedBox(height: 16),

            // Visualization
            _buildVisualizationSection(context),

            // Raw data (if enabled)
            if (_showRawData) _buildRawDataSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualization(BuildContext context, List<double> values) {
    if (values.isEmpty) return const SizedBox();

    // Scale values for the visualization
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_formatMetricName(_selectedMetric)} Distribution',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: TimeDistributionPainter(
                values: values,
                min: min,
                max: max,
                numBins: 30,
              ),
              size: const Size(double.infinity, 200),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatTime(min)),
              Text(_formatTime((min + max) / 2)),
              Text(_formatTime(max)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(double timeInSeconds) {
    // Convert to milliseconds for display
    final ms = timeInSeconds * 1000;

    if (ms < 1) {
      // Show microseconds for very small values
      return '${(ms * 1000).toStringAsFixed(1)} μs';
    } else if (ms < 1000) {
      // Show milliseconds
      return '${ms.toStringAsFixed(1)} ms';
    } else {
      // Show seconds
      return '${(ms / 1000).toStringAsFixed(2)} s';
    }
  }

  List<Widget> _buildStatCards(BuildContext context) {
    // Get stats for the selected metric
    final stats = widget.timingManager.getMetricStats(_selectedMetric);
    final values = widget.timingManager.timingMetrics[_selectedMetric] ?? [];

    return [
      _buildStatCard(context, 'Mean', _formatTime(stats['mean'] ?? 0)),
      _buildStatCard(context, 'Min', _formatTime(stats['min'] ?? 0)),
      _buildStatCard(context, 'Max', _formatTime(stats['max'] ?? 0)),
      _buildStatCard(context, 'Std Dev', _formatTime(stats['stdDev'] ?? 0)),
      _buildStatCard(context, 'Count', '${values.length}'),
    ];
  }

  Widget _buildVisualizationSection(BuildContext context) {
    final values = widget.timingManager.timingMetrics[_selectedMetric] ?? [];

    return Row(
      children: [
        values.isEmpty
            ? const Center(child: Text('No data available. Run a test first.'))
            : _buildVisualization(context, values),
      ],
    );
  }

  Widget _buildRawDataSection(BuildContext context) {
    final values = widget.timingManager.timingMetrics[_selectedMetric] ?? [];

    if (values.isEmpty) return const SizedBox();

    return SizedBox(
      height: 100,
      child: ListView.builder(
        itemCount: math.min(values.length, 100), // Limit to 100 entries
        itemBuilder: (context, index) {
          return Text(
            'Sample ${index + 1}: ${_formatTime(values[index])}',
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      ),
    );
  }

  String _formatMetricName(String metric) {
    // Handle corrected metrics
    if (metric.endsWith('_corrected')) {
      final baseName = metric.substring(0, metric.length - '_corrected'.length);
      return '${_formatBaseMetricName(baseName)} (Corrected)';
    }

    return _formatBaseMetricName(metric);
  }

  String _formatBaseMetricName(String metric) {
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
      case 'created_to_lsl_reported':
        return 'Creation to LSL Report';
      case 'lsl_to_lsl':
        return 'LSL to LSL Transfer';
      default:
        return metric;
    }
  }

  // Rest of the class remains the same...
}

class TimeDistributionPainter extends CustomPainter {
  final List<double> values;
  final double min;
  final double max;
  final int numBins;

  TimeDistributionPainter({
    required this.values,
    required this.min,
    required this.max,
    required this.numBins,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final labelPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Calculate bin size
    final binSize = (max - min) / numBins;

    // Count values in each bin
    final bins = List<int>.filled(numBins, 0);

    for (final value in values) {
      final binIndex = ((value - min) / binSize).floor();
      if (binIndex >= 0 && binIndex < numBins) {
        bins[binIndex]++;
      }
    }

    // Find the maximum bin count for scaling
    final maxCount = bins.reduce(math.max);

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

    // Draw the x-axis
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      labelPaint,
    );

    // Draw vertical grid lines
    for (int i = 0; i <= numBins; i += 5) {
      final x = i * barWidth;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, 0),
        labelPaint..color = Colors.grey.withAlpha(82),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
