import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dartframe/dartframe.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/enhanced_timing_analysis_service.dart';
import '../services/ultra_fast_enhanced_timing_analysis_service.dart';
import '../services/background_analysis_service.dart';

class EnhancedStatsWidget extends StatefulWidget {
  final DataFrame csvData;

  const EnhancedStatsWidget({super.key, required this.csvData});

  @override
  State<EnhancedStatsWidget> createState() => _EnhancedStatsWidgetState();
}

class _EnhancedStatsWidgetState extends State<EnhancedStatsWidget> {
  List<InterSampleIntervalResult>? _intervalResults;
  List<LatencyResult>? _latencyResults;
  bool _isLoading = true;
  AnalysisProgress? _currentProgress;

  @override
  void initState() {
    super.initState();
    _performEnhancedAnalysis();
  }

  Future<void> _performEnhancedAnalysis() async {
    try {
      setState(() {
        _currentProgress = const AnalysisProgress(
          stage: 'Enhanced Analysis',
          progress: 0.1,
          details: 'Starting enhanced timing analysis...',
        );
      });

      // Run the heavy computation in a background isolate
      final result = await compute(_computeEnhancedAnalysis, widget.csvData);

      if (mounted) {
        setState(() {
          _intervalResults =
              result['intervals'] as List<InterSampleIntervalResult>;
          _latencyResults = result['latencies'] as List<LatencyResult>;
          _isLoading = false;
          _currentProgress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enhanced analysis failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static Map<String, dynamic> _computeEnhancedAnalysis(DataFrame csvData) {
    final analysisService = UltraFastEnhancedTimingAnalysisService();

    final intervalResults = analysisService.calculateInterSampleIntervals(
      csvData,
    );
    final latencyResults = analysisService.calculateLatencies(csvData);

    return {'intervals': intervalResults, 'latencies': latencyResults};
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: _currentProgress != null
            ? _EnhancedAnalysisProgressIndicator(progress: _currentProgress!)
            : const CircularProgressIndicator(),
      );
    }

    if (_intervalResults == null || _latencyResults == null) {
      return const Center(child: Text('Enhanced analysis failed to complete'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enhanced Timing Analysis Results',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Includes time correction interpolation for accurate cross-device measurements',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),

            // Inter-sample intervals section
            _buildSectionHeader('Inter-Sample Production Intervals'),
            const SizedBox(height: 16),
            ..._intervalResults!.map((result) => _buildIntervalCard(result)),

            const SizedBox(height: 32),

            // Latency section
            _buildSectionHeader('Device-to-Device Latencies'),
            const SizedBox(height: 16),
            ..._latencyResults!.map((result) => _buildLatencyCard(result)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildIntervalCard(InterSampleIntervalResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device: ${result.deviceId}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatRow('Count', result.count),
                      _buildStatRow(
                        'Mean (ms)',
                        result.mean.toStringAsFixed(3),
                      ),
                      _buildStatRow(
                        'Median (ms)',
                        result.median.toStringAsFixed(3),
                      ),
                      _buildStatRow(
                        'Std Dev (ms)',
                        result.standardDeviation.toStringAsFixed(3),
                      ),
                      _buildStatRow('Min (ms)', result.min.toStringAsFixed(3)),
                      _buildStatRow('Max (ms)', result.max.toStringAsFixed(3)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 200,
                    child: _buildHistogram(
                      result.intervals,
                      'Interval (ms)',
                      'Count',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyCard(LatencyResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Latency: ${result.fromDevice} → ${result.toDevice}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (result.timeCorrectionApplied)
                  const Chip(
                    label: Text(
                      'Time Corrected',
                      style: TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                else
                  const Chip(
                    label: Text(
                      'No Time Correction',
                      style: TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.orange,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Show both corrected and raw latencies if time correction was applied
            if (result.timeCorrectionApplied) ...[
              Row(
                children: [
                  // Corrected latencies
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Time-Corrected Latencies',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow('Count', result.count),
                        _buildStatRow(
                          'Mean (ms)',
                          result.mean.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Median (ms)',
                          result.median.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Std Dev (ms)',
                          result.standardDeviation.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Min (ms)',
                          result.min.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Max (ms)',
                          result.max.toStringAsFixed(3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Raw latencies for comparison
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Raw Latencies (for comparison)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._buildRawStats(result.rawLatencies),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 200,
                      child: _buildComparisonHistogram(
                        result.latencies,
                        result.rawLatencies,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // No time correction available - show single set of results
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatRow('Count', result.count),
                        _buildStatRow(
                          'Mean (ms)',
                          result.mean.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Median (ms)',
                          result.median.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Std Dev (ms)',
                          result.standardDeviation.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Min (ms)',
                          result.min.toStringAsFixed(3),
                        ),
                        _buildStatRow(
                          'Max (ms)',
                          result.max.toStringAsFixed(3),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 200,
                      child: _buildHistogram(
                        result.latencies,
                        'Latency (ms)',
                        'Count',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRawStats(List<double> rawLatencies) {
    if (rawLatencies.isEmpty) {
      return [const Text('No raw data available')];
    }

    final sorted = List<double>.from(rawLatencies)..sort();
    final mean = rawLatencies.reduce((a, b) => a + b) / rawLatencies.length;
    final median = sorted.length % 2 == 0
        ? (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2
        : sorted[sorted.length ~/ 2];

    return [
      _buildStatRow('Count', rawLatencies.length, color: Colors.grey),
      _buildStatRow('Mean (ms)', mean.toStringAsFixed(3), color: Colors.grey),
      _buildStatRow(
        'Median (ms)',
        median.toStringAsFixed(3),
        color: Colors.grey,
      ),
      _buildStatRow(
        'Min (ms)',
        sorted.first.toStringAsFixed(3),
        color: Colors.grey,
      ),
      _buildStatRow(
        'Max (ms)',
        sorted.last.toStringAsFixed(3),
        color: Colors.grey,
      ),
    ];
  }

  Widget _buildStatRow(String label, dynamic value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w500, color: color),
            ),
          ),
          Text(value.toString(), style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _buildHistogram(List<double> data, String xTitle, String yTitle) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    // Create histogram bins
    final histogram = _createHistogram(data, 20); // 20 bins
    final spots = histogram.entries
        .map((entry) => FlSpot(entry.key, entry.value.toDouble()))
        .toList();

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(enabled: true),
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: Text(yTitle),
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: Text(xTitle),
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: const Color(0xff37434d), width: 1),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.blue,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonHistogram(
    List<double> correctedData,
    List<double> rawData,
  ) {
    if (correctedData.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    // Only plot the corrected data to avoid -10000ms values skewing the visualization
    final correctedHistogram = _createHistogram(correctedData, 20);

    final correctedSpots = correctedHistogram.entries
        .map((entry) => FlSpot(entry.key, entry.value.toDouble()))
        .toList();

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(enabled: true),
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Text('Count'),
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('Time-Corrected Latency (ms)'),
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: const Color(0xff37434d), width: 1),
        ),
        lineBarsData: [
          // Only show time-corrected data in the plot
          LineChartBarData(
            spots: correctedSpots,
            isCurved: false,
            color: Colors.green,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Map<double, int> _createHistogram(List<double> data, int binCount) {
    if (data.isEmpty) return {};

    final sortedData = List<double>.from(data)..sort();
    final min = sortedData.first;
    final max = sortedData.last;
    final binWidth = (max - min) / binCount;

    final histogram = <double, int>{};

    for (final value in data) {
      final binIndex = ((value - min) / binWidth).floor();
      final binStart = min + (binIndex * binWidth);
      histogram[binStart] = (histogram[binStart] ?? 0) + 1;
    }

    return histogram;
  }
}

/// Local progress indicator for enhanced analysis progress
class _EnhancedAnalysisProgressIndicator extends StatelessWidget {
  final AnalysisProgress progress;

  const _EnhancedAnalysisProgressIndicator({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getIconForStage(progress.stage), size: 48, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            progress.stage,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (progress.details != null)
            Text(
              progress.details!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: progress.progress,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          const SizedBox(height: 12),
          Text(
            '${(progress.progress * 100).toStringAsFixed(1)}%',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  IconData _getIconForStage(String stage) {
    switch (stage.toLowerCase()) {
      case 'enhanced analysis':
        return Icons.engineering;
      case 'inter-sample intervals':
        return Icons.timeline;
      case 'latency analysis':
        return Icons.network_ping;
      case 'complete':
        return Icons.check_circle;
      default:
        return Icons.analytics;
    }
  }
}
