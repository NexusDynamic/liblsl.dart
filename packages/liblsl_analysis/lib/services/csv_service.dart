import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import '../models/csv_data.dart';

class CSVService {
  /// Process a CSV string into structured CSVData
  Future<CSVData> processCSV(String csvString) async {
    // Convert the CSV string to a list of lists
    final List<List<dynamic>> rowsAsListOfValues = const CsvToListConverter(
      shouldParseNumbers: true,
      allowInvalid: false,
      eol: '\n',
    ).convert(csvString);

    if (rowsAsListOfValues.isEmpty) {
      throw Exception('CSV file is empty');
    }

    // Extract headers (first row)
    final headers = rowsAsListOfValues.first.map((e) => e.toString()).toList();

    // Extract metadata if present (expecting a 'metadata' column)
    Map<String, dynamic>? metadata;
    final metadataColumnIndex = headers.indexWhere(
      (header) => header.toLowerCase() == 'metadata',
    );

    // Convert rows to list of maps
    final List<Map<String, dynamic>> rows = [];

    // Start from index 1 to skip the header row
    for (int i = 1; i < rowsAsListOfValues.length; i++) {
      final row = rowsAsListOfValues[i];
      if (row.length != headers.length) {
        // Skip rows with different column count
        continue;
      }

      final Map<String, dynamic> rowMap = {};

      for (int j = 0; j < headers.length; j++) {
        final value = row[j];
        rowMap[headers[j]] = value;

        // If this is the metadata column, process it
        if (j == metadataColumnIndex && value != null) {
          try {
            // Try to parse metadata as JSON if it looks like JSON
            if (value is String &&
                    (value.startsWith('{') && value.endsWith('}')) ||
                (value.startsWith('[') && value.endsWith(']'))) {
              metadata = parseMetadata(value);
            }
          } catch (e) {
            // If metadata parsing fails, just use it as a regular string
            if (kDebugMode) {
              print('Failed to parse metadata: $e');
            }
          }
        }
      }

      rows.add(rowMap);
    }

    return CSVData(headers: headers, rows: rows, metadata: metadata);
  }

  /// Attempt to parse metadata from a string (usually JSON)
  Map<String, dynamic>? parseMetadata(String metadataStr) {
    try {
      // This would use proper JSON parsing in a real app
      // For now, we'll do a basic extraction of key-value pairs
      final result = <String, dynamic>{};

      if (metadataStr.startsWith('{') && metadataStr.endsWith('}')) {
        // Simple key-value extraction
        final content = metadataStr.substring(1, metadataStr.length - 1);
        final pairs = content.split(',');

        for (var pair in pairs) {
          final parts = pair.split(':');
          if (parts.length == 2) {
            var key = parts[0].trim();
            var value = parts[1].trim();

            // Remove quotes from keys and string values
            if (key.startsWith('"') && key.endsWith('"')) {
              key = key.substring(1, key.length - 1);
            }

            if (value.startsWith('"') && value.endsWith('"')) {
              result[key] = value.substring(1, value.length - 1);
            } else if (value == 'true') {
              result[key] = true;
            } else if (value == 'false') {
              result[key] = false;
            } else if (value == 'null') {
              result[key] = null;
            } else {
              // Try to parse as number
              try {
                if (value.contains('.')) {
                  result[key] = double.parse(value);
                } else {
                  result[key] = int.parse(value);
                }
              } catch (_) {
                // Keep as string if not a number
                result[key] = value;
              }
            }
          }
        }
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing metadata: $e');
      }
      return null;
    }
  }
}
