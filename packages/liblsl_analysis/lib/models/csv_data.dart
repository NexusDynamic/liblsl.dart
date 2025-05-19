/// Represents structured CSV data with column names and rows
class CSVData {
  final List<String> headers;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? metadata;

  const CSVData({required this.headers, required this.rows, this.metadata});

  /// Get column values as a list
  List<dynamic> getColumn(String columnName) {
    return rows.map((row) => row[columnName]).toList();
  }

  /// Filter rows by a condition
  CSVData filter(bool Function(Map<String, dynamic> row) condition) {
    final filteredRows = rows.where(condition).toList();
    return CSVData(headers: headers, rows: filteredRows, metadata: metadata);
  }

  /// Sort rows by a specific column
  CSVData sortBy(String columnName, {bool ascending = true}) {
    final List<Map<String, dynamic>> sortedRows = List.from(rows);
    sortedRows.sort((a, b) {
      final valueA = a[columnName];
      final valueB = b[columnName];

      if (valueA == null) return ascending ? -1 : 1;
      if (valueB == null) return ascending ? 1 : -1;

      int comparison;
      if (valueA is num && valueB is num) {
        comparison = valueA.compareTo(valueB);
      } else {
        comparison = valueA.toString().compareTo(valueB.toString());
      }

      return ascending ? comparison : -comparison;
    });

    return CSVData(headers: headers, rows: sortedRows, metadata: metadata);
  }

  /// Get descriptive statistics for numerical columns
  Map<String, Map<String, dynamic>> getStats() {
    final result = <String, Map<String, dynamic>>{};

    for (final column in headers) {
      final values = getColumn(column).whereType<num>().toList();

      if (values.isNotEmpty) {
        values.sort();
        final sum = values.reduce((a, b) => a + b);
        final mean = sum / values.length;

        final middleIndex = values.length ~/ 2;
        final median = values.length.isOdd
            ? values[middleIndex]
            : (values[middleIndex - 1] + values[middleIndex]) / 2;

        final min = values.first;
        final max = values.last;

        final deviations = values.map(
          (value) => (value - mean) * (value - mean),
        );
        final variance = deviations.reduce((a, b) => a + b) / values.length;
        final stdDev = variance <= 0 ? 0 : sqrt(variance);

        result[column] = {
          'count': values.length,
          'mean': mean,
          'median': median,
          'min': min,
          'max': max,
          'std': stdDev,
        };
      }
    }

    return result;
  }

  /// Group data by a column and perform aggregation
  Map<dynamic, Map<String, dynamic>> groupBy(
    String columnName,
    Map<String, String Function(List<dynamic>)> aggregations,
  ) {
    final groups = <dynamic, List<Map<String, dynamic>>>{};

    // Group rows by the given column
    for (final row in rows) {
      final key = row[columnName];
      groups.putIfAbsent(key, () => []).add(row);
    }

    // Apply aggregations to each group
    final result = <dynamic, Map<String, dynamic>>{};
    groups.forEach((key, groupRows) {
      final aggregated = <String, dynamic>{};

      aggregations.forEach((resultColumn, aggregateFn) {
        final columnValues = groupRows.map((row) {
          return headers.contains(resultColumn) ? row[resultColumn] : null;
        }).toList();

        aggregated[resultColumn] = aggregateFn(columnValues);
      });

      result[key] = aggregated;
    });

    return result;
  }
}

/// Simple math utilities
double sqrt(double value) {
  // Simple implementation for square root
  if (value <= 0) return 0;

  double x = value / 2;
  double prev;

  do {
    prev = x;
    x = (x + value / x) / 2;
  } while ((prev - x).abs() > 1e-10);

  return x;
}
