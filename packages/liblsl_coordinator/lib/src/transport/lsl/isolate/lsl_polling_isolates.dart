import 'dart:async';
import 'dart:isolate';
import 'package:liblsl/lsl.dart';
import 'package:synchronized/synchronized.dart';
import '../../../utils/logging.dart';
import '../config/lsl_stream_config.dart';
import '../config/lsl_channel_format.dart';
import '../../../session/stream_config.dart';
import 'lsl_isolate_controller.dart';

/// Inlet consumer isolate - receives streamInfo addresses and creates inlets dynamically
void lslInletConsumerIsolate(LSLInletIsolateParams params) async {
  try {
    print(
      'DEBUG ISOLATE: Inlet consumer isolate starting for node ${params.nodeId}',
    );

    if (params.sendPort == null) {
      print('DEBUG ISOLATE: ERROR - No SendPort provided to inlet isolate!');
      return;
    }

    // Setup isolate logging
    Log.sendPort = params.sendPort;

    final logger = Log.logger;
    logger.finest('Inlet consumer isolate starting for node ${params.nodeId}');

    print('DEBUG ISOLATE: Setting up communication');
    // Setup communication with main isolate
    final receivePort = ReceivePort();
    print('DEBUG ISOLATE: Sending receive port SendPort to main isolate');
    params.sendPort!.send(receivePort.sendPort);
    print('DEBUG ISOLATE: SendPort sent successfully');

    final Map<int, LSLInlet> inlets = {}; // Map streamInfo address to inlet
    final Map<int, double> timeCorrections = {};
    final lock = Lock();

    var isRunning = true;
    var config = params.config;
    var samplesProcessed = 0;
    var droppedSamples = 0;
    var lastStatsUpdate = DateTime.now();

    try {
      final exitCompleter = Completer<void>();
      Completer<void>? pauseCompleter;
      print('DEBUG ISOLATE: Setting up message listener');
      // Listen for commands from main isolate
      receivePort.listen((message) async {
        print('DEBUG ISOLATE: Received message: ${message.runtimeType}');
        if (message is IsolateMessage) {
          await _handleInletCommand(
            message,
            inlets,
            timeCorrections,
            lock,
            config,
            () => isRunning,
            (running, {paused = false}) {
              isRunning = running;
              if (paused) {
                // Create a new pause completer if we don't have one
                pauseCompleter ??= Completer<void>();
              } else {
                // Resume by completing the pause completer
                logger.finest('Received resume command, resuming polling');
                pauseCompleter?.complete();
                pauseCompleter = null;
              }
            },
            params.receiveOwnMessages,
            params.nodeId,
            exitCompleter,
            logger,
          );
        }
      });

      print('DEBUG ISOLATE: Starting polling loop');
      // Start the appropriate polling loop based on configuration
      while (!exitCompleter.isCompleted) {
        // Wait for resume if paused
        if (pauseCompleter != null) {
          await pauseCompleter!.future;
        }

        if (config.useBusyWait) {
          print('DEBUG ISOLATE: Using busy-wait polling loop');
          logger.finest('Starting busy-wait polling loop');
          await _busyWaitPollingLoop(params, inlets, config, () => isRunning, (
            processed,
            dropped,
          ) {
            samplesProcessed += processed;
            droppedSamples += dropped;

            // Send metrics periodically
            final now = DateTime.now();
            if (now.difference(lastStatsUpdate).inMilliseconds >= 1000) {
              if (params.sendPort != null) {
                _sendMetrics(
                  params.sendPort!,
                  samplesProcessed,
                  droppedSamples,
                  config.targetIntervalMicroseconds,
                );
              }
              lastStatsUpdate = now;
            }
          }, logger);
        } else {
          print('DEBUG ISOLATE: Using timer-based polling loop');
          logger.finest('Starting timer-based polling loop');

          await _timerBasedPollingLoop(
            params,
            inlets,
            config,
            () => isRunning,
            (processed, dropped) {
              samplesProcessed += processed;
              droppedSamples += dropped;
            },
            logger,
          );
        }
        // Check if we should exit
        if (exitCompleter.isCompleted) {
          isRunning = false;
          logger.finest('Exit command received, stopping polling loop');
          break;
        }
      }
    } catch (e, stackTrace) {
      print('DEBUG ISOLATE: Inlet isolate error: $e');
      print('DEBUG ISOLATE: Stack trace: $stackTrace');
      try {
        params.sendPort?.send(IsolateMessage.error('Inlet isolate error', e));
      } catch (sendError) {
        print('DEBUG ISOLATE: Failed to send error message: $sendError');
      }
    } finally {
      // Cleanup all inlets
      logger.finest('Cleaning up inlet isolate');

      await lock.synchronized(() async {
        for (final inlet in inlets.values) {
          try {
            await inlet.destroy();
          } catch (e) {
            logger.warning('Error destroying inlet: $e');
          }
        }
        inlets.clear();
      });

      receivePort.close();
    }
  } catch (e, stackTrace) {
    print('DEBUG ISOLATE: Inlet isolate outer error: $e');
    print('DEBUG ISOLATE: Stack trace: $stackTrace');
  }
}

/// Outlet producer isolate - receives outlet configs and creates outlets dynamically
void lslOutletProducerIsolate(LSLOutletIsolateParams params) async {
  try {
    print(
      'DEBUG ISOLATE: Outlet producer isolate starting for node ${params.nodeId}',
    );

    if (params.sendPort == null) {
      print('DEBUG ISOLATE: ERROR - No SendPort provided to isolate!');
      return;
    }

    // Setup isolate logging
    Log.sendPort = params.sendPort;

    final logger = Log.logger;
    logger.finest('Outlet producer isolate starting for node ${params.nodeId}');

    print('DEBUG ISOLATE: Setting up communication');
    // Setup communication
    final receivePort = ReceivePort();
    print('DEBUG ISOLATE: Sending receive port SendPort to main isolate');
    params.sendPort!.send(receivePort.sendPort);
    print('DEBUG ISOLATE: SendPort sent successfully');

    final Map<String, LSLOutlet> outlets = {}; // Map outlet ID to outlet
    var isRunning = true;

    print('DEBUG ISOLATE: Setting up message listener');
    // Listen for commands from main isolate
    receivePort.listen((message) async {
      print('DEBUG ISOLATE: Received message: ${message.runtimeType}');
      if (message is IsolateMessage) {
        await _handleOutletCommand(
          message,
          outlets,
          () => isRunning,
          (running) => isRunning = running,
          logger,
        );
      }
    });

    print('DEBUG ISOLATE: Starting main loop');
    // Keep isolate alive until stopped
    while (isRunning) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  } catch (e, stackTrace) {
    print('DEBUG ISOLATE: Outlet isolate error: $e');
    print('DEBUG ISOLATE: Stack trace: $stackTrace');
    try {
      params.sendPort?.send(IsolateMessage.error('Outlet isolate error', e));
    } catch (sendError) {
      print('DEBUG ISOLATE: Failed to send error message: $sendError');
    }
  } finally {
    print('DEBUG ISOLATE: Cleaning up isolate');
    // Note: outlets and receivePort are scoped within try block
    // Cleanup will be handled by isolate termination
  }
}

/// Handle commands sent to inlet isolate
Future<void> _handleInletCommand(
  IsolateMessage message,
  Map<int, LSLInlet> inlets,
  Map<int, double> timeCorrections,
  Lock lock,
  LSLPollingConfig config,
  bool Function() isRunning,
  void Function(bool, {bool paused}) setRunning,
  bool receiveOwnMessages,
  String nodeId,
  Completer<void> exitCompleter,
  logger,
) async {
  if (message.type == IsolateMessageType.command) {
    final command = IsolateCommand.values.firstWhere(
      (cmd) => cmd.name == message.data['command'],
    );

    switch (command) {
      case IsolateCommand.addInlets:
        await _addInlets(
          message.data['streamAddresses'] as List<int>,
          inlets,
          timeCorrections,
          lock,
          config,
          receiveOwnMessages,
          nodeId,
          logger,
        );
        break;

      case IsolateCommand.removeInlet:
        await _removeInlet(
          message.data['streamAddress'] as int,
          inlets,
          timeCorrections,
          lock,
          logger,
        );
        break;

      case IsolateCommand.stop:
        setRunning(false);
        logger.finest('Received stop command');
        exitCompleter.complete();
        break;

      case IsolateCommand.pause:
        setRunning(false, paused: true);
        logger.finest('Received pause command');
        break;

      case IsolateCommand.resume:
        setRunning(true, paused: false);
        logger.finest('received resume command');
        break;

      case IsolateCommand.updateConfig:
        // TODO: Update config on the fly
        break;

      default:
        logger.warning('Unknown inlet command: ${command.name}');
    }
  }
}

/// Handle commands sent to outlet isolate
Future<void> _handleOutletCommand(
  IsolateMessage message,
  Map<String, LSLOutlet> outlets,
  bool Function() isRunning,
  void Function(bool) setRunning,
  logger,
) async {
  if (message.type == IsolateMessageType.command) {
    final command = IsolateCommand.values.firstWhere(
      (cmd) => cmd.name == message.data['command'],
    );

    switch (command) {
      case IsolateCommand.addOutlet:
        await _addOutlet(
          message.data['outletId'] as String,
          message.data['streamConfig'] as Map<String, dynamic>,
          outlets,
          logger,
        );
        break;

      case IsolateCommand.removeOutlet:
        await _removeOutlet(
          message.data['outletId'] as String,
          outlets,
          logger,
        );
        break;

      case IsolateCommand.sendData:
        // Only send data if not paused
        if (isRunning()) {
          await _sendDataThroughOutlet(
            message.data['outletId'] as String,
            message.data['samples'] as List<LSLSample>, // Use LSLSample
            outlets,
            logger,
          );
        }
        break;

      case IsolateCommand.stop:
        setRunning(false);
        logger.finest('Received stop command');
        break;

      case IsolateCommand.pause:
        setRunning(false);
        logger.finest('Received pause command');
        break;

      case IsolateCommand.resume:
        setRunning(true);
        logger.finest('Received resume command');
        break;

      case IsolateCommand.waitForConsumer:
        final outletId = message.data['outletId'] as String;
        final timeout = (message.data['timeout'] as num?)?.toDouble() ?? 60.0;
        final result = await _waitForConsumer(
          outletId,
          timeout,
          outlets,
          logger,
        );
        // Send response back
        (message.data['sendPort'] as SendPort?)?.send(
          IsolateMessage.response({'result': result, 'outletId': outletId}),
        );
        break;

      case IsolateCommand.hasConsumers:
        final outletId = message.data['outletId'] as String;
        final result = await _hasConsumers(outletId, outlets, logger);
        // Send response back
        (message.data['sendPort'] as SendPort?)?.send(
          IsolateMessage.response({'result': result, 'outletId': outletId}),
        );
        break;

      default:
        logger.warning('Unknown outlet command: ${command.name}');
    }
  }
}

/// Add inlets from streamInfo addresses
Future<void> _addInlets(
  List<int> streamAddresses,
  Map<int, LSLInlet> inlets,
  Map<int, double> timeCorrections,
  Lock lock,
  LSLPollingConfig config,
  bool receiveOwnMessages,
  String nodeId,
  logger,
) async {
  await lock.synchronized(() async {
    for (final address in streamAddresses) {
      // Skip if we already have this inlet
      if (inlets.containsKey(address)) {
        continue;
      }

      try {
        // Reconstruct streamInfo from address
        final streamInfo = LSLStreamInfo.fromStreamInfoAddr(address);

        // Skip our own messages if configured
        if (!receiveOwnMessages && streamInfo.sourceId.contains(nodeId)) {
          // never destroy a streaminfo that is not owned by us
          // streamInfo.destroy();
          continue;
        }

        // Create inlet
        final inlet = await LSL.createInlet<dynamic>(
          streamInfo: streamInfo,
          maxBuffer: 10,
          chunkSize: 1,
          recover: true,
          useIsolates: config.useIsolatedInlets,
        );

        inlets[address] = inlet;
        timeCorrections[address] = 0.0;

        logger.finest(
          'Added inlet for stream address $address (${streamInfo.sourceId})',
        );
      } catch (e) {
        logger.severe('Failed to create inlet for address $address: $e');
      }
    }
  });
}

/// Remove inlet by streamInfo address
Future<void> _removeInlet(
  int streamAddress,
  Map<int, LSLInlet> inlets,
  Map<int, double> timeCorrections,
  Lock lock,
  logger,
) async {
  await lock.synchronized(() async {
    final inlet = inlets.remove(streamAddress);
    timeCorrections.remove(streamAddress);

    if (inlet != null) {
      try {
        await inlet.destroy();
        logger.finest('Removed inlet for stream address $streamAddress');
      } catch (e) {
        logger.warning('Error destroying inlet for address $streamAddress: $e');
      }
    }
  });
}

/// Add outlet from config
Future<void> _addOutlet(
  String outletId,
  Map<String, dynamic> streamConfigData,
  Map<String, LSLOutlet> outlets,
  logger,
) async {
  if (outlets.containsKey(outletId)) {
    logger.warning('Outlet $outletId already exists');
    return;
  }

  try {
    // Reconstruct stream config from data
    final streamConfig = LSLStreamConfigExtension.fromMap(streamConfigData);
    final streamInfo = await streamConfig.toStreamInfo();

    final outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: streamConfig.transportConfig.outletChunkSize,
      maxBuffer: streamConfig.transportConfig.maxOutletBuffer,
      useIsolates: streamConfig.pollingConfig.useIsolatedOutlets,
    );

    outlets[outletId] = outlet;
    logger.finest('Added outlet $outletId');
  } catch (e) {
    logger.severe('Failed to create outlet $outletId: $e');
  }
}

/// Remove outlet
Future<void> _removeOutlet(
  String outletId,
  Map<String, LSLOutlet> outlets,
  logger,
) async {
  final outlet = outlets.remove(outletId);

  if (outlet != null) {
    try {
      await outlet.destroy();
      logger.finest('Removed outlet $outletId');
    } catch (e) {
      logger.warning('Error destroying outlet $outletId: $e');
    }
  }
}

/// Send LSLSample(s) through specific outlet
Future<void> _sendDataThroughOutlet(
  String outletId,
  List<LSLSample> samples,
  Map<String, LSLOutlet> outlets,
  logger,
) async {
  final outlet = outlets[outletId];

  if (outlet != null) {
    try {
      // Send each sample through the outlet
      for (final sample in samples) {
        await outlet.pushSample(sample.data);
      }
    } catch (e) {
      logger.warning('Error sending data through outlet $outletId: $e');
    }
  } else {
    logger.warning('Outlet $outletId not found');
  }
}

/// Busy-wait polling loop - polls all managed inlets
Future<void> _busyWaitPollingLoop(
  LSLInletIsolateParams params,
  Map<int, LSLInlet> inlets,
  LSLPollingConfig config,
  bool Function() isRunning,
  void Function(int processed, int dropped) onStats,
  logger,
) async {
  final targetInterval = Duration(
    microseconds: config.targetIntervalMicroseconds,
  );
  var nextTargetTime = DateTime.now().add(targetInterval);

  while (isRunning()) {
    // final loopStart = DateTime.now();
    var samplesThisLoop = 0;
    var droppedThisLoop = 0;

    // Poll all inlets for samples
    for (final entry in Map.from(inlets).entries) {
      final address = entry.key;
      final inlet = entry.value;

      try {
        final sample = await inlet.pullSample(timeout: config.pullTimeout);
        if (sample.isNotEmpty) {
          samplesThisLoop++;
          logger.finest(
            'DEBUG: Received sample from ${inlet.streamInfo.sourceId}: ${sample.data.take(4).toList()}...',
          );

          // Send LSLSample to main isolate
          params.sendPort?.send(
            IsolateMessage.data({
              'streamAddress': address,
              'sourceId': inlet.streamInfo.sourceId,
              'sample': sample, // This is an LSLSample
              'timestamp': DateTime.now().microsecondsSinceEpoch,
            }),
          );
        }
      } catch (e) {
        logger.warning('Error polling inlet at address $address: $e');
        droppedThisLoop++;
      }
    }

    onStats(samplesThisLoop, droppedThisLoop);

    // Precise timing control with busy-wait
    final now = DateTime.now();
    if (now.isBefore(nextTargetTime)) {
      final remaining = nextTargetTime.difference(now);
      if (remaining.inMicroseconds > 100) {
        // Sleep for larger delays to avoid burning CPU
        await Future.delayed(remaining);
      } else {
        // Busy-wait for precise timing
        while (DateTime.now().isBefore(nextTargetTime)) {
          // Busy wait for precision
        }
      }
    }

    nextTargetTime = nextTargetTime.add(targetInterval);

    // Prevent drift by resetting if we're too far behind
    if (DateTime.now().isAfter(nextTargetTime.add(targetInterval))) {
      nextTargetTime = DateTime.now().add(targetInterval);
    }
  }
}

/// Timer-based polling loop - more relaxed timing
Future<void> _timerBasedPollingLoop(
  LSLInletIsolateParams params,
  Map<int, LSLInlet> inlets,
  LSLPollingConfig config,
  bool Function() isRunning,
  void Function(int processed, int dropped) onStats,
  logger,
) async {
  final interval = Duration(microseconds: config.targetIntervalMicroseconds);

  while (isRunning()) {
    var samplesThisLoop = 0;
    var droppedThisLoop = 0;

    // Poll all inlets for samples
    for (final entry in Map.from(inlets).entries) {
      final address = entry.key;
      final inlet = entry.value;

      try {
        final sample = await inlet.pullSample(timeout: config.pullTimeout);
        if (sample.isNotEmpty) {
          samplesThisLoop++;
          logger.finest(
            'DEBUG: Received sample from ${inlet.streamInfo.sourceId}: ${sample.data.take(4).toList()}...',
          );

          params.sendPort?.send(
            IsolateMessage.data({
              'streamAddress': address,
              'sourceId': inlet.streamInfo.sourceId,
              'sample': sample, // This is an LSLSample
              'timestamp': DateTime.now().microsecondsSinceEpoch,
            }),
          );
        }
      } catch (e) {
        logger.warning('Error polling inlet at address $address: $e');
        droppedThisLoop++;
      }
    }

    onStats(samplesThisLoop, droppedThisLoop);

    await Future.delayed(interval);
  }
}

/// Send performance metrics to main isolate
void _sendMetrics(
  SendPort sendPort,
  int samplesProcessed,
  int droppedSamples,
  int targetIntervalMicroseconds,
) {
  final targetFrequency = 1000000.0 / targetIntervalMicroseconds;

  sendPort.send(
    IsolateMessage.metrics({
      'samplesProcessed': samplesProcessed,
      'droppedSamples': droppedSamples,
      'actualFrequency': targetFrequency, // TODO: Calculate actual frequency
      'targetFrequency': targetFrequency,
      'messagesReceived': samplesProcessed,
    }),
  );
}

/// Extension to add fromMap to LSLStreamConfig
extension LSLStreamConfigExtension on LSLStreamConfig {
  static LSLStreamConfig fromMap(Map<String, dynamic> map) {
    return LSLStreamConfig(
      id: map['id'] as String,
      maxSampleRate: map['maxSampleRate'] as double,
      pollingFrequency: map['pollingFrequency'] as double,
      channelCount: map['channelCount'] as int,
      channelFormat: _deserializeChannelFormat(map['channelFormat'] as String),
      protocol: _deserializeProtocol(map['protocol'] as Map<String, dynamic>),
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
      streamType: map['streamType'] as String? ?? 'data',
      sourceId: map['sourceId'] as String,
      contentType: LSLContentType.values.firstWhere(
        (t) => t.toString() == map['contentType'],
        orElse: () => LSLContentType.eeg,
      ),
      pollingConfig: _deserializePollingConfig(
        map['pollingConfig'] as Map<String, dynamic>? ?? {},
      ),
      transportConfig: _deserializeTransportConfig(
        map['transportConfig'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  static StreamProtocol _deserializeProtocol(Map<String, dynamic> protocolMap) {
    final type = protocolMap['type'] as String;
    switch (type) {
      case 'ProducerOnlyProtocol':
        return const ProducerOnlyProtocol();
      case 'ConsumerOnlyProtocol':
        return const ConsumerOnlyProtocol();
      case 'RelayProtocol':
        return const RelayProtocol();
      default:
        return const ProducerOnlyProtocol(); // Default fallback
    }
  }

  static CoordinatorLSLChannelFormat _deserializeChannelFormat(
    String formatString,
  ) {
    switch (formatString) {
      case 'CoordinatorLSLChannelFormat.float32':
        return CoordinatorLSLChannelFormat.float32;
      case 'CoordinatorLSLChannelFormat.double64':
        return CoordinatorLSLChannelFormat.double64;
      case 'CoordinatorLSLChannelFormat.int8':
        return CoordinatorLSLChannelFormat.int8;
      case 'CoordinatorLSLChannelFormat.int16':
        return CoordinatorLSLChannelFormat.int16;
      case 'CoordinatorLSLChannelFormat.int32':
        return CoordinatorLSLChannelFormat.int32;
      case 'CoordinatorLSLChannelFormat.int64':
        return CoordinatorLSLChannelFormat.int64;
      case 'CoordinatorLSLChannelFormat.string':
        return CoordinatorLSLChannelFormat.string;
      default:
        return CoordinatorLSLChannelFormat.float32; // Default fallback
    }
  }

  static LSLPollingConfig _deserializePollingConfig(
    Map<String, dynamic> configMap,
  ) {
    return LSLPollingConfig(
      useBusyWait: configMap['useBusyWait'] as bool? ?? false,
      usePollingIsolate: configMap['usePollingIsolate'] as bool? ?? true,
      useIsolatedInlets: configMap['useIsolatedInlets'] as bool? ?? false,
      useIsolatedOutlets: configMap['useIsolatedOutlets'] as bool? ?? false,
      targetIntervalMicroseconds:
          configMap['targetIntervalMicroseconds'] as int? ?? 1000,
      bufferSize: configMap['bufferSize'] as int? ?? 1000,
      pullTimeout: configMap['pullTimeout'] as double? ?? 0.0,
      busyWaitThresholdMicroseconds:
          configMap['busyWaitThresholdMicroseconds'] as int? ?? 100,
    );
  }

  static LSLTransportConfig _deserializeTransportConfig(
    Map<String, dynamic> configMap,
  ) {
    return LSLTransportConfig(
      maxOutletBuffer: configMap['maxOutletBuffer'] as int? ?? 360,
      outletChunkSize: configMap['outletChunkSize'] as int? ?? 0,
      maxInletBuffer: configMap['maxInletBuffer'] as int? ?? 360,
      inletChunkSize: configMap['inletChunkSize'] as int? ?? 0,
      enableRecovery: configMap['enableRecovery'] as bool? ?? true,
    );
  }
}

/// Wait for consumers to connect to a specific outlet
Future<bool> _waitForConsumer(
  String outletId,
  double timeout,
  Map<String, LSLOutlet> outlets,
  logger,
) async {
  final outlet = outlets[outletId];
  if (outlet == null) {
    logger.warning('Outlet $outletId not found for waitForConsumer');
    return false;
  }

  try {
    return await outlet.waitForConsumer(timeout: timeout);
  } catch (e) {
    logger.warning('Error waiting for consumers on outlet $outletId: $e');
    return false;
  }
}

/// Check if consumers are connected to a specific outlet
Future<bool> _hasConsumers(
  String outletId,
  Map<String, LSLOutlet> outlets,
  logger,
) async {
  final outlet = outlets[outletId];
  if (outlet == null) {
    logger.warning('Outlet $outletId not found for hasConsumers');
    return false;
  }

  try {
    return await outlet.hasConsumers();
  } catch (e) {
    logger.warning('Error checking consumers on outlet $outletId: $e');
    return false;
  }
}
