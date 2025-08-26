// lib/transports/lsl/isolate/isolate_manager.dart

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:collection/collection.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/framework.dart';
import 'package:synchronized/synchronized.dart';

/// Configuration for isolate workers
class IsolateWorkerConfig {
  final String streamId;
  final StreamDataType dataType;
  final int channelCount;
  final double sampleRate;
  final bool useBusyWaitInlets;
  final bool useBusyWaitOutlets;
  final Duration pollingInterval;
  final SendPort mainSendPort;

  // For outlets
  final int? outletAddress;

  // For inlets
  final List<int>? inletAddresses;

  IsolateWorkerConfig({
    required this.streamId,
    required this.dataType,
    required this.channelCount,
    required this.sampleRate,
    required this.useBusyWaitInlets,
    required this.useBusyWaitOutlets,
    required this.pollingInterval,
    required this.mainSendPort,
    this.outletAddress,
    this.inletAddresses,
  });
}

/// Message sent from isolate to main
class IsolateDataMessage {
  final String streamId;
  final String messageId;
  final DateTime timestamp;
  final List<dynamic> data;
  final String? sourceId;
  final double? lslTimestamp;
  final double? lslTimeCorrection;

  IsolateDataMessage({
    required this.streamId,
    required this.messageId,
    required this.timestamp,
    required this.data,
    this.sourceId,
    this.lslTimestamp,
    this.lslTimeCorrection,
  });

  Map<String, dynamic> toMap() => {
    'streamId': streamId,
    'messageId': messageId,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
    'sourceId': sourceId,
    'lslTimestamp': lslTimestamp,
    'lslTimeCorrection': lslTimeCorrection,
  };

  factory IsolateDataMessage.fromMap(Map<String, dynamic> map) {
    return IsolateDataMessage(
      streamId: map['streamId'] as String,
      messageId: map['messageId'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      data: map['data'] as List<dynamic>,
      sourceId: map['sourceId'] as String?,
      lslTimestamp: map['lslTimestamp'] as double?,
      lslTimeCorrection: map['lslTimeCorrection'] as double?,
    );
  }
}

/// Manages isolates for LSL stream I/O with proper lifecycle
class IsolateStreamManager {
  final String streamId;
  final StreamDataType dataType;
  final bool useIsolates;
  final bool useBusyWaitInlets;
  final bool useBusyWaitOutlets;

  Isolate? _outletIsolate;
  Isolate? _inletIsolate;
  SendPort? _outletSendPort;
  SendPort? _inletSendPort;
  ReceivePort? _outletReceivePort;
  ReceivePort? _inletReceivePort;

  final _outletReady = Completer<void>();
  final _inletReady = Completer<void>();

  final StreamController<IsolateDataMessage> _incomingDataController =
      StreamController<IsolateDataMessage>.broadcast();

  Stream<IsolateDataMessage> get incomingData => _incomingDataController.stream;

  IsolateStreamManager({
    required this.streamId,
    required this.dataType,
    this.useIsolates = true,
    required this.useBusyWaitInlets,
    required this.useBusyWaitOutlets,
  });

  /// Creates outlet isolate for sending data
  Future<void> createOutletIsolate({
    required LSLStreamInfo streamInfo,
    required double sampleRate,
    required int channelCount,
    Duration? pollingInterval,
  }) async {
    if (!useIsolates) {
      // Direct mode - no isolate
      return;
    }

    _outletReceivePort = ReceivePort();

    final config = IsolateWorkerConfig(
      streamId: streamId,
      dataType: dataType,
      channelCount: channelCount,
      sampleRate: sampleRate,
      useBusyWaitInlets: useBusyWaitInlets,
      useBusyWaitOutlets: useBusyWaitOutlets,
      pollingInterval: pollingInterval ?? Duration(microseconds: 10),
      mainSendPort: _outletReceivePort!.sendPort,
      outletAddress: streamInfo.streamInfo.address,
    );

    _outletReceivePort!.listen((message) {
      if (message is SendPort) {
        _outletSendPort = message;
        if (!_outletReady.isCompleted) {
          _outletReady.complete();
        }
      } else if (message is LogRecord) {
        Log.logIsolateMessage(message);
      } else if (message is Map<String, dynamic>) {
        // Handle status messages from outlet isolate
        logger.fine('Outlet isolate message: $message');
      }
    });

    _outletIsolate = await Isolate.spawn(_outletWorker, config);
    await _outletReady.future;
  }

  /// Creates inlet isolate for receiving data
  Future<void> createInletIsolate({
    required List<LSLStreamInfo> streamInfos,
    Duration? pollingInterval,
  }) async {
    if (!useIsolates || streamInfos.isEmpty) {
      return;
    }

    _inletReceivePort = ReceivePort();

    final config = IsolateWorkerConfig(
      streamId: streamId,
      dataType: dataType,
      channelCount: streamInfos.first.channelCount,
      sampleRate: streamInfos.first.sampleRate,
      useBusyWaitInlets: useBusyWaitInlets,
      useBusyWaitOutlets: useBusyWaitOutlets,
      pollingInterval: pollingInterval ?? Duration(microseconds: 100),
      mainSendPort: _inletReceivePort!.sendPort,
      inletAddresses:
          streamInfos
              .map((streamInfo) => streamInfo.streamInfo.address)
              .toList(),
    );

    _inletReceivePort!.listen((message) {
      if (message is SendPort) {
        _inletSendPort = message;
        if (!_inletReady.isCompleted) {
          _inletReady.complete();
        }
      } else if (message is LogRecord) {
        Log.logIsolateMessage(message);
      } else if (message is List) {
        // Handle batch of samples
        logger.finest(
          'Isolate manager received batch of ${message.length} samples',
        );
        for (final item in message) {
          if (item is Map<String, dynamic>) {
            final dataMessage = IsolateDataMessage.fromMap(item);
            logger.finest('Processing isolate data: ${dataMessage.data}');
            _incomingDataController.add(dataMessage);
          }
        }
      }
    });

    _inletIsolate = await Isolate.spawn(_inletWorker, config);
    await _inletReady.future;
  }

  /// Send data through outlet (if using isolates)
  Future<void> sendData(List<dynamic> data) async {
    if (!useIsolates) {
      // Direct mode handled by stream
      return;
    }

    await _outletReady.future;
    _outletSendPort?.send({'type': 'data', 'payload': data});
  }

  /// Start processing
  Future<void> start() async {
    if (!useIsolates) return;

    if (_outletSendPort != null) {
      await _outletReady.future;
      _outletSendPort!.send({'type': 'start'});
    }

    if (_inletSendPort != null) {
      await _inletReady.future;
      _inletSendPort!.send({'type': 'start'});
    }
  }

  /// Stop processing
  Future<void> stop() async {
    if (!useIsolates) return;

    _outletSendPort?.send({'type': 'stop'});
    _inletSendPort?.send({'type': 'stop'});
  }

  /// Clean up resources
  Future<void> dispose() async {
    await stop();

    // Give isolates a moment to process stop messages and cancel timers
    await Future.delayed(Duration(milliseconds: 100));

    _outletIsolate?.kill(priority: Isolate.immediate);
    _inletIsolate?.kill(priority: Isolate.immediate);

    _outletReceivePort?.close();
    _inletReceivePort?.close();

    await _incomingDataController.close();
  }

  // Worker functions for isolates
  static void _outletWorker(IsolateWorkerConfig config) async {
    final receivePort = ReceivePort();
    config.mainSendPort.send(receivePort.sendPort);
    Log.sendPort = config.mainSendPort;

    logger.info('Outlet isolate for stream ${config.streamId} started');

    final outlet = _createOutlet(config);

    logger.info(
      'Outlet isolate created for stream ${config.streamId} ${config.dataType}',
    );

    bool running = false;
    Timer? timer;
    int sampleCounter = 0;

    Completer<void>? completer;

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String;

        switch (type) {
          case 'start':
            running = true;
            // For coordination streams, we only send on demand
            if (config.sampleRate <= 0) {
              return;
            }
            if (completer == null || completer!.isCompleted) {
              completer = Completer<void>();
            }

            if (config.useBusyWaitOutlets) {
              _startBusyWaitOutlet(config, outlet, receivePort, completer!);
            } else {
              // Normal timer-based sending for coordination
              final interval = Duration(
                microseconds: (1000000 / config.sampleRate).round(),
              );
              timer = Timer.periodic(interval, (_) {
                if (!running) {
                  timer?.cancel();
                  return;
                }
                // Auto-generate samples if needed
                _generateAndSendSample(outlet, config, sampleCounter++);
              });
            }
            break;

          case 'stop':
            if (completer != null && !completer!.isCompleted) {
              completer?.complete();
              completer = null;
            }
            running = false;
            timer?.cancel();
            break;

          case 'data':
            // On-demand data sending
            final payload = message['payload'] as List<dynamic>;
            outlet.pushSampleSync(payload);
            break;
        }
      }
    });
  }

  static void _inletWorker(IsolateWorkerConfig config) async {
    final receivePort = ReceivePort();
    config.mainSendPort.send(receivePort.sendPort);

    Log.sendPort = config.mainSendPort;
    logger.info('Inlet isolate for stream ${config.streamId} started');

    final inlets = _createInlets(config);

    final List<double> timeCorrections = List.filled(
      inlets.length,
      0.0,
      growable: true,
    );
    final Lock inletsLock = Lock();
    final Lock timeCorrectionsLock = Lock();
    final MultiLock inletAddRemoveLock = MultiLock(
      locks: [inletsLock, timeCorrectionsLock],
    );
    logger.info(
      'Inlet isolate created ${inlets.length} inlets for stream '
      '${config.streamId}. Fetching initial time corrections...',
    );
    await _updateTimeCorrections(inlets, timeCorrections, timeCorrectionsLock);
    _lastTimeCorrectionUpdate.start();
    logger.info(
      'Initial time corrections for stream ${config.streamId}: '
      '$timeCorrections',
    );
    bool running = false;
    Timer? timer;
    final bufferLock = Lock();
    final buffer = ListQueue<Map<String, dynamic>>();
    Completer<void>? completer;
    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String;

        switch (type) {
          case 'start':
            running = true;
            if (completer == null || completer!.isCompleted) {
              completer = Completer<void>();
            }

            if (config.useBusyWaitInlets) {
              _startBusyWaitInlets(
                config,
                inlets,
                timeCorrections,
                buffer,
                completer!,
                bufferLock,
                inletsLock,
                timeCorrectionsLock,
              );
            } else {
              // Normal polling for coordination streams
              timer = Timer.periodic(config.pollingInterval, (_) async {
                if (!running) {
                  timer?.cancel();
                  return;
                }

                await inletsLock.synchronized(() async {
                  _pollInlets(
                    config,
                    inlets,
                    buffer,
                    timeCorrections,
                    bufferLock,
                    timeCorrectionsLock,
                  );
                });

                // Send buffered data periodically
                if (buffer.isNotEmpty) {
                  await bufferLock.synchronized(() {
                    if (buffer.isNotEmpty) {
                      config.mainSendPort.send(List.from(buffer));
                      buffer.clear();
                    }
                  });
                }
              });
            }
            break;

          case 'stop':
            running = false;
            if (completer != null && !completer!.isCompleted) {
              completer?.complete();
              completer = null;
            }
            _lastTimeCorrectionUpdate.stop();
            timer?.cancel();

            // Send remaining buffered data
            await bufferLock.synchronized(() {
              if (buffer.isNotEmpty) {
                config.mainSendPort.send(List.from(buffer));
                buffer.clear();
              }
            });
            break;
          case 'addInlet':
            final addr = message['address'] as int;
            final newInlet = _createInletFromAddr(addr, config.dataType);
            await inletAddRemoveLock.synchronized(() {
              inlets.add(newInlet);
              timeCorrections.add(0.0);
            });
            logger.info('Added new inlet for stream ${config.streamId}');
            break;
          case 'removeInlet':
            final addr = message['address'] as int;
            await inletAddRemoveLock.synchronized(() {
              int? index;
              inlets.whereIndexed((i, inlet) {
                if (inlet.streamInfo.streamInfo.address == addr) {
                  index = i;
                  return true;
                }
                return false;
              });
              if (index != null) {
                inlets[index!].destroy();
                inlets.removeAt(index!);
                timeCorrections.removeAt(index!);
              }
            });
            logger.info('Removed inlet for stream ${config.streamId}');
            break;
        }
      }
    });
  }

  static LSLOutlet _createOutlet(IsolateWorkerConfig config) {
    final streamInfo = LSLStreamInfo.fromStreamInfoAddr(config.outletAddress!);
    return LSLOutlet(streamInfo, useIsolates: false)..create();
  }

  static List<LSLInlet> _createInlets(IsolateWorkerConfig config) {
    return config.inletAddresses!.map((addr) {
      return _createInletFromAddr(addr, config.dataType);
    }).toList();
  }

  static LSLInlet _createInletFromAddr(
    int streamInfoAddr,
    StreamDataType dataType,
  ) {
    final streamInfo = LSLStreamInfo.fromStreamInfoAddr(streamInfoAddr);
    final inlet = _createTypedInlet(streamInfo, dataType);
    inlet.create();
    return inlet;
  }

  static LSLInlet _createTypedInlet(
    LSLStreamInfo streamInfo,
    StreamDataType dataType,
  ) {
    // Create inlet with proper type based on dataType
    switch (dataType) {
      case StreamDataType.float32:
      case StreamDataType.double64:
        return LSLInlet<double>(streamInfo, useIsolates: false);
      case StreamDataType.int8:
      case StreamDataType.int16:
      case StreamDataType.int32:
      case StreamDataType.int64:
        return LSLInlet<int>(streamInfo, useIsolates: false);
      case StreamDataType.string:
        return LSLInlet<String>(streamInfo, useIsolates: false);
    }
  }

  static void _generateAndSendSample(
    LSLOutlet outlet,
    IsolateWorkerConfig config,
    int counter,
  ) {
    // Generate sample based on data type
    final sample = List.generate(config.channelCount, (i) {
      switch (config.dataType) {
        case StreamDataType.float32:
        case StreamDataType.double64:
          if (i == 0) return counter.toDouble();
          return i * 0.1;
        case StreamDataType.int8:
        case StreamDataType.int16:
        case StreamDataType.int32:
        case StreamDataType.int64:
          if (i == 0) return counter;
          return i.round();
        case StreamDataType.string:
          if (i == 0) return counter.toString();
          return 'ch_$i';
      }
    });

    outlet.pushSampleSync(sample);
  }

  static Future<void> _updateTimeCorrections(
    List<LSLInlet> inlets,
    List<double> timeCorrections,
    Lock timeCorrectionsLock,
  ) async {
    if (_lastTimeCorrectionUpdate.elapsedMilliseconds < 5000) {
      // Limit updates to every 5 seconds
      return;
    }
    await timeCorrectionsLock.synchronized(() async {
      final List<Future<double>> futures = [];
      for (int i = 0; i < inlets.length; i++) {
        try {
          futures.add(inlets[i].getTimeCorrection(timeout: 1.0));
        } catch (e) {
          logger.warning('Error updating time correction: $e');
        }
      }
      final results = await Future.wait(futures);
      for (int i = 0; i < results.length; i++) {
        timeCorrections[i] = results[i];
      }
    });
    _lastTimeCorrectionUpdate.reset();
  }

  static final Stopwatch _lastTimeCorrectionUpdate = Stopwatch();

  static Future<void> _pollInlets(
    IsolateWorkerConfig config,
    List<LSLInlet> inlets,
    ListQueue<Map<String, dynamic>> buffer,
    List<double> timeCorrections,
    Lock bufferLock,
    Lock timeCorrectionsLock,
  ) async {
    int index = 0;
    for (final inlet in inlets) {
      try {
        final sample = inlet.pullSampleSync(timeout: 0.0);

        if (sample.isNotEmpty) {
          final message = IsolateDataMessage(
            streamId: config.streamId,
            messageId: generateUid(),
            timestamp: DateTime.now(),
            data: sample.data,
            sourceId: inlet.streamInfo.sourceId,
            lslTimestamp: sample.timestamp,
            lslTimeCorrection: timeCorrections[index++],
          );

          await bufferLock.synchronized(() {
            buffer.add(message.toMap());
          });
        }
      } catch (e) {
        // Log but continue polling other inlets
        logger.warning('Error polling inlet: $e');
      }
    }
  }

  static void _startBusyWaitOutlet(
    IsolateWorkerConfig config,
    LSLOutlet outlet,
    ReceivePort receivePort,
    Completer<void> completer,
  ) {
    // Use runPreciseInterval for busy-wait timing
    final intervalMicros = (1000000 / config.sampleRate).round();
    final completer = Completer<void>();
    int counter = 0;

    // receivePort.listen((message) {
    //   if (message is Map<String, dynamic> && message['type'] == 'stop') {
    //     completer.complete();
    //   }
    // });

    runPreciseIntervalAsync(
      Duration(microseconds: intervalMicros),
      (state) {
        _generateAndSendSample(outlet, config, counter++);
        return state;
      },
      completer: completer,
      state: null,
      startBusyAt: Duration(microseconds: (intervalMicros * 0.99).round()),
    );
  }

  static Future<void> _startBusyWaitInlets(
    IsolateWorkerConfig config,
    List<LSLInlet> inlets,
    List<double> timeCorrections,
    ListQueue<Map<String, dynamic>> buffer,
    Completer<void> completer,
    Lock bufferLock,
    Lock inletsLock,
    Lock timeCorrectionsLock,
  ) async {
    // High-frequency polling with busy-wait
    runPreciseIntervalAsync(
      config.pollingInterval,
      (state) async {
        inletsLock.synchronized(() async {
          await _pollInlets(
            config,
            inlets,
            buffer,
            timeCorrections,
            bufferLock,
            timeCorrectionsLock,
          );
        });

        // Send buffer when it reaches threshold
        bufferLock.synchronized(() {
          if (buffer.isNotEmpty) {
            config.mainSendPort.send(List.from(buffer));
            buffer.clear();
          }
        });

        return state;
      },
      completer: completer,
      state: null,
      startBusyAt: Duration(
        microseconds: (config.pollingInterval.inMicroseconds * 0.99).round(),
      ),
    );
  }
}
