// lib/src/data/data_exporter.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'timing_manager.dart';

class DataExporter {
  final TimingManager timingManager;

  DataExporter(this.timingManager);

  Future<File> _getFile(String fileBaseName) async {
    Directory? directory = await getDownloadsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    File file;
    if (directory != null) {
      try {
        String tmpFilePath = '${directory.path}/${fileBaseName}_$timestamp.csv';
        // try opening for writing
        file = File(tmpFilePath);
        return await file.create(exclusive: false, recursive: true);
      } catch (e) {
        if (kDebugMode) {
          print('Failed to create file in downloads directory: $e');
        }
      }
    }
    // If we can't write to the downloads directory, fallback to application documents directory
    directory = await getApplicationDocumentsDirectory();
    return await File(
      '${directory.path}/${fileBaseName}_$timestamp.csv',
    ).create(exclusive: false, recursive: true);
  }

  /// Export all timing events to a CSV file
  Future<String> exportEventsToCSV() async {
    final events = timingManager.events;

    if (events.isEmpty) {
      throw Exception('No events to export');
    }

    // Create CSV content
    final buffer = StringBuffer();

    // Header row
    buffer.writeln('timestamp,event_id,event_type,description,metadata');

    // Data rows
    for (final event in events) {
      final metadata = event.metadata != null ? jsonEncode(event.metadata) : '';

      buffer.writeln(
        '${event.timestamp},${event.eventId},${event.eventType},'
        '${_escapeCsvField(event.description ?? '')},"${_escapeCsvField(metadata)}"',
      );
    }

    // Save to file
    final file = await _getFile('lsl_events');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Export calculated metrics to a CSV file
  Future<String> exportMetricsToCSV() async {
    final metrics = timingManager.metrics;

    if (metrics.isEmpty) {
      throw Exception('No metrics to export');
    }

    // Create CSV content
    final buffer = StringBuffer();

    // Process each metric type
    for (final metricName in metrics.keys) {
      final values = metrics[metricName] ?? [];

      buffer.writeln('\n$metricName');
      buffer.writeln('sample_number,value_seconds');

      for (int i = 0; i < values.length; i++) {
        buffer.writeln('${i + 1},${values[i]}');
      }

      // Add statistics
      final stats = timingManager.getMetricStats(metricName);
      buffer.writeln('\nStatistics:');
      buffer.writeln('mean,${stats['mean']}');
      buffer.writeln('min,${stats['min']}');
      buffer.writeln('max,${stats['max']}');
      buffer.writeln('stdDev,${stats['stdDev']}');
    }

    // Save to file
    final file = await _getFile('lsl_metrics');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Helper method to escape CSV fields
  String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return field.replaceAll('"', '""');
    }
    return field;
  }
}
