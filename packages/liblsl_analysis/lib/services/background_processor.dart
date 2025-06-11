import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:dartframe/dartframe.dart';
import 'package:flutter/foundation.dart';
import '../extensions/series_pick_indices.dart';

/// Progress update for background operations
class ProcessingProgress {
  final String stage;
  final double progress; // 0.0 to 1.0
  final String? details;

  const ProcessingProgress({
    required this.stage,
    required this.progress,
    this.details,
  });
}

/// Message types for isolate communication
enum MessageType { processFile, progress, result, error }

/// Message structure for isolate communication
class IsolateMessage {
  final MessageType type;
  final dynamic data;

  const IsolateMessage(this.type, this.data);
}

/// File processing request
class FileProcessingRequest {
  final String filePath;
  final String fileName;
  final bool isMultipleFiles;

  const FileProcessingRequest({
    required this.filePath,
    required this.fileName,
    this.isMultipleFiles = false,
  });
}

/// Background processor service
class BackgroundProcessor {
  static Future<DataFrame> processFilesInBackground({
    required List<FileProcessingRequest> files,
    required Function(ProcessingProgress) onProgress,
  }) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _isolateEntryPoint,
      receivePort.sendPort,
    );

    final completer = Completer<DataFrame>();
    SendPort? isolateSendPort;

    receivePort.listen((message) {
      if (message is SendPort) {
        // This is the initial SendPort from the isolate
        isolateSendPort = message;
        // Send the processing request
        isolateSendPort!.send(IsolateMessage(MessageType.processFile, files));
      } else if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.progress:
            onProgress(message.data as ProcessingProgress);
            break;
          case MessageType.result:
            completer.complete(message.data as DataFrame);
            receivePort.close();
            isolate.kill();
            break;
          case MessageType.error:
            completer.completeError(message.data);
            receivePort.close();
            isolate.kill();
            break;
          default:
            break;
        }
      }
    });

    return completer.future;
  }

  static void _isolateEntryPoint(SendPort mainSendPort) async {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    await for (final message in receivePort) {
      if (message is IsolateMessage &&
          message.type == MessageType.processFile) {
        try {
          final files = message.data as List<FileProcessingRequest>;
          final result = await _processFiles(files, (progress) {
            mainSendPort.send(IsolateMessage(MessageType.progress, progress));
          });
          mainSendPort.send(IsolateMessage(MessageType.result, result));
        } catch (e) {
          mainSendPort.send(IsolateMessage(MessageType.error, e.toString()));
        }
        break;
      }
    }
  }

  static Future<DataFrame> _processFiles(
    List<FileProcessingRequest> files,
    Function(ProcessingProgress) onProgress,
  ) async {
    DataFrame? csvData;

    onProgress(
      const ProcessingProgress(
        stage: 'Reading files',
        progress: 0.0,
        details: 'Starting file processing...',
      ),
    );

    // Process each file
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileProgress = i / files.length;

      onProgress(
        ProcessingProgress(
          stage: 'Reading files',
          progress: fileProgress * 0.3, // File reading is 30% of total
          details: 'Processing ${file.fileName}...',
        ),
      );

      final data = await fileIO.readFromFile(file.filePath);
      final singleCsvData = await DataFrame.fromCSV(csv: data, delimiter: '\t');

      if (csvData == null) {
        csvData = singleCsvData;
      } else {
        csvData = csvData.concatenate([singleCsvData]);
      }
    }

    if (csvData == null) {
      throw Exception('No data loaded');
    }

    onProgress(
      const ProcessingProgress(
        stage: 'Processing data',
        progress: 0.3,
        details: 'Extracting timestamps...',
      ),
    );

    // Extract timestamps
    csvData['extractedTimestamp'] = (csvData['event_id']).map((el) {
      return el.toString().split('_')[1];
    });

    // Clean column names
    csvData.columns = csvData.columns.map((colname) {
      return colname.trim();
    }).toList();

    onProgress(
      const ProcessingProgress(
        stage: 'Processing metadata',
        progress: 0.4,
        details: 'Parsing JSON metadata...',
      ),
    );

    // Process metadata in chunks to allow progress updates
    if (csvData.columns.contains('metadata')) {
      csvData = await _processMetadataInChunks(csvData, onProgress);
    }

    onProgress(
      const ProcessingProgress(
        stage: 'Adjusting timestamps',
        progress: 0.8,
        details: 'Calculating device adjustments...',
      ),
    );

    // Process timestamp adjustments
    csvData = await _processTimestampAdjustments(csvData, onProgress);

    onProgress(
      const ProcessingProgress(
        stage: 'Finalizing',
        progress: 0.95,
        details: 'Sorting data...',
      ),
    );

    csvData.sort('lsl_clock');

    onProgress(
      const ProcessingProgress(
        stage: 'Complete',
        progress: 1.0,
        details: 'Processing complete!',
      ),
    );

    return csvData;
  }

  static Future<DataFrame> _processMetadataInChunks(
    DataFrame csvData,
    Function(ProcessingProgress) onProgress,
  ) async {
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
    final totalRows = csvData['metadata'].data.length;
    const chunkSize = 100;

    for (int startIdx = 0; startIdx < totalRows; startIdx += chunkSize) {
      final endIdx = (startIdx + chunkSize).clamp(0, totalRows);
      final progress = 0.4 + (startIdx / totalRows) * 0.3; // 40-70% of total

      onProgress(
        ProcessingProgress(
          stage: 'Processing metadata',
          progress: progress,
          details: 'Processing rows ${startIdx + 1}-$endIdx of $totalRows...',
        ),
      );

      // Process chunk
      for (int i = startIdx; i < endIdx; i++) {
        var value = csvData['metadata'].data[i].toString();

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

      // Yield control to allow other operations
      await Future.delayed(const Duration(microseconds: 1));
    }

    onProgress(
      const ProcessingProgress(
        stage: 'Processing metadata',
        progress: 0.7,
        details: 'Merging metadata columns...',
      ),
    );

    // Merge metadata
    csvData.drop('metadata');
    final metadataDf = DataFrame(metadataValues, columns: metaColumns);
    return csvData.concatenate([metadataDf], axis: 1);
  }

  static Future<DataFrame> _processTimestampAdjustments(
    DataFrame csvData,
    Function(ProcessingProgress) onProgress,
  ) async {
    // Find test started events
    final testStartedEvents = csvData['event_type'].isEqual(
      'EventType.testStarted',
    );
    final sources = csvData['reportingDeviceName'].indices(
      testStartedEvents.data,
    );
    final lslStartTimestamps = csvData['lsl_clock'].indices(
      testStartedEvents.data,
    );

    final lowestTimestamp = lslStartTimestamps.data
        .map(
          (e) => e != null ? ((e is String) ? double.parse(e) : e) : double.nan,
        )
        .reduce((a, b) => min(a, b));

    final Map<String, double> deviceAdjustments = {};

    for (final (index, source) in sources.data.indexed) {
      final deviceStartTimestamp = double.parse(lslStartTimestamps.data[index]);
      final diff = deviceStartTimestamp - lowestTimestamp;
      deviceAdjustments[source] = lowestTimestamp + diff;

      onProgress(
        ProcessingProgress(
          stage: 'Adjusting timestamps',
          progress: 0.8 + (index / sources.data.length) * 0.15,
          details: 'Adjusting timestamps for $source...',
        ),
      );

      // Adjust timestamps for this source
      final sourceIndices = csvData['reportingDeviceName'].isEqual(source);
      final adjustedTimestamps = csvData['lsl_clock']
          .indices(sourceIndices.data)
          .data;

      int j = 0;
      for (final (i, pick) in sourceIndices.data.indexed) {
        if (pick) {
          csvData.updateCell(
            'lsl_clock',
            i,
            double.parse(adjustedTimestamps[j]) - deviceAdjustments[source]!,
          );
          j++;
        }
      }

      // Yield control periodically
      if (index % 10 == 0) {
        await Future.delayed(const Duration(microseconds: 1));
      }
    }

    return csvData;
  }
}
