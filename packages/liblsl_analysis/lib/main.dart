import 'dart:convert';
import 'dart:io';

import 'package:dartframe/dartframe.dart' hide FileType;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/data_view_screen.dart';
import 'screens/file_picker_screen.dart';
import 'services/background_processor.dart';
import 'widgets/progress_indicator_widget.dart';

void main() {
  runApp(const LSLAnalysis());
}

class LSLAnalysis extends StatelessWidget {
  const LSLAnalysis({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liblsl Timing Analysis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AnalysisHomePage(title: 'Liblsl Timing Analysis'),
    );
  }
}

class AnalysisHomePage extends StatefulWidget {
  const AnalysisHomePage({super.key, required this.title});

  final String title;

  @override
  State<AnalysisHomePage> createState() => _AnalysisHomePageState();
}

class _AnalysisHomePageState extends State<AnalysisHomePage> {
  DataFrame? csvData;
  String? fileName;
  bool isLoading = false;
  ProcessingProgress? currentProgress;

  static const String _lastDirectoryKey = 'last_selected_directory';

  /// Get the last used directory from shared preferences
  Future<String?> _getLastDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDir = prefs.getString(_lastDirectoryKey);

      // Verify the directory still exists
      if (lastDir != null && await Directory(lastDir).exists()) {
        if (kDebugMode) {
          print('📂 Loading last directory: $lastDir');
        }
        return lastDir;
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error loading last directory: $e');
      }
    }
    return null;
  }

  /// Save the selected directory to shared preferences
  Future<void> _saveLastDirectory(String directoryPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastDirectoryKey, directoryPath);
      if (kDebugMode) {
        print('💾 Saved last directory: $directoryPath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error saving last directory: $e');
      }
    }
  }

  Future<void> _pickAndProcessFile() async {
    setState(() {
      isLoading = true;
      currentProgress = const ProcessingProgress(
        stage: 'Reading files',
        progress: 0.0,
        details: 'Initializing file processing...',
      );
    });

    try {
      // Get the last used directory
      final initialDirectory = await _getLastDirectory();

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tsv'],
        dialogTitle: 'Select TSV files',
        allowMultiple: true,
        initialDirectory: initialDirectory,
      );

      if (result != null && result.files.isNotEmpty) {
        // Save the directory for next time
        final firstFilePath = result.files.first.path;
        if (firstFilePath != null) {
          final directory = Directory(firstFilePath).parent.path;
          await _saveLastDirectory(directory);
        }

        // Process files synchronously but with progress updates
        await _processFilesWithProgress(result.files);

        if (mounted && csvData != null) {
          setState(() {
            isLoading = false;
            currentProgress = null;
          });

          // Navigate to data view screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DataViewScreen(
                csvData: csvData!,
                fileName: fileName ?? 'Processed Data',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          currentProgress = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing files: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );

        if (kDebugMode) {
          print('Error processing files: $e');
        }
      }
    }
  }

  Future<void> _processFilesWithProgress(List<PlatformFile> files) async {
    // Load files
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      fileName = file.name;

      setState(() {
        currentProgress = ProcessingProgress(
          stage: 'Reading files',
          progress: (i / files.length) * 0.3,
          details: 'Processing ${file.name}...',
        );
      });

      if (kDebugMode) {
        print('Selected file: ${file.path}');
      }
      final data = await File(file.path!).readAsString();
      final singleCsvData = await DataFrame.fromCSV(csv: data, delimiter: '\t');

      if (csvData == null) {
        csvData = singleCsvData;
      } else {
        csvData = csvData!.concatenate([singleCsvData]);
      }
    }

    if (csvData == null) return;

    setState(() {
      currentProgress = const ProcessingProgress(
        stage: 'Processing data',
        progress: 0.3,
        details: 'Extracting timestamps...',
      );
    });

    // Extract timestamps
    csvData!['extractedTimestamp'] = (csvData!['event_id']).map((el) {
      return el.toString().split('_')[1];
    });

    // Clean column names
    csvData!.columns = csvData!.columns.map((colname) {
      return colname.trim();
    }).toList();

    setState(() {
      currentProgress = const ProcessingProgress(
        stage: 'Processing metadata',
        progress: 0.4,
        details: 'Parsing JSON metadata...',
      );
    });

    // Process metadata quickly (no chunking)
    if (csvData!.columns.contains('metadata')) {
      final metaColumns = [
        'sampleId',
        'counter',
        'lslTime',
        'lslTimestamp',
        'lslTimeCorrection',
        'lslSent',
        'dartTimestamp',
        'reportingDeviceName',
        'reportingDeviceId',
        'testType',
        'testId',
        'sourceId',
      ];

      final List<List<dynamic>> metadataValues = [];
      for (var value in csvData!['metadata'].data) {
        value = value.toString();
        try {
          value = value.trim().replaceAll(RegExp(r'(^")|("$)'), '');
          final metadata = jsonDecode(value);
          final List<dynamic> metadataMap = List.filled(
            metaColumns.length,
            null,
            growable: false,
          );
          if (metadata is Map<String, dynamic>) {
            final sourceIdIndex = metaColumns.indexOf('sourceId');

            for (final (idx, column) in metaColumns.indexed) {
              if (column == 'sourceId' && metadataMap[idx] != null) {
                continue;
              }

              if (metadata.containsKey(column)) {
                metadataMap[idx] = metadata[column];
                if (column == 'sampleId') {
                  final sourceId = metadata['sampleId']
                      ?.toString()
                      .replaceAll(RegExp(r'^(LatencyTest_)'), '')
                      .replaceAll(RegExp(r'_+\d+$'), '');
                  if (sourceId != null) {
                    metadataMap[sourceIdIndex] = sourceId;
                  }
                }
              } else {
                metadataMap[idx] = null;
              }
            }
          }
          metadataValues.add(metadataMap);
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing metadata: $e');
          }
          metadataValues.add(List.filled(metaColumns.length, null));
        }
      }

      setState(() {
        currentProgress = const ProcessingProgress(
          stage: 'Processing metadata',
          progress: 0.7,
          details: 'Merging metadata columns...',
        );
      });

      csvData!.drop('metadata');
      final metadataDf = DataFrame(metadataValues, columns: metaColumns);
      csvData = csvData!.concatenate([metadataDf], axis: 1);
    }

    setState(() {
      currentProgress = const ProcessingProgress(
        stage: 'Adjusting timestamps',
        progress: 0.8,
        details: 'Calculating device adjustments...',
      );
    });

    // Process timestamp adjustments
    // final testStartedEvents = csvData!['event_type'].isEqual('EventType.testStarted');
    // final sources = csvData!['reportingDeviceName'].indices(testStartedEvents.data);
    // final lslStartTimestamps = csvData!['lsl_clock'].indices(testStartedEvents.data);

    // if (kDebugMode) {
    //   print('Found ${sources.length} unique sources: $sources. '
    //       'LSL Start Timestamps: ${lslStartTimestamps.data}');
    // }

    // final lowestTimestamp = lslStartTimestamps.data
    //     .map((e) => e != null ? ((e is String) ? double.parse(e) : e) : double.nan)
    //     .reduce((a, b) => min(a, b));

    // final Map<String, double> deviceAdjustments = {};
    // for (final (index, source) in sources.data.indexed) {
    //   final deviceStartTimestamp = double.parse(lslStartTimestamps.data[index]);
    //   if (kDebugMode) {
    //     print('LSL Start Timestamp for $source: $deviceStartTimestamp');
    //   }
    //   final diff = deviceStartTimestamp - lowestTimestamp;
    //   if (kDebugMode) {
    //     print('Device: $source, Adjustment: $diff');
    //   }
    //   deviceAdjustments[source] = lowestTimestamp + diff;

    //   final sourceIndices = csvData!['reportingDeviceName'].isEqual(source);
    //   if (kDebugMode) {
    //     print('Found ${sourceIndices.data.where((e) => e).length} entries for source "$source".');
    //   }
    //   final adjustedTimestamps = csvData!['lsl_clock'].indices(sourceIndices.data).data;
    //   int j = 0;
    //   for (final (i, pick) in sourceIndices.data.indexed) {
    //     if (pick) {
    //       csvData!.updateCell(
    //         'lsl_clock',
    //         i,
    //         double.parse(adjustedTimestamps[j]) - deviceAdjustments[source]!,
    //       );
    //       j++;
    //     }
    //   }
    // }
    // make LSL clock a double
    csvData = csvData!.applyToColumn(
      'lsl_clock',
      (value) => double.tryParse(value.toString()) ?? double.nan,
    );

    setState(() {
      currentProgress = const ProcessingProgress(
        stage: 'Finalizing',
        progress: 0.95,
        details: 'Sorting data...',
      );
    });

    csvData!.sort('lsl_clock');

    setState(() {
      currentProgress = const ProcessingProgress(
        stage: 'Complete',
        progress: 1.0,
        details: 'Processing complete!',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          FilePickerScreen(
            onPickFile: _pickAndProcessFile,
            isLoading: isLoading,
          ),
          if (isLoading && currentProgress != null)
            LoadingOverlay(
              progress: currentProgress!,
              onCancel: () {
                setState(() {
                  isLoading = false;
                  currentProgress = null;
                });
              },
            ),
        ],
      ),
    );
  }
}
