import 'package:dartframe/dartframe.dart';
import 'package:flutter/material.dart';
import 'package:liblsl_analysis/widgets/free_scroll_view.dart';

class DataTableWidget extends StatelessWidget {
  final DataFrame? csvData;
  final Function(String) onSort;
  final String? sortColumn;
  final bool sortAscending;

  const DataTableWidget({
    super.key,
    required this.csvData,
    required this.onSort,
    this.sortColumn,
    this.sortAscending = true,
  });

  @override
  Widget build(BuildContext context) {
    return csvData == null || csvData!.rows.isEmpty
        ? const Center(child: Text('No data available'))
        : FreeScrollView(
            child: DataTable(
              columns: csvData!.columns.map((header) {
                return DataColumn(
                  label: Row(
                    children: [
                      Text(header),
                      if (sortColumn == header)
                        Icon(
                          sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16,
                        ),
                    ],
                  ),
                  onSort: (_, __) => onSort(header),
                );
              }).toList(),
              rows: csvData!.head(50).rows.map((row) {
                return DataRow(
                  cells: List<DataCell>.generate(row.length, (idx) {
                    final value = row[idx];
                    return DataCell(Text(value?.toString() ?? 'null'));
                  }).toList(),
                );
              }).toList(),
            ),
          );
  }
}
