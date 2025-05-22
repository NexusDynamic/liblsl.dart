import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';

class IsolateConfig {
  final List<int> inletPtrs;
  final SendPort mainSendPort;
  final double? sampleRate;
  final String? sampleIdPrefix;

  IsolateConfig(
    this.inletPtrs,
    this.mainSendPort, {
    this.sampleRate,
    this.sampleIdPrefix,
  });
}

class IsolateSampleMessage {
  final double timestamp;
  final double lslNow;
  final int dartNow;
  final int counter;
  final String sampleId;

  IsolateSampleMessage(this.timestamp, this.counter, this.sampleId)
    : lslNow = LSL.localClock(),
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
    void Function(IsolateSampleMessage message)? onSampleReceived,
  }) async {
    final readyCompleter = Completer<void>();
    mainReceivePort = ReceivePort();

    consumerIsolate = await Isolate.spawn(
      inletConsumerWorker,
      IsolateConfig(
        streamInfos
            .map((streamInfo) => streamInfo.streamInfo!.address)
            .toList(),
        mainReceivePort.sendPort,
      ),
    );

    // Listen for timing data from isolate
    mainReceivePort.listen((dynamic message) {
      if (message is SendPort) {
        consumerSendPort = message;
        readyCompleter.complete();
      } else if (message is IsolateSampleMessage) {
        // Handle the received timing data
        onSampleReceived?.call(message);
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
    final List<LSLIsolatedInlet> inlets = [];
    for (final ptr in config.inletPtrs) {
      final streamInfo = LSLStreamInfo.fromStreamInfoAddr(ptr);
      final inlet = LSLIsolatedInlet(
        streamInfo,
        maxBufferSize: 5,
        maxChunkLength: 1,
        recover: true,
      );
      streamInfos.add(streamInfo);
      await inlet.create();
      inlets.add(inlet);
    }
    final loopCompleter = Completer<void>();
    final loopStarter = Completer<void>();
    final mainSendPort = config.mainSendPort;
    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (message == 'stop') {
        loopCompleter.complete();
      } else if (message == 'start') {
        loopStarter.complete();
      }
    });

    mainSendPort.send(receivePort.sendPort);
    await loopStarter.future;
    while (!loopCompleter.isCompleted) {
      for (final inlet in inlets) {
        inlet
            .pullSample()
            .then((LSLSample sample) {
              if (sample.isNotEmpty) {
                // Extract the counter value (first channel)
                final counter = sample[0].toInt();
                final sampleId = '${inlet.streamInfo.sourceId}_$counter';
                final timestamp = sample.timestamp;
                final sampleMessage = IsolateSampleMessage(
                  timestamp,
                  counter,
                  sampleId,
                );

                mainSendPort.send(sampleMessage);
              }
            })
            .catchError((error) {
              // Handle error
              if (kDebugMode) {
                print('Error pulling sample: $error');
              }
            });
      }
      await Future.delayed(Duration.zero);
    }

    for (final inlet in inlets) {
      inlet.destroy();
    }
  }
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
    void Function(IsolateSampleMessage message)? onSampleSent,
  }) async {
    final readyCompleter = Completer<void>();
    mainReceivePort = ReceivePort();
    consumerIsolate = await Isolate.spawn(
      outletProducerWorker,
      IsolateConfig(
        [streamInfo.streamInfo!.address],
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
      } else if (message is IsolateSampleMessage) {
        // Handle the received timing data
        onSampleSent?.call(message);
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
    final outlet = LSLIsolatedOutlet(
      streamInfo: streamInfo,
      chunkSize: 1,
      maxBuffer: 5,
    );
    await outlet.create();
    final loopCompleter = Completer<void>();
    final loopStarter = Completer<void>();
    final mainSendPort = config.mainSendPort;
    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (message == 'stop') {
        loopCompleter.complete();
      } else if (message == 'start') {
        loopStarter.complete();
      }
    });

    mainSendPort.send(receivePort.sendPort);
    await loopStarter.future;
    int lastSendTime = 0;
    final sampleData = List<double>.generate(
      streamInfo.channelCount,
      (i) => i == 0 ? 0 : math.Random().nextDouble(),
    );
    final intervalMicroseconds = (1000000 / (config.sampleRate ?? 1)).round();
    int sampleCounter = 0;
    while (!loopCompleter.isCompleted) {
      if (DateTime.now().microsecondsSinceEpoch - lastSendTime <=
          intervalMicroseconds) {
        await Future.delayed(Duration.zero);
        continue;
      }
      lastSendTime = DateTime.now().microsecondsSinceEpoch;
      sampleCounter++;
      outlet
          .pushSample(sampleData)
          .then((_) {
            final sampleId = '${config.sampleIdPrefix}$sampleCounter';
            sampleData[0] = sampleCounter.toDouble();
            final sampleMessage = IsolateSampleMessage(
              LSL.localClock(),
              sampleCounter,
              sampleId,
            );
            mainSendPort.send(sampleMessage);
          })
          .catchError((error) {
            // Handle error
            if (kDebugMode) {
              print('Error pushing sample: $error');
            }
          });
    }

    outlet.destroy();
  }
}
