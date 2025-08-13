import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:synchronized/synchronized.dart';
import '../core/coordination_message.dart';
import '../utils/logging.dart';
import 'lsl_transport.dart';

/// High-frequency configuration for critical data streams
class HighFrequencyConfig {
  /// Target polling frequency in Hz (default 1000 Hz)
  final double targetFrequency;

  /// Use busy-wait polling instead of timer-based polling
  final bool useBusyWait;

  /// Buffer size for high-frequency data
  final int bufferSize;

  /// Use separate isolate for polling
  final bool useIsolate;

  /// If we should create isolated inlets (a second-layer isolate)
  /// This is not usually necessary if [useIsolate] is true
  final bool useIsolateInlet;

  /// If we should create isolated outlets (a second-layer isolate)
  /// This is not usually necessary if [useIsolate] is true
  final bool useIsolateOutlet;

  /// Channel format for the game data stream
  final LSLChannelFormat channelFormat;

  /// Number of channels in the stream
  final int channelCount;

  const HighFrequencyConfig({
    this.targetFrequency = 1000.0,
    this.useBusyWait = true,
    this.bufferSize = 1000,
    this.useIsolate = true,
    this.useIsolateInlet = false,
    this.useIsolateOutlet = false,
    this.channelFormat = LSLChannelFormat.int32,
    this.channelCount = 1,
  }) : assert(targetFrequency > 0, 'Target frequency must be positive'),
       assert(bufferSize > 0, 'Buffer size must be positive'),
       assert(channelCount > 0, 'Channel count must be positive');

  /// Get the target polling interval in microseconds
  int get targetIntervalMicroseconds => (1000000 / targetFrequency).round();
}

/// High-frequency LSL transport using separate isolates for inlet/outlet
class HighFrequencyLSLTransport extends LSLNetworkTransport {
  final HighFrequencyConfig _config;
  final bool _receiveOwnMessages;

  // Separate isolates for inlet and outlet
  Isolate? _inletIsolate;
  Isolate? _outletIsolate;

  final Lock _lock = Lock();
  final Completer<void> _readyCompleter = Completer<void>();

  List<NetworkNode> _knownNodes = [];

  // Communication ports
  ReceivePort? _inletReceivePort;
  ReceivePort? _outletReceivePort;
  SendPort? _inletSendPort;
  SendPort? _outletSendPort;

  final StreamController<GameDataSample> _gameDataController =
      StreamController<GameDataSample>.broadcast();

  HighFrequencyLSLTransport({
    required super.streamName,
    required super.nodeId,
    super.sampleRate,
    HighFrequencyConfig? performanceConfig,
    bool receiveOwnMessages = true,
    super.lslApiConfig,
  }) : _config = performanceConfig ?? const HighFrequencyConfig(),
       _receiveOwnMessages = receiveOwnMessages;

  /// Stream for high-frequency game data samples
  Stream<GameDataSample> get gameDataStream => _gameDataController.stream;

  /// Get current performance metrics
  HighFrequencyMetrics get performanceMetrics => _performanceMetrics;

  HighFrequencyMetrics _performanceMetrics = HighFrequencyMetrics.empty();

  /// Stream for backward compatibility with coordination messages
  Stream<CoordinationMessage> get highPerformanceMessageStream =>
      gameDataStream.map(
        (sample) => ApplicationMessage(
          messageId: '${sample.sourceId}_${sample.timestamp}',
          senderId: sample.sourceId,
          timestamp: DateTime.fromMicrosecondsSinceEpoch(sample.timestamp),
          applicationType: 'game_data',
          payload: sample.toMap(),
        ),
      );

  @override
  Future<void> initialize() async {
    if (initialized) return;
    await _lock.synchronized(() async {
      // @TODO: fix and remove duplicate code
      // await super.initialize(); this, doesnt work
      if (initialized) return;
      initialized = true;
      logger.finest(
        'Initializing high-frequency LSL transport for node $nodeId, stream $streamName',
      );

      if (_config.useIsolate) {
        // Start separate isolates for inlet and outlet
        logger.finest(
          'Starting separate isolates for high-frequency transport',
        );

        await _startSeparateIsolates();
      }
      _readyCompleter.complete();
    });
  }

  Future<void> initializeWithTopology(List<NetworkNode> knownNodes) async {
    _knownNodes = knownNodes;
    logger.finest(
      'Initializing high-frequency LSL transport with topology: ${_knownNodes.length} nodes',
    );

    // Initialize the transport
    await initialize();
  }

  /// Start separate isolates for inlet consumer and outlet producer
  Future<void> _startSeparateIsolates() async {
    try {
      // Start outlet producer isolate
      logger.finest(
        'Starting outlet producer isolate for high-frequency transport',
      );
      await _startOutletProducerIsolate();

      // Start inlet consumer isolate
      logger.finest(
        'Starting inlet consumer isolate for high-frequency transport',
      );
      await _startInletConsumerIsolate();

      // Wait for both isolates to be ready
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      throw LSLTransportException('Failed to start separate isolates', e);
    }
  }

  /// Start inlet consumer isolate (receives data from other nodes)
  Future<void> _startInletConsumerIsolate() async {
    _inletReceivePort = ReceivePort();

    final isolateParams = _InletIsolateParams(
      streamName: streamName,
      nodeId: nodeId,
      config: _config,
      sendPort: _inletReceivePort!.sendPort,
      receiveOwnMessages: _receiveOwnMessages,
    );

    // Listen for messages from inlet isolate
    _inletReceivePort!.listen((message) {
      if (message is _IsolateMessage) {
        switch (message.type) {
          case _IsolateMessageType.gameDataSample:
            final sample = GameDataSample.fromMap(message.data);
            _gameDataController.add(sample);
            break;
          case _IsolateMessageType.performanceMetrics:
            _performanceMetrics = HighFrequencyMetrics.fromMap(message.data);
            break;
          case _IsolateMessageType.timeCorrectionUpdate:
            final correction = TimeCorrectionInfo.fromMap(message.data);
            _handleTimeCorrectionUpdate(correction);
            break;
          case _IsolateMessageType.error:
            print('Inlet consumer error: ${message.data}');
            break;
          default:
            break;
        }
      } else if (message is LogRecord) {
        Log.logIsolateMessage(message);
      } else if (message is SendPort) {
        _inletSendPort = message;
        if (_knownNodes.isNotEmpty) {
          // Notify inlet isolate about initial topology
          logger.finest('Sending initial topology to inlet consumer isolate');
          _inletSendPort!.send(
            _IsolateMessage(
              type: _IsolateMessageType.configUpdate,
              data: {'nodes': _knownNodes.map((n) => n.toMap()).toList()},
              timestamp: DateTime.now().microsecondsSinceEpoch,
            ),
          );
        }
      }
    });
    logger.finest(
      'Spawning inlet consumer isolate for high-frequency transport',
    );
    _inletIsolate = await Isolate.spawn(_inletConsumerIsolate, isolateParams);
    logger.finest(
      'Inlet consumer isolate started for high-frequency transport',
    );
  }

  /// Start outlet producer isolate (sends data to other nodes)
  Future<void> _startOutletProducerIsolate() async {
    _outletReceivePort = ReceivePort();

    final isolateParams = _OutletIsolateParams(
      streamName: streamName,
      nodeId: nodeId,
      config: _config,
      sendPort: _outletReceivePort!.sendPort,
    );

    // Listen for messages from outlet isolate
    _outletReceivePort!.listen((message) {
      if (message is _IsolateMessage) {
        switch (message.type) {
          case _IsolateMessageType.error:
            print('Outlet producer error: ${message.data}');
            break;
          default:
            break;
        }
      } else if (message is LogRecord) {
        Log.logIsolateMessage(message);
      } else if (message is SendPort) {
        _outletSendPort = message;
      }
    });

    _outletIsolate = await Isolate.spawn(_outletProducerIsolate, isolateParams);
  }

  /// Send game data with multiple channels and any data type
  Future<void> sendGameData<T>(List<T> channelData) async {
    if (_outletSendPort != null) {
      _outletSendPort!.send(
        _IsolateMessage(
          type: _IsolateMessageType.sendGameData,
          data: {
            'channel_data': channelData,
            'timestamp': DateTime.now().microsecondsSinceEpoch,
          },
          timestamp: DateTime.now().microsecondsSinceEpoch,
        ),
      );
    } else {
      // Fallback: create a coordination message
      final message = ApplicationMessage(
        messageId: _generateMessageId(),
        senderId: nodeId,
        timestamp: DateTime.now(),
        applicationType: 'game_data',
        payload: {
          'channel_data': channelData,
          'timestamp': DateTime.now().microsecondsSinceEpoch,
        },
      );
      await super.sendMessage(message);
    }
  }

  /// Send simple single-channel int event
  Future<void> sendEvent(int eventCode) async {
    // If stream has more than 1 channel, pad with 0 for compatibility
    if (_config.channelCount > 1) {
      final data = List<int>.filled(_config.channelCount, 0);
      data[0] = eventCode;
      await sendGameData(data);
    } else {
      await sendGameData([eventCode]);
    }
  }

  /// Send two-channel int data (e.g., event + response value)
  Future<void> sendEventWithValue(int eventCode, int value) async {
    await sendGameData([eventCode, value]);
  }

  /// Send multi-channel double data (e.g., position coordinates)
  Future<void> sendPositionData(List<double> coordinates) async {
    await sendGameData(coordinates);
  }

  /// Configure real-time polling parameters
  Future<void> configureRealTimePolling({
    double? frequency,
    bool? useBusyWait,
  }) async {
    if (_inletSendPort != null) {
      _inletSendPort!.send(
        _IsolateMessage(
          type: _IsolateMessageType.configUpdate,
          data: {'frequency': frequency, 'useBusyWait': useBusyWait},
          timestamp: DateTime.now().microsecondsSinceEpoch,
        ),
      );
    }
  }

  void _handleTimeCorrectionUpdate(TimeCorrectionInfo correction) {
    // Handle time correction updates for clock synchronization
    // This could be used for precise timing coordination between devices
    print(
      'Time correction update for ${correction.sourceId}: ${correction.correctionSeconds}s',
    );
  }

  String _generateMessageId() {
    return '${nodeId}_${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> updateTopology(List<NetworkNode> nodes) async {
    if (!initialized) {
      throw LSLTransportException('Transport not initialized');
    }
    await _readyCompleter.future;
    if (_inletSendPort == null) {
      logger.warning('Inlet send port is null, cannot update topology');
      return;
    }

    // Notify inlet consumer isolate about topology change
    logger.finest(
      'Updating topology with ${nodes.length} nodes for high-frequency transport',
    );
    _inletSendPort!.send(
      _IsolateMessage(
        type: _IsolateMessageType.configUpdate,
        data: {'nodes': nodes.map((n) => n.toMap()).toList()},
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  Future<void> pause() async {
    // Pause inlet consumer isolate
    if (_inletSendPort != null) {
      logger.info('Pausing inlet consumer isolate');
      _inletSendPort!.send(
        _IsolateMessage(
          type: _IsolateMessageType.pause,
          data: {},
          timestamp: DateTime.now().microsecondsSinceEpoch,
        ),
      );
    }

    // Pause outlet producer isolate
    if (_outletSendPort != null) {
      logger.info('Pausing outlet producer isolate');
      _outletSendPort!.send(
        _IsolateMessage(
          type: _IsolateMessageType.pause,
          data: {},
          timestamp: DateTime.now().microsecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> resume() async {
    // Resume inlet consumer isolate
    if (_inletSendPort != null) {
      logger.info('Resuming inlet consumer isolate');
      _inletSendPort!.send(
        _IsolateMessage(
          type: _IsolateMessageType.resume,
          data: {},
          timestamp: DateTime.now().microsecondsSinceEpoch,
        ),
      );
    }

    // Resume outlet producer isolate
    if (_outletSendPort != null) {
      logger.info('Resuming outlet producer isolate');
      _outletSendPort!.send(
        _IsolateMessage(
          type: _IsolateMessageType.resume,
          data: {},
          timestamp: DateTime.now().microsecondsSinceEpoch,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    logger.finest('Disposing high-frequency LSL transport');
    try {
      // Stop inlet consumer isolate
      if (_inletSendPort != null) {
        logger.finest('Stopping inlet consumer isolate');
        _inletSendPort!.send(
          _IsolateMessage(
            type: _IsolateMessageType.shutdown,
            data: {},
            timestamp: DateTime.now().microsecondsSinceEpoch,
          ),
        );
      }

      // Stop outlet producer isolate
      if (_outletSendPort != null) {
        logger.finest('Stopping outlet producer isolate');
        _outletSendPort!.send(
          _IsolateMessage(
            type: _IsolateMessageType.shutdown,
            data: {},
            timestamp: DateTime.now().microsecondsSinceEpoch,
          ),
        );
      }

      _inletIsolate?.kill();
      _outletIsolate?.kill();
      _inletReceivePort?.close();
      _outletReceivePort?.close();
      await _gameDataController.close();

      _inletIsolate = null;
      _outletIsolate = null;
      _inletReceivePort = null;
      _outletReceivePort = null;
      _inletSendPort = null;
      _outletSendPort = null;
    } catch (e) {
      logger.severe('Error disposing high-frequency transport: $e');
    }

    await super.dispose();
  }
}

/// Parameters for the inlet consumer isolate
class _InletIsolateParams {
  final String streamName;
  final String nodeId;
  final HighFrequencyConfig config;
  final SendPort sendPort;
  final bool receiveOwnMessages;

  _InletIsolateParams({
    required this.streamName,
    required this.nodeId,
    required this.config,
    required this.sendPort,
    required this.receiveOwnMessages,
  });
}

/// Parameters for the outlet producer isolate
class _OutletIsolateParams {
  final String streamName;
  final String nodeId;
  final HighFrequencyConfig config;
  final SendPort sendPort;

  _OutletIsolateParams({
    required this.streamName,
    required this.nodeId,
    required this.config,
    required this.sendPort,
  });
}

/// Message types for isolate communication
enum _IsolateMessageType {
  gameDataSample,
  performanceMetrics,
  timeCorrectionUpdate,
  error,
  sendGameData,
  // ignore: unused_field
  sendMessage,
  configUpdate,
  shutdown,
  pause,
  resume,
}

/// Message wrapper for isolate communication
class _IsolateMessage {
  final _IsolateMessageType type;
  final Map<String, dynamic> data;
  final int timestamp;

  _IsolateMessage({
    required this.type,
    required this.data,
    required this.timestamp,
  });
}

/// Game data sample with time correction info
class GameDataSample {
  final String sourceId;
  final List<dynamic> channelData;
  final int timestamp;
  final double? timeCorrection;
  final LSLChannelFormat channelFormat;

  const GameDataSample({
    required this.sourceId,
    required this.channelData,
    required this.timestamp,
    this.timeCorrection,
    required this.channelFormat,
  });

  factory GameDataSample.fromMap(Map<String, dynamic> map) {
    return GameDataSample(
      sourceId: map['source_id'],
      channelData: List<dynamic>.from(map['channel_data']),
      timestamp: map['timestamp'],
      timeCorrection: map['time_correction']?.toDouble(),
      channelFormat: LSLChannelFormat.values[map['channel_format'] ?? 0],
    );
  }

  Map<String, dynamic> toMap() => {
    'source_id': sourceId,
    'channel_data': channelData,
    'timestamp': timestamp,
    'time_correction': timeCorrection,
    'channel_format': channelFormat.index,
  };

  /// Get single-channel int value (for simple events)
  int get eventCode => channelData.isNotEmpty ? channelData[0] as int : 0;

  /// Get two-channel int values (event + value)
  (int event, int value) get eventWithValue =>
      channelData.length >= 2
          ? (channelData[0] as int, channelData[1] as int)
          : (0, 0);

  /// Get position data as doubles
  List<double> get positionData => channelData.map((e) => e as double).toList();
}

/// Time correction information for clock synchronization
class TimeCorrectionInfo {
  final String sourceId;
  final double correctionSeconds;
  final DateTime timestamp;

  const TimeCorrectionInfo({
    required this.sourceId,
    required this.correctionSeconds,
    required this.timestamp,
  });

  factory TimeCorrectionInfo.fromMap(Map<String, dynamic> map) {
    return TimeCorrectionInfo(
      sourceId: map['source_id'],
      correctionSeconds: map['correction_seconds']?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMicrosecondsSinceEpoch(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() => {
    'source_id': sourceId,
    'correction_seconds': correctionSeconds,
    'timestamp': timestamp.microsecondsSinceEpoch,
  };
}

/// Performance metrics for high-frequency polling
class HighFrequencyMetrics {
  final double actualFrequency;
  final int samplesProcessed;
  final int droppedSamples;
  final Map<String, double> timeCorrections;
  final DateTime timestamp;

  const HighFrequencyMetrics({
    required this.actualFrequency,
    required this.samplesProcessed,
    required this.droppedSamples,
    required this.timeCorrections,
    required this.timestamp,
  });

  factory HighFrequencyMetrics.empty() => HighFrequencyMetrics(
    actualFrequency: 0,
    samplesProcessed: 0,
    droppedSamples: 0,
    timeCorrections: {},
    timestamp: DateTime.now(),
  );

  factory HighFrequencyMetrics.fromMap(Map<String, dynamic> map) {
    return HighFrequencyMetrics(
      actualFrequency: map['actualFrequency']?.toDouble() ?? 0.0,
      samplesProcessed: map['samplesProcessed'] ?? 0,
      droppedSamples: map['droppedSamples'] ?? 0,
      timeCorrections: Map<String, double>.from(map['timeCorrections'] ?? {}),
      timestamp: DateTime.fromMicrosecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }

  Map<String, dynamic> toMap() => {
    'actualFrequency': actualFrequency,
    'samplesProcessed': samplesProcessed,
    'droppedSamples': droppedSamples,
    'timeCorrections': timeCorrections,
    'timestamp': timestamp.microsecondsSinceEpoch,
  };
}

/// Simplified precise interval function for polling
Future<void> _runPrecisePollingInterval(
  Duration interval,
  bool Function() isRunning,
  Future<void> Function() callback, {
  Duration startBusyAt = const Duration(microseconds: 100),
  bool Function()? isPaused,
  Duration pauseDuration = const Duration(milliseconds: 100),
}) async {
  logger.fine('Starting precise polling interval: $interval');
  final sw = Stopwatch()..start();

  for (int i = 1; isRunning(); i++) {
    if (isPaused?.call() ?? false) {
      logger.fine('Polling paused, waiting for resume');
      while (isPaused?.call() ?? false) {
        await Future.delayed(pauseDuration);
      }
      logger.fine('Polling resumed');
    }
    final nextAwake = interval * i;
    final toSleep = (nextAwake - sw.elapsed) - startBusyAt;

    // Sleep efficiently until close to target time
    if (toSleep > Duration.zero) {
      // sleep(toSleep);
      // less precise but avoids busy-waiting
      await Future.delayed(toSleep);
    }

    // Precise busy-wait for the final stretch
    while (sw.elapsed < nextAwake && isRunning()) {
      // Busy wait for microsecond precision
    }

    if (isRunning()) {
      await callback();
    }
  }
}

/// Inlet consumer isolate entry point - only handles receiving data
void _inletConsumerIsolate(_InletIsolateParams params) async {
  Log.sendPort = params.sendPort;
  logger.finest(
    'Inlet isolate entry point. Starting polling for '
    'node ${params.nodeId}, stream ${params.streamName}',
  );
  final receivePort = ReceivePort();
  params.sendPort.send(receivePort.sendPort);

  List<LSLInlet> inlets = <LSLInlet>[];
  final timeCorrections = <String, double>{};
  final Lock lock = Lock();

  var isRunning = true;
  var config = params.config;

  // Performance tracking
  var samplesProcessed = 0;
  var droppedSamples = 0;
  var lastStatsUpdate = DateTime.now();
  logger.finest('Preparing resolver for game data streams');
  final resolver = LSLStreamResolverContinuousByPredicate(
    predicate:
        "name='${params.streamName}' and starts-with(source_id, 'game_')",
    maxStreams: 50,
  );
  resolver.create();

  try {
    // Discover and connect to existing game data streams
    logger.finest('Discovering existing game data streams');

    await _discoverAndConnectGameStreams(
      params,
      inlets,
      timeCorrections,
      resolver,
    );

    // Start high-frequency polling loop
    if (config.useBusyWait) {
      logger.finest('Using busy-wait polling for high-frequency transport');
      await _busyWaitInletPollingLoop(
        params,
        inlets,
        config,
        receivePort,
        timeCorrections,
        lock,
        () => isRunning,
        (processed, dropped) {
          samplesProcessed += processed;
          droppedSamples += dropped;

          // Send performance metrics every second
          final now = DateTime.now();
          if (now.difference(lastStatsUpdate).inMilliseconds >= 1000) {
            _sendPerformanceMetrics(
              params.sendPort,
              samplesProcessed,
              droppedSamples,
              timeCorrections,
              config.targetFrequency,
            );
            lastStatsUpdate = now;
          }
        },
        resolver,
      );
    } else {
      logger.finest('Using timer-based polling for high-frequency transport');
      await _timerBasedInletPollingLoop(
        params,
        inlets,
        config,
        receivePort,
        timeCorrections,
        () => isRunning,
      );
    }
  } catch (e) {
    logger.severe('Error in inlet consumer isolate: $e');
    params.sendPort.send(
      _IsolateMessage(
        type: _IsolateMessageType.error,
        data: {'error': e.toString()},
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  } finally {
    // Clean up
    logger.finest('Cleaning up inlet consumer isolate');
    for (final inlet in inlets) {
      try {
        await inlet.destroy();
        //inlet.streamInfo.destroy();
      } catch (e) {
        print('Error destroying inlet: $e');
      }
    }
    resolver.destroy();
    receivePort.close();
  }
}

Future<List<LSLInlet>> _addInletForNodes(
  HighFrequencyConfig config,
  List<NetworkNode> nodes,
  List<LSLInlet> inlets,
  LSLStreamResolverContinuous resolver,
) async {
  final availableStreams = await resolver.resolve(waitTime: 0.5);
  for (final node in nodes) {
    try {
      final stream = availableStreams.firstWhere(
        (s) => s.sourceId == 'game_${node.nodeId}',
        orElse:
            () => throw Exception('Stream not found for node ${node.nodeId}'),
      );

      if (!inlets.any((i) => i.streamInfo.sourceId == stream.sourceId)) {
        logger.info('Creating inlet for node ${node.nodeId}');
        final inlet = await LSL.createInlet(
          streamInfo: stream,
          maxBuffer: 1000,
          chunkSize: 1,
          recover: true,
          useIsolates: config.useIsolateInlet,
        );
        inlets.add(inlet);
        // remove from stream list
        availableStreams.remove(stream);
        await inlet.getTimeCorrection(timeout: 1.0);
      }
    } catch (e) {
      logger.warning('Failed to find stream for node ${node.nodeId}: $e');
    }
  }
  // Destroy any remaining streams that were not used
  availableStreams.destroy();
  return inlets;
}

Future<List<LSLInlet>> _removeInlets(
  List<LSLInlet> remove,
  List<LSLInlet> inlets,
) async {
  for (final inlet in remove) {
    try {
      await inlet.destroy();
      //inlet.streamInfo.destroy();
      inlets.remove(inlet);
    } catch (e) {
      logger.warning('Failed to destroy inlet: $e');
    }
  }
  return inlets;
}

/// Outlet producer isolate entry point - only handles sending data
void _outletProducerIsolate(_OutletIsolateParams params) async {
  Log.sendPort = params.sendPort;
  logger.finest(
    'Starting outlet producer isolate for high-frequency transport',
  );
  final receivePort = ReceivePort();
  params.sendPort.send(receivePort.sendPort);

  LSLOutlet? outlet;
  var isRunning = true;
  var config = params.config;

  try {
    // Initialize LSL outlet for sending game data
    final streamInfo = await LSL.createStreamInfo(
      streamName: params.streamName,
      streamType: LSLContentType.markers,
      channelCount: config.channelCount,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: config.channelFormat,
      sourceId: 'game_${params.nodeId}',
    );

    outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: 1,
      maxBuffer: config.bufferSize,
      useIsolates: config.useIsolateOutlet,
    );

    // Listen for messages from main thread
    receivePort.listen((message) {
      if (message is _IsolateMessage) {
        switch (message.type) {
          case _IsolateMessageType.sendGameData:
            // Send game data via outlet
            if (outlet != null) {
              try {
                final channelData = message.data['channel_data'] as List;
                outlet.pushSample(channelData);
              } catch (e) {
                params.sendPort.send(
                  _IsolateMessage(
                    type: _IsolateMessageType.error,
                    data: {'error': 'Failed to send game data: $e'},
                    timestamp: DateTime.now().microsecondsSinceEpoch,
                  ),
                );
              }
            }
            break;
          case _IsolateMessageType.shutdown:
            isRunning = false;
            break;
          default:
            break;
        }
      }
    });

    // Keep the isolate alive
    while (isRunning) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    logger.finest('Shutting down outlet producer isolate');
  } catch (e) {
    logger.severe('Error in outlet producer isolate: $e');
    params.sendPort.send(
      _IsolateMessage(
        type: _IsolateMessageType.error,
        data: {'error': e.toString()},
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  } finally {
    // Clean up
    if (outlet != null) {
      try {
        await outlet.destroy();
        //outlet.streamInfo.destroy();
      } catch (e) {
        logger.severe('Error destroying outlet: $e');
      }
    }

    receivePort.close();
  }
}

/// Discover and connect to existing game data streams
Future<void> _discoverAndConnectGameStreams(
  _InletIsolateParams params,
  List<LSLInlet> inlets,
  Map<String, double> timeCorrections,
  LSLStreamResolverContinuous resolver,
) async {
  try {
    final streams = await resolver.resolve();

    final gameStreams = streams.where(
      (s) =>
          (params.receiveOwnMessages || s.sourceId != 'game_${params.nodeId}'),
    );

    logger.finest(
      'Discovered ${gameStreams.length} game streams for node ${params.nodeId}. recievesOwnMessages: ${params.receiveOwnMessages}',
    );
    // destroy the rest of the streamInfos that are not in gameStreams
    final restStreams =
        streams
            .where((s) => !gameStreams.any((gs) => gs.sourceId == s.sourceId))
            .toList();
    logger.finest(
      "Ignoring ${restStreams.length} non-game streams: [${restStreams.map((s) => s.sourceId).join(', ')}]",
    );
    restStreams.destroy();

    for (final stream in gameStreams) {
      try {
        logger.info('Creating inlet for game stream ${stream.sourceId}');
        final inlet = await LSL.createInlet(
          streamInfo: stream,
          maxBuffer: params.config.bufferSize,
          chunkSize: 1,
          recover: true,
          useIsolates: params.config.useIsolateInlet,
        );

        inlets.add(inlet);

        // Get initial time correction (this takes time on first call)
        try {
          final correction = await inlet.getTimeCorrection(timeout: 1.0);
          timeCorrections[stream.sourceId] = correction;

          params.sendPort.send(
            _IsolateMessage(
              type: _IsolateMessageType.timeCorrectionUpdate,
              data:
                  TimeCorrectionInfo(
                    sourceId: stream.sourceId,
                    correctionSeconds: correction,
                    timestamp: DateTime.now(),
                  ).toMap(),
              timestamp: DateTime.now().microsecondsSinceEpoch,
            ),
          );
        } catch (e) {
          logger.warning(
            'Failed to get time correction for ${stream.sourceId}: $e',
          );
          timeCorrections[stream.sourceId] = 0.0;
        }
      } catch (e) {
        logger.severe('Failed to create inlet for ${stream.sourceId}: $e');
      }
    }
  } catch (e) {
    logger.severe('Error discovering game streams: $e');
  }
}

/// High-precision polling loop using precise interval technique - inlet only
Future<void> _busyWaitInletPollingLoop(
  _InletIsolateParams params,
  List<LSLInlet> inlets,
  HighFrequencyConfig config,
  ReceivePort receivePort,
  Map<String, double> timeCorrections,
  Lock lock,
  bool Function() isRunning,
  void Function(int processed, int dropped) onStats,
  LSLStreamResolverContinuous resolver,
) async {
  var samplesProcessed = 0;
  var droppedSamples = 0;

  final interval = Duration(microseconds: config.targetIntervalMicroseconds);
  final busyWaitThreshold = Duration(microseconds: 100);

  var paused = false;
  logger.finest(
    'Starting busy-wait polling loop for node ${params.nodeId}, stream ${params.streamName}',
  );
  // Listen for isolate messages
  receivePort.listen((message) async {
    if (message is _IsolateMessage) {
      logger.finest(
        'busyWaitInlet: Received isolate message of type ${message.type} with data: ${message.data}',
      );
      switch (message.type) {
        case _IsolateMessageType.configUpdate:
          // Update node toplology
          if (message.data.containsKey('nodes')) {
            logger.info(
              'Updating node topology with ${message.data['nodes'].length} nodes',
            );
            final nodes =
                (message.data['nodes'] as List)
                    .map((n) => NetworkNode.fromMap(n as Map<String, dynamic>))
                    .toList();

            final addedNodes =
                nodes
                    .where(
                      (n) =>
                          !inlets.any((i) => i.streamInfo.sourceId == n.nodeId),
                    )
                    .toList();
            final removedNodes =
                inlets
                    .where(
                      (i) =>
                          !nodes.any((n) => n.nodeId == i.streamInfo.sourceId),
                    )
                    .toList();
            inlets = await _removeInlets(removedNodes, inlets);
            inlets = await _addInletForNodes(
              config,
              addedNodes,
              inlets,
              resolver,
            );
          }

          break;
        case _IsolateMessageType.pause:
          logger.fine('Polling paused by isolate message');
          paused = true;
          break;
        case _IsolateMessageType.resume:
          logger.fine('Polling resumed by isolate message');
          paused = false;
          break;
        case _IsolateMessageType.shutdown:
          return; // Exit the function to stop polling
        default:
          break;
      }
    }
  });

  // Use precise interval technique
  await _runPrecisePollingInterval(
    interval,
    isRunning,
    () async {
      // Poll all inlets for new game data
      for (final inlet in inlets) {
        try {
          final sample = await inlet.pullSample(timeout: 0.0);
          if (sample.isNotEmpty) {
            final pollTime = DateTime.now().microsecondsSinceEpoch;

            // Get current time correction (fast after initial call)
            final sourceId = inlet.streamInfo.sourceId;
            var correction = timeCorrections[sourceId] ?? 0.0;

            try {
              // Update time correction periodically (every 100 samples)
              await lock.synchronized(() async {
                if (samplesProcessed % 100 == 0) {
                  final newCorrection = await inlet.getTimeCorrection(
                    timeout: 0.001,
                  );
                  if ((newCorrection - correction).abs() > 0.001) {
                    timeCorrections[sourceId] = newCorrection;
                    correction = newCorrection;

                    params.sendPort.send(
                      _IsolateMessage(
                        type: _IsolateMessageType.timeCorrectionUpdate,
                        data:
                            TimeCorrectionInfo(
                              sourceId: sourceId,
                              correctionSeconds: newCorrection,
                              timestamp: DateTime.now(),
                            ).toMap(),
                        timestamp: DateTime.now().microsecondsSinceEpoch,
                      ),
                    );
                  }
                }
              });

              final gameSample = GameDataSample(
                sourceId: sourceId,
                channelData: sample.data,
                timestamp: pollTime,
                timeCorrection: correction,
                channelFormat: config.channelFormat,
              );

              params.sendPort.send(
                _IsolateMessage(
                  type: _IsolateMessageType.gameDataSample,
                  data: gameSample.toMap(),
                  timestamp: pollTime,
                ),
              );

              samplesProcessed++;
            } catch (e) {
              logger.shout('Error processing game data sample: $e');
              droppedSamples++;
            }
          }
        } catch (e) {
          logger.severe('Error polling inlet: $e');
        }
      }

      // Send stats periodically
      if (samplesProcessed % 1000 == 0 && samplesProcessed > 0) {
        onStats(samplesProcessed, droppedSamples);
        samplesProcessed = 0;
        droppedSamples = 0;
      }
    },
    startBusyAt: busyWaitThreshold,
    isPaused: () => paused,
    pauseDuration: const Duration(milliseconds: 100),
  );
}

/// Timer-based polling loop (less precise but lower CPU usage) - inlet only
Future<void> _timerBasedInletPollingLoop(
  _InletIsolateParams params,
  List<LSLInlet> inlets,
  HighFrequencyConfig config,
  ReceivePort receivePort,
  Map<String, double> timeCorrections,
  bool Function() isRunning,
) async {
  var paused = false;
  // Listen for isolate messages
  receivePort.listen((message) {
    if (message is _IsolateMessage) {
      switch (message.type) {
        case _IsolateMessageType.pause:
          logger.fine('Polling paused by isolate message');
          paused = true;
          break;
        case _IsolateMessageType.resume:
          logger.fine('Polling resumed by isolate message');
          paused = false;
          break;
        default:
          break;
      }
    }
  });
  final timer = Timer.periodic(
    Duration(microseconds: config.targetIntervalMicroseconds),
    (timer) async {
      if (paused) {
        return;
      }
      if (!isRunning()) {
        timer.cancel();
        return;
      }

      // Similar polling logic as busy wait but less precise
      for (final inlet in inlets) {
        try {
          final sample = await inlet.pullSample(timeout: 0.0);
          if (sample.isNotEmpty) {
            final sourceId = inlet.streamInfo.sourceId;
            final correction = timeCorrections[sourceId] ?? 0.0;

            final gameSample = GameDataSample(
              sourceId: sourceId,
              channelData: sample.data,
              timestamp: DateTime.now().microsecondsSinceEpoch,
              timeCorrection: correction,
              channelFormat: config.channelFormat,
            );

            params.sendPort.send(
              _IsolateMessage(
                type: _IsolateMessageType.gameDataSample,
                data: gameSample.toMap(),
                timestamp: DateTime.now().microsecondsSinceEpoch,
              ),
            );
          }
        } catch (e) {
          logger.severe('Error polling inlet: $e');
        }
      }
    },
  );

  // Keep the isolate alive
  await Future.doWhile(() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return isRunning();
  });
  logger.finest('Stopping timer-based polling loop');
  timer.cancel();
}

/// Send performance metrics to main isolate
void _sendPerformanceMetrics(
  SendPort sendPort,
  int samplesProcessed,
  int droppedSamples,
  Map<String, double> timeCorrections,
  double targetFrequency,
) {
  final actualFrequency = samplesProcessed > 0 ? targetFrequency : 0.0;

  final metrics = HighFrequencyMetrics(
    actualFrequency: actualFrequency,
    samplesProcessed: samplesProcessed,
    droppedSamples: droppedSamples,
    timeCorrections: Map.from(timeCorrections),
    timestamp: DateTime.now(),
  );

  sendPort.send(
    _IsolateMessage(
      type: _IsolateMessageType.performanceMetrics,
      data: metrics.toMap(),
      timestamp: DateTime.now().microsecondsSinceEpoch,
    ),
  );
}
