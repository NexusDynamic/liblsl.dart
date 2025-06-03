// lib/src/tests/interactive_test.dart
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import '../config/constants.dart';
import 'base_test.dart';

class InteractiveTest extends BaseTest {
  // LSL resources
  LSLStreamInfo? _streamInfo;
  InteractiveInletManager? _inletManager;
  InteractiveOutletManager? _outletManager;

  final String _srcPrefix = 'Interactive_';

  // Callback for UI updates
  Function(String deviceId)? onMarkerReceived;

  // Test variables
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  InteractiveTest(super.config, super.timingManager);

  @override
  String get name => 'Interactive Test';

  @override
  TestType get testType => TestType.interactive;

  @override
  String get description =>
      'End-to-end timing test with user interaction and visual feedback';

  @override
  Future<void> setup() async {
    _isRunning = false;
    if (kDebugMode) {
      print('Setting up Interactive Test for device: $config');
    }

    // Create stream info for markers
    _streamInfo = await LSL.createStreamInfo(
      streamName: '${config.streamName}_Interactive',
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.int64,
      sourceId: '$_srcPrefix${config.deviceId}',
    );

    // Create outlet if this device is a producer
    if (config.isProducer) {
      _outletManager = InteractiveOutletManager();
      await _outletManager!.prepareOutlet(_streamInfo!);
    }

    // Find available streams
    await Future.delayed(const Duration(milliseconds: 500));
    final streams = await LSL.resolveStreams(
      waitTime: config.streamMaxWaitTimeSeconds,
      maxStreams: config.streamMaxStreams,
    );

    // Create inlet if this device is a consumer
    if (config.isConsumer && streams.isNotEmpty) {
      final interactiveStreams = streams.where(
        (s) =>
            s.streamName == '${config.streamName}_Interactive' &&
            s.sourceId.startsWith(_srcPrefix) &&
            s.streamType == LSLContentType.markers,
      );

      if (interactiveStreams.isNotEmpty) {
        _inletManager = InteractiveInletManager();
        await _inletManager!.prepareInletConsumers(
          interactiveStreams,
          onSampleReceived: (List<InteractiveSampleMessage> samples) async {
            // Record receive events and trigger UI callback
            for (final sample in samples) {
              timingManager.recordTimestampedEvent(
                EventType.markerReceived,
                sample.dartNow * 1e-6, // Convert to seconds
                lslClock: sample.lslNow,
                description: 'Interactive marker ${sample.markerId} received',
                metadata: {
                  'markerId': sample.markerId,
                  'sourceId': sample.sourceId,
                  'lslTimestamp': sample.timestamp,
                  'lslReceived': sample.lslNow,
                  'dartTimestamp': sample.dartNow,
                },
              );

              // Trigger UI update
              onMarkerReceived?.call(sample.sourceId);
            }
          },
        );
      }
    }

    timingManager.recordEvent(
      EventType.testStarted,
      description: 'Interactive test setup completed',
      metadata: {'config': config.toMap()},
      testType: testType.toString(),
    );
  }

  /// Send a marker when the button is pressed
  Future<void> sendMarker() async {
    if (!_isRunning || _outletManager == null) return;

    final markerId = DateTime.now().microsecondsSinceEpoch;

    // Record the event
    timingManager.recordEvent(
      EventType.markerSent,
      description: 'Interactive marker sent',
      metadata: {
        'markerId': markerId,
        'sourceId': '$_srcPrefix${config.deviceId}',
        'lslTimestamp': LSL.localClock(),
      },
    );

    // Send the marker
    await _outletManager!.sendMarker(markerId);
  }

  @override
  Future<void> run(Completer<void> completer) async {
    _isRunning = true;

    // Start receiving samples if this device is a consumer
    if (config.isConsumer && _inletManager != null) {
      _inletManager!.startInletConsumers();
    }

    // Wait for test completion
    await completer.future;

    _isRunning = false;

    // Stop receiving samples
    if (config.isConsumer && _inletManager != null) {
      await _inletManager!.stopInletConsumers();
    }
  }

  @override
  Future<void> cleanup() async {
    _isRunning = false;

    _outletManager?.cleanup();
    _inletManager?.cleanup();

    _streamInfo?.destroy();
    _streamInfo = null;
  }
}

// Custom inlet manager with busy-wait loop
class InteractiveInletManager {
  late Isolate consumerIsolate;
  late SendPort consumerSendPort;
  late ReceivePort mainReceivePort;

  Future<void> prepareInletConsumers(
    Iterable<LSLStreamInfo> streamInfos, {
    void Function(List<InteractiveSampleMessage> message)? onSampleReceived,
  }) async {
    final readyCompleter = Completer<void>();
    mainReceivePort = ReceivePort();

    consumerIsolate = await Isolate.spawn(
      interactiveInletWorker,
      InteractiveIsolateConfig(
        streamInfos.map((s) => s.streamInfo!.address).toList(),
        mainReceivePort.sendPort,
      ),
    );

    mainReceivePort.listen((dynamic message) {
      if (message is SendPort) {
        consumerSendPort = message;
        readyCompleter.complete();
      } else if (message is List<InteractiveSampleMessage>) {
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

  void cleanup() {
    consumerIsolate.kill(priority: Isolate.immediate);
    mainReceivePort.close();
  }

  static void interactiveInletWorker(InteractiveIsolateConfig config) async {
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

    // Use busy-wait loop for minimal latency
    // runPreciseInterval(
    //   const Duration(microseconds: 100), // Check every 100μs
    //   (Future<int> state) async {
    // for (final inlet in inlets) {
    //   try {
    //     final sample = await inlet.pullSample();
    //     if (sample.isNotEmpty) {
    //       final markerId = sample[0] as String;
    //       final sampleMessage = InteractiveSampleMessage(
    //         sample.timestamp,
    //         markerId,
    //         inlet.streamInfo.sourceId,
    //       );
    //       mainSendPort.send([sampleMessage]);
    //     }
    //   } catch (e) {
    //     // Continue polling
    //   }
    // }
    //     return state;
    //   },
    //   completer: loopCompleter,
    //   state: 0,
    //   startBusyAt: const Duration(
    //     microseconds: 50,
    //   ), // Start busy wait 50μs before next check
    // );
    while (!loopCompleter.isCompleted) {
      for (final inlet in inlets) {
        try {
          final sample = await inlet.pullSample();
          if (sample.isNotEmpty) {
            final markerId = sample[0] as int;
            final sampleMessage = InteractiveSampleMessage(
              sample.timestamp,
              markerId,
              inlet.streamInfo.sourceId,
            );
            mainSendPort.send([sampleMessage]);
          }
        } catch (e) {
          // Continue polling
        }
      }
      await Future.delayed(Duration.zero); // Yield to event loop
    }

    for (final inlet in inlets) {
      inlet.destroy();
    }
  }
}

// Custom outlet manager for sending markers
class InteractiveOutletManager {
  LSLIsolatedOutlet? _outlet;

  Future<void> prepareOutlet(LSLStreamInfo streamInfo) async {
    _outlet = LSLIsolatedOutlet(
      streamInfo: streamInfo,
      chunkSize: 1,
      maxBuffer: 5,
    );
    await _outlet!.create();
  }

  Future<void> sendMarker(int markerId) async {
    if (_outlet == null) return;

    // Send the marker ID as a string
    _outlet!.pushSampleSync([markerId]);
  }

  void cleanup() {
    _outlet?.destroy();
    _outlet = null;
  }
}

// Message types for interactive test
class InteractiveSampleMessage {
  final double timestamp;
  final double lslNow;
  final int dartNow;
  final int markerId;
  final String sourceId;

  InteractiveSampleMessage(this.timestamp, this.markerId, this.sourceId)
    : lslNow = LSL.localClock(),
      dartNow = DateTime.now().microsecondsSinceEpoch;
}

class InteractiveIsolateConfig {
  final List<int> inletPtrs;
  final SendPort mainSendPort;

  InteractiveIsolateConfig(this.inletPtrs, this.mainSendPort);
}
