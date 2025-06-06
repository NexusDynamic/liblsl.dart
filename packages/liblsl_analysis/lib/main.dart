import 'dart:convert';
import 'dart:math';

import 'package:dartframe/dartframe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'screens/data_view_screen.dart';
import 'screens/file_picker_screen.dart';
import 'package:liblsl_analysis/extensions/series_pick_indices.dart';

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

  Future<void> _pickAndProcessFile() async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tsv'],
        dialogTitle: 'Select a TSV files',
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          fileName = file.name;
          if (kDebugMode) {
            print('Selected file: ${file.path}');
          }
          final data = await fileIO.readFromFile(file.path);
          final singleCsvData = DataFrame.fromCSV(csv: data, delimiter: '\t');

          if (csvData == null) {
            csvData = singleCsvData;
          } else {
            csvData = csvData!.concatenate(singleCsvData);
          }
        }

        if (csvData != null) {
          if (kDebugMode) {
            print('CSV Data loaded successfully:');
          }
          csvData!['extractedTimestamp'] = (csvData!['event_id']).map((el) {
            // extract the timestamp from the event_id
            return el.toString().split('_')[1];
          });
          csvData!.columns = csvData!.columns.map((colname) {
            // strip whitespace from column names
            return colname.trim();
          }).toList();

          // process json metadata column
          // {"sampleId":"260_DID_LatencyTest_3","counter":3,"flutterTime":1747318677.605998,"lslTime":23804.612151041,"lslTimestamp":23804.606961291,"data":[3.0,0.20758968591690063,0.393753319978714,0.39640799164772034,0.04201863333582878,0.16800223290920258,0.35932600498199463,0.859130322933197,0.08029846847057343,0.8140344619750977,0.4999730885028839,0.3090531527996063,0.5186386704444885,0.8037077188491821,0.2308173030614853,0.2816702425479889],"reportingDeviceId":"260_DID","reportingDeviceName":"Device_82"}
          // {"sampleId":"260_DID_7","counter":7,"lslTime":23804.60972975,"reportingDeviceId":"260_DID","reportingDeviceName":"Device_82"}
          // {"device_name":"Device_82","stream_name":"DartTimingTest","stream_type":"Markers","channel_count":16,"sample_rate":1000.0,"channel_format":"float32","is_producer":true,"is_consumer":true,"device_id":"260_DID","test_duration_seconds":180,"stream_max_wait_time":5.0,"stream_max_streams":15,"reportingDeviceId":"260_DID","reportingDeviceName":"Device_82"}
          // {"sampleId":"260_DID_9","counter":9,"lslTime":23804.612186041,"reportingDeviceId":"260_DID","reportingDeviceName":"Device_82"}
          // {"device_name":"Device_82","stream_name":"DartTimingTest","stream_type":"Markers","channel_count":1,"sample_rate":100.0,"channel_format":"float32","is_producer":true,"is_consumer":true,"device_id":"260_DID","test_duration_seconds":180,"stream_max_wait_time":5.0,"stream_max_streams":15,"syncStreams":1,"syncInlets":1,"reportingDeviceId":"260_DID","reportingDeviceName":"Device_82"}
          // {"deviceId":"684_DID_Sync","timeCorrection":-25.694465624999793,"remoteTime":2685.269822375,"estimatedOffset":-25.694465624999793,"reportingDeviceId":"260_DID","reportingDeviceName":"Device_82"}
          // {"syncId":3,"deviceId":"260_DID","deviceName":"Device_82","localTime":1747390515.683611,"lslTime":2659.857578708,"systemOffset":-1747387855.8260322,"reportingDeviceId":"260_DID","reportingDeviceName":"Device_82"}
          if (csvData!.columns.contains('metadata')) {
            final metaColumns = [
              'sampleId',
              'counter',
              'lslTime',
              'lslTimestamp',
              'lslSent',
              'dartTimestamp',
              'reportingDeviceName',
              'reportingDeviceId',
              'testType',
              // @todo: add testId to runner...
              'testId',
              'sourceId', // pseudo column for sourceId until it is added
            ];

            final List<List<dynamic>> metadataValues = [];
            for (var value in csvData!['metadata'].data) {
              value = value.toString();
              try {
                // strip double quotes if present from the start and end
                value = value.trim().replaceAll(RegExp(r'(^")|("$)'), '');
                // replace double quote escapes with one double quote
                // this is a dirty hack, if there is an empty value, this
                // will break it.
                //value = value.replaceAll(RegExp(r'""'), '"');
                final metadata = jsonDecode(value);
                final List<dynamic> metadataMap = List.filled(
                  metaColumns.length,
                  null,
                  growable: false,
                );
                if (metadata is Map<String, dynamic>) {
                  final sourcIdIndex = metaColumns.indexOf('sourceId');

                  for (final (idx, column) in metaColumns.indexed) {
                    if (column == 'sourceId' && metadataMap[idx] != null) {
                      continue;
                    }

                    if (metadata.containsKey(column)) {
                      metadataMap[idx] = metadata[column];
                      if (column == 'sampleId') {
                        // map to the sourceID
                        final sourceId = metadata['sampleId']
                            ?.toString()
                            .replaceAll(RegExp(r'^(LatencyTest_)'), '')
                            .replaceAll(RegExp(r'_+\d+$'), '');
                        if (sourceId != null) {
                          metadataMap[sourcIdIndex] = sourceId;
                        }
                      }
                    } else {
                      metadataMap[idx] = null; // or some default value
                    }
                  }
                } else {
                  if (kDebugMode) {
                    print('Metadata is not a map: $metadata');
                  }
                }
                metadataValues.add(metadataMap);
              } catch (e) {
                if (kDebugMode) {
                  print('Error parsing metadata: $e');
                }
              }
            }
            // drop the metadata column from the original DataFrame
            csvData!.drop('metadata');
            // create a new DataFrame with the metadata columns
            final metadataDf = DataFrame(metadataValues, columns: metaColumns);
            // merge the metadata DataFrame with the original DataFrame
            if (kDebugMode) {
              print('metadataDf: ${metadataDf.head(2)}');
              print('csvData before merge: ${csvData!.head(2)}');
            }
            csvData = csvData!.concatenate(metadataDf, axis: 1);
            if (kDebugMode) {
              print('csvData after merge: ${csvData!.head(2)}');
            }
          } else {
            if (kDebugMode) {
              print('No metadata column found in CSV data');
            }
          }
          // find all events of event_type == EventType.testStarted
          final testStartedEvents = csvData!['event_type'].isEqual(
            'EventType.testStarted',
          );
          final sources = csvData!['reportingDeviceName'].indices(
            testStartedEvents.data,
          );
          final lslStartTimestamps = csvData!['lsl_clock'].indices(
            testStartedEvents.data,
          );

          if (kDebugMode) {
            print(
              'Found ${sources.length} unique sources: $sources. '
              'LSL Start Timestamps: ${lslStartTimestamps.data}',
            );
          }
          // there should be only one testStarted event per source

          final lowestTimestamp = lslStartTimestamps.data
              .map(
                (e) => e != null
                    ? ((e is String) ? double.parse(e) : e)
                    : double.nan,
              )
              .reduce((a, b) => min(a, b));

          // device adjustments
          final Map<String, double> deviceAdjustments = {};
          for (final (index, source) in sources.data.indexed) {
            final deviceStartTimestamp = double.parse(
              lslStartTimestamps.data[index],
            );
            if (kDebugMode) {
              // device start timestamp
              print('LSL Start Timestamp for $source: $deviceStartTimestamp');
            }
            final diff = deviceStartTimestamp - lowestTimestamp;
            if (kDebugMode) {
              print('Device: $source, Adjustment: $diff');
            }
            deviceAdjustments[source] = lowestTimestamp + diff;

            // now remove the adjusted amount from the lslTimestamp column
            // for the current source
            final sourceIndices = csvData!['reportingDeviceName'].isEqual(
              source,
            );
            if (kDebugMode) {
              print(
                'Found ${sourceIndices.data.where((e) => e).length} entries for source "$source".',
              );
            }
            final adjustedTimestamps = csvData!['lsl_clock']
                .indices(sourceIndices.data)
                .data;
            int j = 0;
            for (final (i, pick) in sourceIndices.data.indexed) {
              if (pick) {
                // adjust the timestamp
                csvData!.updateCell(
                  'lsl_clock',
                  i,
                  double.parse(adjustedTimestamps[j]) -
                      deviceAdjustments[source]!,
                );
                j++;
              }
            }
          }

          if (kDebugMode) {
            print('Lowest LSL timestamp: $lowestTimestamp');
          }

          csvData!.sort('lsl_clock');
          // Navigate to data view screen
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DataViewScreen(
                  csvData: csvData!,
                  fileName: fileName ?? 'Unnamed CSV',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading CSV: ${e.toString()}')),
        );
        if (kDebugMode) {
          print('Error loading CSV: $e');
          // backtrace
          print('Stack trace: ${StackTrace.current}');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: FilePickerScreen(
        onPickFile: _pickAndProcessFile,
        isLoading: isLoading,
      ),
    );
  }
}
