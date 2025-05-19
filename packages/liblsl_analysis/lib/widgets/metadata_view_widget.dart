import 'package:dartframe/dartframe.dart';
import 'package:flutter/material.dart';

class MetadataViewWidget extends StatelessWidget {
  final DataFrame csvData;

  const MetadataViewWidget({super.key, required this.csvData});

  @override
  Widget build(BuildContext context) {
    final metadata = csvData['metadata'];

    if (metadata.length == 0) {
      return const Center(child: Text('No metadata available'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Metadata',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: metadata.data.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(child: _buildValueWidget(entry.value)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValueWidget(dynamic value) {
    if (value == null) {
      return const Text('null', style: TextStyle(fontStyle: FontStyle.italic));
    } else if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    e.key.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(child: _buildValueWidget(e.value)),
              ],
            ),
          );
        }).toList(),
      );
    } else if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.asMap().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '[${e.key}]',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(child: _buildValueWidget(e.value)),
              ],
            ),
          );
        }).toList(),
      );
    } else {
      return Text(value.toString());
    }
  }
}
