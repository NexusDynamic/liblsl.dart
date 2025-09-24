import 'package:dartframe/dartframe.dart';
import 'package:flutter/material.dart';
import '../widgets/data_table_widget.dart';
import '../widgets/simplified_stats_widget.dart';
import '../widgets/enhanced_stats_widget.dart';
import '../widgets/metadata_view_widget.dart';

class DataViewScreen extends StatefulWidget {
  final DataFrame csvData;
  final String fileName;

  const DataViewScreen({
    super.key,
    required this.csvData,
    required this.fileName,
  });

  @override
  State<DataViewScreen> createState() => _DataViewScreenState();
}

class _DataViewScreenState extends State<DataViewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DataFrame? _currentData;
  String? _sortColumn;
  bool _sortAscending = true;
  String? _filterColumn;
  String _filterValue = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _currentData = widget.csvData;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }

      _currentData?.sort(column, ascending: _sortAscending);
    });
  }

  void _applyFilter() {
    if (_filterColumn == null || _filterValue.isEmpty) {
      setState(() {
        _currentData = widget.csvData;
      });
      return;
    }

    setState(() {
      _currentData = widget.csvData.filter((row) {
        final value = row[_filterColumn];
        if (value == null) return false;
        return value.toString().toLowerCase().contains(
          _filterValue.toLowerCase(),
        );
      });
    });
  }

  void _resetFilters() {
    setState(() {
      _filterColumn = null;
      _filterValue = '';
      _currentData = widget.csvData;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analysis: ${widget.fileName}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.table_chart), text: 'Data'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Statistics'),
            Tab(icon: Icon(Icons.analytics), text: 'Enhanced'),
            Tab(icon: Icon(Icons.info), text: 'Metadata'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_tabController.index == 0) // Only show filter on data tab
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Filter Column',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _filterColumn,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Select column'),
                        ),
                        ...widget.csvData.columns.map(
                          (header) => DropdownMenuItem<String>(
                            value: header,
                            child: Text(header),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _filterColumn = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Filter Value',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _filterValue = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _applyFilter,
                    child: const Text('Apply'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _resetFilters,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Data Tab
                DataTableWidget(
                  csvData: _currentData,
                  onSort: _onSort,
                  sortColumn: _sortColumn,
                  sortAscending: _sortAscending,
                ),

                // Basic Statistics Tab
                SimplifiedStatsWidget(csvData: widget.csvData),

                // Enhanced Statistics Tab
                EnhancedStatsWidget(csvData: widget.csvData),

                // Metadata Tab
                MetadataViewWidget(csvData: widget.csvData),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
