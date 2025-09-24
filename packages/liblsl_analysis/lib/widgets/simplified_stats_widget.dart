import 'package:flutter/material.dart';
import 'package:dartframe/dartframe.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/efficient_timing_analysis_service.dart';
import '../services/background_analysis_service.dart';

class SimplifiedStatsWidget extends StatefulWidget {
  final DataFrame csvData;

  const SimplifiedStatsWidget({super.key, required this.csvData});

  @override
  State<SimplifiedStatsWidget> createState() => _SimplifiedStatsWidgetState();
}

class _SimplifiedStatsWidgetState extends State<SimplifiedStatsWidget> {
  AnalysisResult? _analysisResult;
  bool _isLoading = true;
  AnalysisProgress? _currentProgress;

  @override
  void initState() {
    super.initState();
    _performAnalysis();
  }

  Future<void> _performAnalysis() async {
    try {
      final result =
          await BackgroundAnalysisService.performAnalysisInBackground(
            data: widget.csvData,
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _currentProgress = progress;
                });
              }
            },
          );

      if (mounted) {
        setState(() {
          _analysisResult = result;
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
            content: Text('Analysis failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: _currentProgress != null
            ? _AnalysisProgressIndicator(progress: _currentProgress!)
            : const CircularProgressIndicator(),
      );
    }

    if (_analysisResult == null) {
      return const Center(child: Text('Analysis failed to complete'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Timing Analysis Results',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Inter-sample intervals section
            _buildSectionHeader('Inter-Sample Production Intervals'),
            const SizedBox(height: 16),
            ..._analysisResult!.intervalResults.map(
              (result) => _buildIntervalCard(result),
            ),

            const SizedBox(height: 32),

            // Latency section
            _buildSectionHeader('Device-to-Device Latencies'),
            const SizedBox(height: 16),
            ..._analysisResult!.latencyResults.map(
              (result) => _buildLatencyCard(result),
            ),
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
            Text(
              'Latency: ${result.fromDevice} → ${result.toDevice}',
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
                      result.latencies,
                      'Latency (ms)',
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

  Widget _buildStatRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(value.toString()),
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

/// Local progress indicator for analysis progress
class _AnalysisProgressIndicator extends StatelessWidget {
  final AnalysisProgress progress;

  const _AnalysisProgressIndicator({required this.progress});

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
          Icon(
            _getIconForStage(progress.stage),
            size: 48,
            color: Theme.of(context).primaryColor,
          ),
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
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).primaryColor,
            ),
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
      case 'initializing':
        return Icons.settings;
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
