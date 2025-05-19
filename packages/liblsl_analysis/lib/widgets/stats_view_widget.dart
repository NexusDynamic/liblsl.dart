import 'package:dartframe/dartframe.dart';
import 'package:flutter/material.dart';

class StatsViewWidget extends StatelessWidget {
  final DataFrame csvData;

  const StatsViewWidget({super.key, required this.csvData});

  @override
  Widget build(BuildContext context) {
    final stats = csvData['timestamp'];
    //final sentSamples = csvData[]

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
            ...stats.data.map((entry) {
              final columnName = entry.key;
              final columnStats = entry.value;

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
                      _buildStatRow('Count', columnStats['count']),
                      _buildStatRow('Mean', columnStats['mean']),
                      _buildStatRow('Median', columnStats['median']),
                      _buildStatRow('Min', columnStats['min']),
                      _buildStatRow('Max', columnStats['max']),
                      _buildStatRow('Std Dev', columnStats['std']),
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
