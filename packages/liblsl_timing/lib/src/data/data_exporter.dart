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
        String tmpFilePath = '${directory.path}/${fileBaseName}_$timestamp.tsv';
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
      '${directory.path}/${fileBaseName}_$timestamp.tsv',
    ).create(exclusive: false, recursive: true);
  }

  /// Export all timing events to a CSV file
  Future<String> exportEventsToTSV() async {
    final events = timingManager.events;

    if (events.isEmpty) {
      throw Exception('No events to export');
    }

    // Create CSV content
    final buffer = StringBuffer();

    // Header row
    buffer.writeln(
      'log_timestamp\ttimestamp\tevent_id\tevent_type\tlsl_clock\tdescription\tmetadata',
    );

    // Data rows
    for (final TimingEvent event in events) {
      final metadata = event.metadata != null ? jsonEncode(event.metadata) : '';

      buffer.writeln(
        '${event.logTimestamp}\t${event.timestamp}\t${event.eventId}\t'
        '${event.eventType}\t${event.lslClock}\t'
        '${_escapeTsvField(event.description ?? '')}\t'
        '${_escapeTsvField(metadata)}',
      );
    }

    // Save to file
    final file = await _getFile('lsl_events');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Helper method to escape TSV fields
  String _escapeTsvField(String field) {
    if (field.contains('\t') || field.contains('\n')) {
      // replace tabs and newlines with spaces
      field = field.replaceAll('\t', ' ').replaceAll('\n', ' ');
    }
    return field;
  }
}
