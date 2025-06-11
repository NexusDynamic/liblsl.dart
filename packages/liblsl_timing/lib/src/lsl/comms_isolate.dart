import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import 'package:synchronized/synchronized.dart';

class IsolateConfig {
  final List<int> inletPtrs;
  final SendPort mainSendPort;
  final double? sampleRate;
  final String? sampleIdPrefix;

  /// Run time correction every N samples
  /// This is set to 0 by default, meaning no correction values are obtained.
  final int timeCorrectEveryN;
  
  /// Initial timeout for time correction (generous, e.g., 1.0 seconds)
  final double initialTimeCorrectionTimeout;
  
  /// Subsequent timeout for time correction (fast, e.g., 0.01 seconds)
  final double fastTimeCorrectionTimeout;

  IsolateConfig(
    this.inletPtrs,
    this.mainSendPort, {
    this.sampleRate,
    this.sampleIdPrefix,
    this.timeCorrectEveryN = 1, // Default to getting time correction on every sample
    this.initialTimeCorrectionTimeout = 1.0,
    this.fastTimeCorrectionTimeout = 0.01,
  });
}

class IsolateSampleMessage {
  final double timestamp;
  final double lslNow;
  final int dartNow;
  final int counter;
  final double? lslTimeCorrection; // Optional LSL time correction
  final String sampleId;
  final String sourceId;

  IsolateSampleMessage(
    this.timestamp,
    this.counter,
    this.sampleId,
    this.sourceId, {
    this.lslTimeCorrection,
  }) : lslNow = LSL.localClock(),
       dartNow = DateTime.now().microsecondsSinceEpoch;
}

/// Handle polling of multiple LSL inlets in a separate isolate for precise
/// timing
class InletManager {
  late Isolate consumerIsolate;
  late SendPort consumerSendPort;
  late ReceivePort mainReceivePort;

  Future<void> prepareInletConsumers(
    Iterable<LSLStreamInfo> streamInfos, {
    void Function(List<IsolateSampleMessage> message)? onSampleReceived,
    int timeCorrectEveryN = 0,
    double initialTimeCorrectionTimeout = 1.0,
    double fastTimeCorrectionTimeout = 0.01,
  }) async {
    final readyCompleter = Completer<void>();
    mainReceivePort = ReceivePort();

    consumerIsolate = await Isolate.spawn(
      inletConsumerWorker,
      IsolateConfig(
        streamInfos.map((streamInfo) => streamInfo.streamInfo.address).toList(),
        mainReceivePort.sendPort,
        timeCorrectEveryN: timeCorrectEveryN,
        initialTimeCorrectionTimeout: initialTimeCorrectionTimeout,
        fastTimeCorrectionTimeout: fastTimeCorrectionTimeout,
      ),
    );

    // Listen for timing data from isolate
    mainReceivePort.listen((dynamic message) {
      if (message is SendPort) {
        consumerSendPort = message;
        readyCompleter.complete();
      } else if (message is List<IsolateSampleMessage>) {
        // Handle the received timing data
        onSampleReceived?.call(message);
        if (kDebugMode) {
          // for (final sample in message) {
          //   // print(
          //   //   'Received sample: ${sample.sampleId}, '
          //   //   'Counter: ${sample.counter}, '
          //   //   'Timestamp: ${sample.timestamp}',
          //   // );
          // }
        }
      } else {
        // Handle unexpected message type
        if (kDebugMode) {
          print('Unexpected message from isolate: $message');
        }
      }
    });
    return readyCompleter.future;
  }

  Future<void> startInletConsumers() async {
    consumerSendPort.send('start');
  }

  Future<void> stopInletConsumers() async {
    consumerSendPort.send('stop');
    consumerIsolate.kill(priority: Isolate.immediate);
    mainReceivePort.close();
  }

  static void inletConsumerWorker(IsolateConfig config) async {
    final List<LSLStreamInfo> streamInfos = [];
    final List<LSLInlet> inlets = [];
    for (final ptr in config.inletPtrs) {
      final streamInfo = LSLStreamInfo.fromStreamInfoAddr(ptr);
      final inlet = LSLInlet(
        streamInfo,
        maxBuffer: 5,
        chunkSize: 1,
        recover: true,
        useIsolates: false,
      );
      streamInfos.add(streamInfo);
      await inlet.create();
      inlets.add(inlet);
    }
    final loopCompleter = Completer<void>();
    final loopStarter = Completer<void>();
    final mainSendPort = config.mainSendPort;
    final timeCorrectEveryN = config.timeCorrectEveryN;
    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (message == 'stop') {
        loopCompleter.complete();
      } else if (message == 'start') {
        loopStarter.complete();
      }
    });
    final int inletBufferSize = 100;
    final int bufferSize = inletBufferSize * inlets.length;
    final isolateMessageBuffer = List<IsolateSampleMessage>.filled(
      bufferSize,
      IsolateSampleMessage(0, 0, '', ''),
    );
    List<int> sampleCounters = List.filled(inlets.length, 0);
    List<double> inletTimeCorrections = List.filled(inlets.length, 0.0);
    List<bool> initialTimeCorrectionDone = List.filled(inlets.length, false);
    final Lock lock = Lock();
    
    // Perform initial time correction for all inlets with generous timeout
    for (int i = 0; i < inlets.length; i++) {
      try {
        if (kDebugMode) {
          print('Getting initial time correction for inlet ${inlets[i].streamInfo.sourceId}...');
        }
        inletTimeCorrections[i] = inlets[i].getTimeCorrectionSync(
          timeout: config.initialTimeCorrectionTimeout,
        );
        initialTimeCorrectionDone[i] = true;
        if (kDebugMode) {
          print('Initial time correction for ${inlets[i].streamInfo.sourceId}: ${inletTimeCorrections[i]}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Failed to get initial time correction for ${inlets[i].streamInfo.sourceId}: $e');
        }
        initialTimeCorrectionDone[i] = false;
      }
    }
    
    mainSendPort.send(receivePort.sendPort);
    await loopStarter.future;
    while (!loopCompleter.isCompleted) {
      for (final (inletIndex, inlet) in inlets.indexed) {
        LSLSample sample = inlet.pullSampleSync();

        if (sample.isNotEmpty) {
          await lock.synchronized(() {
            sampleCounters[inletIndex]++;
          });
          // Update time correction: use fast timeout for subsequent calls
          if (timeCorrectEveryN > 0 && 
              sampleCounters[inletIndex] % timeCorrectEveryN == 0) {
            try {
              // Use fast timeout for subsequent calls, or generous timeout if initial failed
              final timeout = initialTimeCorrectionDone[inletIndex] 
                  ? config.fastTimeCorrectionTimeout
                  : config.initialTimeCorrectionTimeout;
                  
              inletTimeCorrections[inletIndex] = inlet.getTimeCorrectionSync(
                timeout: timeout,
              );
              
              // Mark initial correction as done if it wasn't already
              if (!initialTimeCorrectionDone[inletIndex]) {
                initialTimeCorrectionDone[inletIndex] = true;
                if (kDebugMode) {
                  print('Successfully got time correction for ${inlet.streamInfo.sourceId}: ${inletTimeCorrections[inletIndex]}');
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print(
                  'Error getting time correction for inlet '
                  '${inlet.streamInfo.sourceId}: $e',
                );
              }
            }
          }
          // Extract the counter value (first channel)
          final counter = sample[0].toInt();
          final sampleId = '${inlet.streamInfo.sourceId}_$counter';
          final timestamp = sample.timestamp;
          final sampleMessage = IsolateSampleMessage(
            timestamp,
            counter,
            sampleId,
            inlet.streamInfo.sourceId,
            lslTimeCorrection: initialTimeCorrectionDone[inletIndex]
                ? inletTimeCorrections[inletIndex]
                : null,
          );
          final index =
              ((sampleCounters[inletIndex] - 1) % inletBufferSize) +
              inletIndex * inletBufferSize;
          isolateMessageBuffer[index] = sampleMessage;
          if (index == bufferSize - 1) {
            // Send the buffered messages every 100 samples
            mainSendPort.send(isolateMessageBuffer);
          }
        }
      }
      await Future.delayed(Duration.zero);
    }

    // Send remaining messages if any
    final index =
        ((sampleCounters[inlets.length - 1] - 1) % inletBufferSize) +
        (inlets.length - 1) * inletBufferSize;
    if (index != bufferSize - 1) {
      mainSendPort.send(isolateMessageBuffer.sublist(0, index));
    }

    for (final inlet in inlets) {
      inlet.destroy();
    }
  }
}

class LoopHelper {
  int sampleCounter = 0;
  SendPort? mainSendPort;
  LSLOutlet? outlet;
}

/// A single LSL outlet in an isolate which sends samples at a specified rate,
/// until stopped.
class OutletManager {
  late Isolate consumerIsolate;
  late SendPort consumerSendPort;
  late ReceivePort mainReceivePort;

  Future<void> prepareOutletProducer(
    LSLStreamInfo streamInfo,
    double sampleRate,
    String sampleIdPrefix, {
    void Function(List<IsolateSampleMessage> message)? onSampleSent,
  }) async {
    final readyCompleter = Completer<void>();
    mainReceivePort = ReceivePort();
    consumerIsolate = await Isolate.spawn(
      outletProducerWorker,
      IsolateConfig(
        [streamInfo.streamInfo.address],
        mainReceivePort.sendPort,
        sampleRate: sampleRate,
        sampleIdPrefix: sampleIdPrefix,
      ),
    );

    // Listen for timing data from isolate
    mainReceivePort.listen((dynamic message) {
      if (message is SendPort) {
        consumerSendPort = message;
        readyCompleter.complete();
      } else if (message is List<IsolateSampleMessage>) {
        // Handle the received timing data
        onSampleSent?.call(message);
      } else {
        // Handle unexpected message type
        if (kDebugMode) {
          print('Unexpected message from isolate: $message');
        }
      }
    });
    return readyCompleter.future;
  }

  Future<void> startOutletProducer() async {
    consumerSendPort.send('start');
  }

  Future<void> stopOutletProducer() async {
    consumerSendPort.send('stop');
    consumerIsolate.kill(priority: Isolate.immediate);
    mainReceivePort.close();
  }

  static void outletProducerWorker(IsolateConfig config) async {
    final streamInfo = LSLStreamInfo.fromStreamInfoAddr(config.inletPtrs[0]);
    final outlet = LSLOutlet(
      streamInfo,
      chunkSize: 1,
      maxBuffer: 5,
      useIsolates: false,
    );
    await outlet.create();
    final loopCompleter = Completer<void>();
    final loopStarter = Completer<void>();
    final mainSendPort = config.mainSendPort;
    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (kDebugMode) {
        print('Received message in outlet producer: $message');
      }
      if (message == 'stop') {
        loopCompleter.complete();
      } else if (message == 'start') {
        loopStarter.complete();
      }
    });

    mainSendPort.send(receivePort.sendPort);

    final sampleData = List<double>.generate(
      streamInfo.channelCount,
      (i) => i == 0 ? 0 : math.Random().nextDouble(),
    );
    final intervalMicroseconds = (1000000 / (config.sampleRate ?? 1)).round();
    final loopState = LoopHelper();
    loopState.sampleCounter = 0;
    loopState.outlet = outlet;
    final isolateMessageBuffer = List<IsolateSampleMessage>.filled(
      100,
      IsolateSampleMessage(0, 0, '', ''),
    );
    if (kDebugMode) {
      print(
        'Starting outlet producer with sample rate: ${config.sampleRate}, '
        'Interval: ${Duration(microseconds: intervalMicroseconds)} '
        'Buffer size: ${isolateMessageBuffer.length}',
      );
    }
    await loopStarter.future;
    if (kDebugMode) {
      print('Outlet producer started');
    }
    runPreciseInterval(
      Duration(microseconds: intervalMicroseconds),
      (LoopHelper state) {
        state.sampleCounter++;
        sampleData[0] = state.sampleCounter.toDouble();
        state.outlet!.pushSampleSync(sampleData);
        // pushed samples, but no verification
        final index = (state.sampleCounter - 1) % 100;
        final sampleId = '${config.sampleIdPrefix}${state.sampleCounter}';
        final sampleMessage = IsolateSampleMessage(
          LSL.localClock(),
          state.sampleCounter,
          sampleId,
          streamInfo.sourceId,
        );
        isolateMessageBuffer[index] = sampleMessage;
        // there is a cost here
        if (index == 99) {
          // Send the buffered messages every 100 samples
          mainSendPort.send(isolateMessageBuffer);
        }

        return state;
      },
      completer: loopCompleter,
      state: loopState,
      // this is based on the assumption of a 1000Hz sample rate
      // so we start busy waiting 0.1ms before the next sample
      startBusyAt: Duration(microseconds: intervalMicroseconds - 100),
    );

    // Clean up
    // send remaining messages if any
    final index = (loopState.sampleCounter - 1) % 100;
    if (index != 99) {
      mainSendPort.send(isolateMessageBuffer.sublist(0, index));
    }

    outlet.destroy();
  }
}
