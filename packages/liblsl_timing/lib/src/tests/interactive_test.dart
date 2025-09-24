// lib/src/tests/interactive_test.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/data/timing_manager.dart';
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

  // Frame synchronization
  TickerProvider? _tickerProvider;
  Ticker? _frameTicker;
  bool _frameBasedMode = false;

  set tickerProvider(TickerProvider? provider) => _tickerProvider = provider;

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
      _outletManager = InteractiveOutletManager(timingManager);
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
          initialTimeCorrectionTimeout: 1.0,
          fastTimeCorrectionTimeout: 0.01,
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
                  'lslTimeCorrection': sample.lslTimeCorrection,
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

  /// Enable frame-based mode for reduced latency
  void enableFrameBasedMode() {
    if (_tickerProvider == null) return;

    _frameBasedMode = true;
    if (_outletManager != null) {
      _outletManager!.enableFrameBasedMode();
    }
  }

  /// Disable frame-based mode
  void disableFrameBasedMode() {
    _frameBasedMode = false;
    _frameTicker?.dispose();
    _frameTicker = null;
    if (_outletManager != null) {
      _outletManager!.disableFrameBasedMode();
    }
  }

  /// Send a marker when the button is pressed
  void sendMarker() {
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
        'frameBasedMode': _frameBasedMode,
      },
    );

    // Send the marker
    _outletManager!.sendMarker(markerId);
  }

  /// Send a marker synchronized to the next frame
  void sendMarkerOnNextFrame() {
    if (!_isRunning || _outletManager == null || _tickerProvider == null) {
      return;
    }

    if (_frameBasedMode) {
      _outletManager!.sendMarkerOnNextFrame();
    } else {
      sendMarker(); // Fallback to immediate sending
    }
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

    // Dispose frame ticker
    _frameTicker?.dispose();
    _frameTicker = null;

    _outletManager?.cleanup();
    _inletManager?.cleanup();

    _streamInfo?.destroy();
    _streamInfo = null;
  }
}

// Custom inlet manager with minimal latency approach
class InteractiveInletManager {
  final List<LSLInlet> _inlets = [];
  final List<double> _inletTimeCorrections = [];
  final List<bool> _initialTimeCorrectionDone = [];
  Timer? _pollingTimer;
  bool _isRunning = false;
  void Function(List<InteractiveSampleMessage> message)? _onSampleReceived;
  double _initialTimeCorrectionTimeout = 1.0;
  // double _fastTimeCorrectionTimeout = 0.01;

  Future<void> prepareInletConsumers(
    Iterable<LSLStreamInfo> streamInfos, {
    void Function(List<InteractiveSampleMessage> message)? onSampleReceived,
    double initialTimeCorrectionTimeout = 1.0,
    double fastTimeCorrectionTimeout = 0.01,
  }) async {
    _onSampleReceived = onSampleReceived;
    _initialTimeCorrectionTimeout = initialTimeCorrectionTimeout;
    // _fastTimeCorrectionTimeout = fastTimeCorrectionTimeout;

    // Create inlets directly in main isolate for minimal latency
    for (final streamInfo in streamInfos) {
      final inlet = LSLInlet(
        streamInfo,
        maxBuffer: 5,
        chunkSize: 1,
        recover: true,
        useIsolates: false, // Critical: no isolates for minimal latency
      );
      await inlet.create();
      _inlets.add(inlet);

      // Initialize time correction data
      _inletTimeCorrections.add(0.0);
      _initialTimeCorrectionDone.add(false);

      // Perform initial time correction with generous timeout
      try {
        if (kDebugMode) {
          print(
            'Getting initial time correction for interactive inlet ${inlet.streamInfo.sourceId}...',
          );
        }
        final timeCorrection = inlet.getTimeCorrectionSync(
          timeout: _initialTimeCorrectionTimeout,
        );
        _inletTimeCorrections[_inlets.length - 1] = timeCorrection;
        _initialTimeCorrectionDone[_inlets.length - 1] = true;
        if (kDebugMode) {
          print(
            'Initial time correction for ${inlet.streamInfo.sourceId}: $timeCorrection',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            'Failed to get initial time correction for ${inlet.streamInfo.sourceId}: $e',
          );
        }
      }
    }
  }

  Future<void> startInletConsumers() async {
    _isRunning = true;

    // Use high-frequency polling for minimal latency
    // This runs on the main isolate to reduce message-passing overhead
    _pollingTimer = Timer.periodic(const Duration(microseconds: 100), (_) {
      if (!_isRunning) return;

      final samples = <InteractiveSampleMessage>[];

      for (int i = 0; i < _inlets.length; i++) {
        final inlet = _inlets[i];
        try {
          // Use sync pull for minimal latency
          final sample = inlet.pullSampleSync();
          if (sample.isNotEmpty) {
            final markerId = sample[0] as int;
            final sampleMessage = InteractiveSampleMessage(
              sample.timestamp,
              markerId,
              inlet.streamInfo.sourceId,
              lslTimeCorrection: _initialTimeCorrectionDone[i]
                  ? _inletTimeCorrections[i]
                  : null,
            );
            samples.add(sampleMessage);
          }
        } catch (e) {
          // Continue polling on errors
        }
      }

      if (samples.isNotEmpty) {
        _onSampleReceived?.call(samples);
      }
    });
  }

  Future<void> stopInletConsumers() async {
    _isRunning = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void cleanup() {
    _isRunning = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    for (final inlet in _inlets) {
      inlet.destroy();
    }
    _inlets.clear();
  }
}

// Custom outlet manager for sending markers
class InteractiveOutletManager {
  LSLOutlet? _outlet;
  bool _frameBasedMode = false;
  int? _pendingMarkerId;
  TimingManager timingManager;

  InteractiveOutletManager(this.timingManager);

  Future<void> prepareOutlet(LSLStreamInfo streamInfo) async {
    _outlet = LSLOutlet(
      streamInfo,
      chunkSize: 1,
      maxBuffer: 5,
      useIsolates: false,
    );
    await _outlet!.create();
  }

  void enableFrameBasedMode() {
    _frameBasedMode = true;
  }

  void disableFrameBasedMode() {
    _frameBasedMode = false;
    _pendingMarkerId = null;
  }

  void sendMarker(int markerId) {
    if (_outlet == null) return;
    _outlet!.pushSampleSync([markerId]);
  }

  void sendMarkerOnNextFrame() {
    if (_outlet == null || !_frameBasedMode) return;

    final markerId = DateTime.now().microsecondsSinceEpoch;
    _pendingMarkerId = markerId;

    // Schedule frame callback for next frame
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (_pendingMarkerId == markerId) {
        _outlet!.pushSampleSync([markerId]);
        _pendingMarkerId = null;
      }
      // log event
      timingManager.recordEvent(
        EventType.markerSent,
        description: 'Interactive marker sent on next frame',
        metadata: {
          'markerId': markerId,
          'sourceId': _outlet!.streamInfo.sourceId,
          'frameBasedMode': _frameBasedMode,
        },
      );
    }, scheduleNewFrame: true);
  }

  void cleanup() {
    _pendingMarkerId = null;
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
  final double? lslTimeCorrection;

  InteractiveSampleMessage(
    this.timestamp,
    this.markerId,
    this.sourceId, {
    this.lslTimeCorrection,
  })  : lslNow = LSL.localClock(),
        dartNow = DateTime.now().microsecondsSinceEpoch;
}
