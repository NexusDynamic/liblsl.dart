import 'dart:async';
import 'dart:isolate';

import 'package:dartframe/dartframe.dart';

import 'efficient_timing_analysis_service.dart';

/// Analysis progress update
class AnalysisProgress {
  final String stage;
  final double progress; // 0.0 to 1.0
  final String? details;

  const AnalysisProgress({
    required this.stage,
    required this.progress,
    this.details,
  });
}

/// Analysis request
class AnalysisRequest {
  final DataFrame data;
  final bool includeInterSampleIntervals;
  final bool includeLatencies;

  const AnalysisRequest({
    required this.data,
    this.includeInterSampleIntervals = true,
    this.includeLatencies = true,
  });
}

/// Analysis result
class AnalysisResult {
  final List<InterSampleIntervalResult> intervalResults;
  final List<LatencyResult> latencyResults;

  const AnalysisResult({
    required this.intervalResults,
    required this.latencyResults,
  });
}

/// Message types for analysis isolate communication
enum AnalysisMessageType { startAnalysis, progress, result, error }

/// Message structure for analysis isolate communication
class AnalysisIsolateMessage {
  final AnalysisMessageType type;
  final dynamic data;

  const AnalysisIsolateMessage(this.type, this.data);
}

/// Background analysis processor service
class BackgroundAnalysisService {
  static Future<AnalysisResult> performAnalysisInBackground({
    required DataFrame data,
    required Function(AnalysisProgress) onProgress,
    bool includeInterSampleIntervals = true,
    bool includeLatencies = true,
  }) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _analysisIsolateEntryPoint,
      receivePort.sendPort,
    );

    final completer = Completer<AnalysisResult>();
    SendPort? isolateSendPort;

    receivePort.listen((message) {
      if (message is SendPort) {
        // This is the initial SendPort from the isolate
        isolateSendPort = message;
        // Send the analysis request
        isolateSendPort!.send(
          AnalysisIsolateMessage(
            AnalysisMessageType.startAnalysis,
            AnalysisRequest(
              data: data,
              includeInterSampleIntervals: includeInterSampleIntervals,
              includeLatencies: includeLatencies,
            ),
          ),
        );
      } else if (message is AnalysisIsolateMessage) {
        switch (message.type) {
          case AnalysisMessageType.progress:
            onProgress(message.data as AnalysisProgress);
            break;
          case AnalysisMessageType.result:
            completer.complete(message.data as AnalysisResult);
            receivePort.close();
            isolate.kill();
            break;
          case AnalysisMessageType.error:
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

  static void _analysisIsolateEntryPoint(SendPort mainSendPort) async {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    await for (final message in receivePort) {
      if (message is AnalysisIsolateMessage &&
          message.type == AnalysisMessageType.startAnalysis) {
        try {
          final request = message.data as AnalysisRequest;
          final result = await _performAnalysis(request, (progress) {
            mainSendPort.send(
              AnalysisIsolateMessage(AnalysisMessageType.progress, progress),
            );
          });
          mainSendPort.send(
            AnalysisIsolateMessage(AnalysisMessageType.result, result),
          );
        } catch (e) {
          mainSendPort.send(
            AnalysisIsolateMessage(AnalysisMessageType.error, e.toString()),
          );
        }
        break;
      }
    }
  }

  static Future<AnalysisResult> _performAnalysis(
    AnalysisRequest request,
    Function(AnalysisProgress) onProgress,
  ) async {
    final service = EfficientTimingAnalysisService();

    onProgress(
      const AnalysisProgress(
        stage: 'Initializing',
        progress: 0.0,
        details: 'Starting timing analysis...',
      ),
    );

    List<InterSampleIntervalResult> intervalResults = [];
    List<LatencyResult> latencyResults = [];

    // Calculate inter-sample intervals
    if (request.includeInterSampleIntervals) {
      onProgress(
        const AnalysisProgress(
          stage: 'Inter-sample Intervals',
          progress: 0.1,
          details: 'Calculating inter-sample intervals...',
        ),
      );

      intervalResults = await _calculateIntervalsWithProgress(
        service,
        request.data,
        onProgress,
      );

      onProgress(
        const AnalysisProgress(
          stage: 'Inter-sample Intervals',
          progress: 0.45,
          details: 'Inter-sample interval analysis complete.',
        ),
      );
    }

    // Calculate latencies
    if (request.includeLatencies) {
      onProgress(
        const AnalysisProgress(
          stage: 'Latency Analysis',
          progress: 0.5,
          details: 'Calculating latencies between devices...',
        ),
      );

      latencyResults = await _calculateLatenciesWithProgress(
        service,
        request.data,
        onProgress,
      );

      onProgress(
        const AnalysisProgress(
          stage: 'Latency Analysis',
          progress: 0.95,
          details: 'Latency analysis complete.',
        ),
      );
    }

    onProgress(
      const AnalysisProgress(
        stage: 'Complete',
        progress: 1.0,
        details: 'Analysis completed successfully!',
      ),
    );

    return AnalysisResult(
      intervalResults: intervalResults,
      latencyResults: latencyResults,
    );
  }

  static Future<List<InterSampleIntervalResult>>
  _calculateIntervalsWithProgress(
    EfficientTimingAnalysisService service,
    DataFrame data,
    Function(AnalysisProgress) onProgress,
  ) async {
    final results = <InterSampleIntervalResult>[];
    final uniqueReporters = data['reportingDeviceId'].unique();
    final totalDevices = uniqueReporters.length;

    for (int deviceIdx = 0; deviceIdx < totalDevices; deviceIdx++) {
      final deviceId = uniqueReporters[deviceIdx];
      if (deviceId == null || deviceId.isEmpty) continue;

      final progress = 0.1 + (deviceIdx / totalDevices) * 0.35;
      onProgress(
        AnalysisProgress(
          stage: 'Inter-sample Intervals',
          progress: progress,
          details:
              'Processing device $deviceId (${deviceIdx + 1}/$totalDevices)...',
        ),
      );

      // Get indices for samples sent by this device
      final deviceIndices = data['reportingDeviceId'].getIndicesWhere(
        (val) => val == deviceId,
      );
      final sentIndices = data['event_type'].getIndicesWhere(
        (val) => val == EfficientTimingAnalysisService.eventTypeSampleSent,
      );

      // Find intersection of device samples that were sent
      final sentByDeviceIndices = deviceIndices
          .toSet()
          .intersection(sentIndices.toSet())
          .toList();

      if (sentByDeviceIndices.length < 2) continue;

      // Sort by index to maintain temporal order
      sentByDeviceIndices.sort();

      // Extract timestamps for these samples
      final timestamps = data['lsl_clock'].selectByIndices(sentByDeviceIndices);

      final intervals = <double>[];
      for (int i = 1; i < timestamps.data.length; i++) {
        final interval =
            ((timestamps.data[i] as double) -
                (timestamps.data[i - 1] as double)) *
            1000;
        intervals.add(interval);
      }

      if (intervals.isNotEmpty) {
        results.add(
          service.calculateIntervalStats(deviceId as String, intervals),
        );
      }

      // Yield control periodically
      if (deviceIdx % 5 == 0) {
        await Future.delayed(const Duration(microseconds: 1));
      }
    }

    return results;
  }

  static Future<List<LatencyResult>> _calculateLatenciesWithProgress(
    EfficientTimingAnalysisService service,
    DataFrame data,
    Function(AnalysisProgress) onProgress,
  ) async {
    final results = <LatencyResult>[];
    final uniqueSources = data['sourceId'].unique();
    final uniqueReporters = data['reportingDeviceId'].unique();
    final totalSources = uniqueSources.length;

    for (int sourceIdx = 0; sourceIdx < totalSources; sourceIdx++) {
      final sourceId = uniqueSources[sourceIdx];
      if (sourceId == null || sourceId.isEmpty) continue;

      final progress = 0.5 + (sourceIdx / totalSources) * 0.45;
      onProgress(
        AnalysisProgress(
          stage: 'Latency Analysis',
          progress: progress,
          details:
              'Processing source $sourceId (${sourceIdx + 1}/$totalSources)...',
        ),
      );

      // Get sent samples for this source
      final sourceIndices = data['sourceId'].getIndicesWhere(
        (val) => val == sourceId,
      );
      final sentIndices = data['event_type'].getIndicesWhere(
        (val) => val == EfficientTimingAnalysisService.eventTypeSampleSent,
      );
      final sentBySourceIndices = sourceIndices
          .toSet()
          .intersection(sentIndices.toSet())
          .toList();

      if (sentBySourceIndices.isEmpty) continue;

      // Get sent data
      final sentCounters = data['counter'].selectByIndices(sentBySourceIndices);
      final sentTimestamps = data['lsl_clock'].selectByIndices(
        sentBySourceIndices,
      );
      final sentDevices = data['reportingDeviceId'].selectByIndices(
        sentBySourceIndices,
      );

      // For each receiving device
      for (final receivingDeviceId in uniqueReporters) {
        if (receivingDeviceId == null || receivingDeviceId.isEmpty) continue;

        // Get the actual sender device for this source
        final senderDevice = sentDevices.data.isNotEmpty
            ? sentDevices.data.first as String
            : '';
        if (senderDevice.isEmpty) continue;

        // Get received samples for this source by this device
        final receiverIndices = data['reportingDeviceId'].getIndicesWhere(
          (val) => val == receivingDeviceId,
        );
        final receivedIndices = data['event_type'].getIndicesWhere(
          (val) =>
              val == EfficientTimingAnalysisService.eventTypeSampleReceived,
        );
        final receivedByDeviceIndices = sourceIndices
            .toSet()
            .intersection(receiverIndices.toSet())
            .intersection(receivedIndices.toSet())
            .toList();

        if (receivedByDeviceIndices.isEmpty) continue;

        // Get received data
        final receivedCounters = data['counter'].selectByIndices(
          receivedByDeviceIndices,
        );
        final receivedTimestamps = data['lsl_clock'].selectByIndices(
          receivedByDeviceIndices,
        );

        // Match sent and received samples by counter
        final latencies = <double>[];

        for (int sentIdx = 0; sentIdx < sentCounters.data.length; sentIdx++) {
          final sentCounter = sentCounters.data[sentIdx] as int;
          final sentTime = sentTimestamps.data[sentIdx] as double;

          // Find matching received sample
          for (
            int recIdx = 0;
            recIdx < receivedCounters.data.length;
            recIdx++
          ) {
            final receivedCounter = receivedCounters.data[recIdx] as int;
            if (receivedCounter == sentCounter) {
              final receivedTime = receivedTimestamps.data[recIdx] as double;
              final latency = (receivedTime - sentTime) * 1000; // Convert to ms
              latencies.add(latency);
              break;
            }
          }
        }

        if (latencies.isNotEmpty) {
          results.add(
            service.calculateLatencyStats(
              senderDevice,
              receivingDeviceId as String,
              latencies,
            ),
          );
        }
      }

      // Yield control periodically
      if (sourceIdx % 3 == 0) {
        await Future.delayed(const Duration(microseconds: 1));
      }
    }

    return results;
  }
}
