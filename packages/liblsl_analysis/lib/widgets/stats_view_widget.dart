import 'dart:math';

import 'package:dartframe/dartframe.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

extension SeriesPickIndices on Series {
  Series indices(List<dynamic> indices) {
    List<dynamic> selectedData = [];

    for (int i = 0; i < indices.length; i++) {
      if (indices[i]) {
        selectedData.add(data[i]);
      }
    }
    return Series(selectedData, name: name);
  }
}

class StatsViewWidget extends StatelessWidget {
  final DataFrame csvData;

  const StatsViewWidget({super.key, required this.csvData});

  Map<String, Map<String, dynamic>> _calculateStatistics() {
    final Map<String, Map<String, dynamic>> stats = {};

    // first we will calculate the stats for EventType.sampleCreated timestamp
    final pickIndices = csvData['event_type'].isEqual(
      'EventType.sampleCreated',
    );

    final timestampColumn = csvData['timestamp'].indices(pickIndices.data);
    //print(indices);
    //final timestampColumn = csvData[indices]['timestamp'];
    // we care about the inter-sample interval
    final interSampleInterval = <double>[];
    for (int i = 1; i < timestampColumn.length; i++) {
      final interval =
          (double.parse(timestampColumn[i]) -
              double.parse(timestampColumn[i - 1])) *
          1000;
      interSampleInterval.add(interval);
    }
    // calculate the stats
    final mean =
        interSampleInterval.reduce((a, b) => a + b) /
        interSampleInterval.length;
    final median = interSampleInterval.length % 2 == 0
        ? (interSampleInterval[interSampleInterval.length ~/ 2 - 1] +
                  interSampleInterval[interSampleInterval.length ~/ 2]) /
              2
        : interSampleInterval[interSampleInterval.length ~/ 2];
    final intervalMin = interSampleInterval.reduce(min);
    final intervalMax = interSampleInterval.reduce(max);
    final stdDev = sqrt(
      interSampleInterval.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) /
          interSampleInterval.length,
    );

    // create a histogram of the inter-sample intervals
    final histogram = <double, int>{};
    for (final interval in interSampleInterval) {
      histogram[double.parse(interval.toStringAsFixed(1))] =
          (histogram[double.parse(interval.toStringAsFixed(1))] ?? 0) + 1;
    }
    // sort the histogram by key
    final sortedHistogram = histogram.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // create a list of FlSpot for the histogram
    final histogramData = sortedHistogram
        .map((entry) => FlSpot(entry.key, entry.value.toDouble()))
        .toList();
    // create a LineChartBarData for the histogram
    final histogramBarData = LineChartBarData(
      spots: histogramData,
      show: true,
      color: Colors.blue.withAlpha(255),
      dotData: FlDotData(show: false),
      preventCurveOverShooting: true,
      isCurved: true,
      barWidth: 1.0,
      belowBarData: BarAreaData(show: true, color: Colors.blue.withAlpha(180)),
    );

    stats['Inter-Sample Interval'] = {
      'count': interSampleInterval.length,
      'mean': mean,
      'median': median,
      'min': intervalMin,
      'max': intervalMax,
      'std': stdDev,
      'plot': histogramBarData,
      'xtitle': 'Inter-Sample Interval (ms)',
      'ytitle': 'Count',
    };

    // now the same for latency
    final sampleRecievedIndices = csvData['event_type'].isEqual(
      'EventType.sampleReceived',
    );
    final recievedTimestamps = csvData['timestamp'].indices(
      sampleRecievedIndices.data,
    );
    final recievedCounter = csvData['counter'].indices(
      sampleRecievedIndices.data,
    );
    final recievedSourceId = csvData['sourceId'].indices(
      sampleRecievedIndices.data,
    );
    final myDeviceId = csvData['reportingDeviceId'].data[0];
    // we already have the sampleCreated timestamps in timestampColumn,
    // so we can just use that to calculate the
    // latency
    final sentCounter = csvData['counter'].indices(pickIndices.data);

    final List<double> latency = List.filled(
      sentCounter.length,
      double.nan,
      growable: true,
    );
    for (int i = 0; i < recievedCounter.length; i++) {
      if (recievedSourceId.data[i] != myDeviceId) {
        continue;
      }
      final cIndex =
          recievedCounter.data[i] - 1; // -1 because we are using 0 based index
      latency[cIndex] = double.parse(recievedTimestamps.data[i]);
    }

    for (int i = 0; i < sentCounter.length; i++) {
      final cIndex = sentCounter.data[i] - 1;
      if (latency[cIndex].isNaN) {
        // this means we didn't get a sampleReceived event for this sample
        // so we will just use the timestamp from the sampleCreated event
        continue;
      }
      latency[cIndex] -= double.parse(timestampColumn.data[i]);
    }

    // remove all the nans values from the latency list
    latency.removeWhere((element) => element.isNaN);
    // convert to milliseconds
    for (int i = 0; i < latency.length; i++) {
      latency[i] *= 1000;
    }

    // calculate the stats
    final latencyMean = latency.reduce((a, b) => a + b) / latency.length;
    final latencyMedian = latency.length % 2 == 0
        ? (latency[latency.length ~/ 2 - 1] + latency[latency.length ~/ 2]) / 2
        : latency[latency.length ~/ 2];
    final latencyMin = latency.reduce(min);
    final latencyMax = latency.reduce(max);
    final latencyStdDev = sqrt(
      latency.map((x) => pow(x - latencyMean, 2)).reduce((a, b) => a + b) /
          latency.length,
    );
    // create a histogram of the latency
    final latencyHistogram = <double, int>{};
    for (final interval in latency) {
      latencyHistogram[double.parse(interval.toStringAsFixed(1))] =
          (latencyHistogram[double.parse(interval.toStringAsFixed(1))] ?? 0) +
          1; // floor it to get the
      // histogram
    }
    // sort the histogram by key
    final sortedLatencyHistogram = latencyHistogram.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // create a list of FlSpot for the histogram
    final latencyHistogramData = sortedLatencyHistogram
        .map((entry) => FlSpot(entry.key, entry.value.toDouble()))
        .toList();
    // create a LineChartBarData for the histogram
    final latencyHistogramBarData = LineChartBarData(
      spots: latencyHistogramData,
      show: true,
      color: Colors.red.withAlpha(255),
      dotData: FlDotData(show: false),
      preventCurveOverShooting: true,
      isCurved: true,
      barWidth: 1.0,
      belowBarData: BarAreaData(show: true, color: Colors.red.withAlpha(180)),
    );
    stats['Latency'] = {
      'count': latency.length,
      'mean': latencyMean,
      'median': latencyMedian,
      'min': latencyMin,
      'max': latencyMax,
      'std': latencyStdDev,
      'plot': latencyHistogramBarData,
      'xtitle': 'Latency (ms)',
      'ytitle': 'Count',
    };
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStatistics();
    //final sentSamples = csvData[]

    // ignore: prefer_is_empty
    if (stats.length == 0) {
      return const Center(
        child: Text('No numerical data available for statistics'),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statistical Summary',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...stats.entries.map((stat) {
              final columnName = stat.key;
              final columnStats = stat.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        columnName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatRow('Count', columnStats['count']),
                              _buildStatRow('Mean', columnStats['mean']),
                              _buildStatRow('Median', columnStats['median']),
                              _buildStatRow('Min', columnStats['min']),
                              _buildStatRow('Max', columnStats['max']),
                              _buildStatRow('Std Dev', columnStats['std']),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // show the distribution of the data
                              SizedBox(
                                width: 600,
                                height: 300,
                                child: LineChart(
                                  LineChartData(
                                    lineTouchData: LineTouchData(),
                                    gridData: FlGridData(show: true),
                                    titlesData: FlTitlesData(
                                      leftTitles: AxisTitles(
                                        axisNameWidget: Text(
                                          columnStats['ytitle'],
                                        ),
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 40,
                                        ),
                                      ),
                                      bottomTitles: AxisTitles(
                                        axisNameWidget: Text(
                                          columnStats['xtitle'],
                                        ),
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 40,
                                        ),
                                      ),
                                      rightTitles: const AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                      topTitles: const AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                    ),
                                    borderData: FlBorderData(
                                      show: true,
                                      border: Border.all(
                                        color: const Color(0xff37434d),
                                        width: 1,
                                      ),
                                    ),
                                    lineBarsData: [
                                      columnStats['plot'] as LineChartBarData,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, dynamic value) {
    String displayValue;

    if (value is double) {
      // Format to 4 decimal places
      displayValue = value.toStringAsFixed(4);
    } else {
      displayValue = value.toString();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(displayValue),
        ],
      ),
    );
  }
}
