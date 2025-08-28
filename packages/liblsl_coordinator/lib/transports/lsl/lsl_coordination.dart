import 'dart:async';
import 'dart:math';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'lsl_coordination_controller.dart';

/// Simplified coordination session using the controller pattern
class LSLCoordinationSession extends CoordinationSession with RuntimeTypeUID {
  @override
  String get id => 'lsl-coordination-session-v2';
  @override
  String get name => 'LSL Coordination Session V2';
  @override
  String get description =>
      'Simplified LSL coordination session using controller pattern';

  late final LSLTransport _transport;
  late final CoordinationController _controller;
  final Map<String, LSLDataStream> _dataStreams = {};

  // Public streams - forward from controller
  Stream<CoordinationPhase> get phaseChanges => _controller.phaseChanges;
  Stream<StartStreamMessage> get streamStartCommands =>
      _controller.streamStartCommands;
  Stream<StopStreamMessage> get streamStopCommands =>
      _controller.streamStopCommands;
  Stream<UserCoordinationMessage> get userMessages => _controller.userMessages;
  Stream<ConfigUpdateMessage> get configUpdates => _controller.configUpdates;
  Stream<Node> get nodeJoined => _controller.nodeJoined;
  Stream<Node> get nodeLeft => _controller.nodeLeft;

  // Public state access
  CoordinationPhase get currentPhase => _controller.currentPhase;
  bool get isCoordinator => _controller.isCoordinator;
  String? get coordinatorUId => _controller.coordinatorUId;
  List<Node> get connectedNodes => _controller.connectedNodes;

  @override
  LSLTransport get transport => _transport;

  LSLCoordinationSession(super.config) {
    _transport =
        (coordinationConfig.transportConfig is LSLTransportConfig)
            ? LSLTransport(
              config: coordinationConfig.transportConfig as LSLTransportConfig,
            )
            : LSLTransport();

    // Add metadata to node
    thisNode.setMetadata('sessionId', config.name);
    thisNode.setMetadata('appId', coordinationConfig.name);
    thisNode.setMetadata('randomRoll', Random().nextDouble().toString());
    thisNode.setMetadata('nodeStartedAt', DateTime.now().toIso8601String());

    _controller = CoordinationController(
      coordinationConfig: coordinationConfig,
      transport: _transport,
      thisNode: thisNode,
      session: this,
    );

    _setupStreamCommandHandlers();
  }

  void _setupStreamCommandHandlers() {
    // Auto-handle stream commands if not overridden by application
    streamStartCommands.listen((command) async {
      logger.info('Received start stream command: ${command.streamName}');

      // Check if we should auto-create the stream
      if (!_dataStreams.containsKey(command.streamName)) {
        logger.info('Auto-creating stream: ${command.streamName}');
        await _createDataStream(command.streamConfig);
      }

      // Start the stream
      final stream = _dataStreams[command.streamName];
      if (stream != null && !stream.started) {
        await stream.start();
        logger.info('Started stream: ${command.streamName}');
      }
    });

    streamStopCommands.listen((command) async {
      logger.info('Received stop stream command: ${command.streamName}');

      final stream = _dataStreams[command.streamName];
      if (stream != null && stream.started) {
        await stream.stop();
        logger.info('Stopped stream: ${command.streamName}');
      }
    });
  }

  @override
  Future<void> create() async {
    await super.create();
    logger.info('LSL Coordination Session V2 created');
  }

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Initialize transport
    await _transport.initialize();
    await _transport.create();

    // Initialize controller
    await _controller.initialize();

    logger.info('LSL Coordination Session V2 initialized');
  }

  @override
  Future<void> join() async {
    await super.join();

    // Start coordination process
    await _controller.start();

    // Wait for coordination to be established
    // TODO: not hardcoded, but configurable
    await _waitForPhase(
      CoordinationPhase.established,
      timeout: Duration(seconds: 30),
    );

    logger.info(
      'Joined coordination session as ${isCoordinator ? "coordinator" : "participant"}',
    );
  }

  /// not yet implementd
  @override
  Future<void> pause() async {
    super.pause();
    throw UnimplementedError(
      'Pause not yet implemented in LSLCoordinationSession',
    );
  }

  /// not yet implementd
  @override
  Future<void> resume() async {
    super.resume();
    throw UnimplementedError(
      'Resume not yet implemented in LSLCoordinationSession',
    );
  }

  /// Wait for a specific coordination phase
  Future<void> _waitForPhase(
    CoordinationPhase targetPhase, {
    Duration? timeout,
  }) async {
    if (currentPhase == targetPhase) return;

    final completer = Completer<void>();
    late StreamSubscription subscription;
    Timer? timeoutTimer;

    subscription = phaseChanges.listen((phase) {
      if (phase == targetPhase) {
        timeoutTimer?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('Timeout waiting for phase $targetPhase', timeout),
          );
        }
      });
    }

    return completer.future;
  }

  /// Create a data stream with automatic setup
  Future<LSLDataStream> createDataStream(DataStreamConfig config) async {
    if (!initialized) throw StateError('Session must be initialized');

    final stream = await _createDataStream(config);

    // If we're the coordinator, we can start it immediately
    // If we're a participant, we wait for coordinator command
    if (isCoordinator) {
      logger.info('Coordinator auto-starting stream: ${config.name}');
      await stream.start();
    } else {
      logger.info(
        'Participant created stream, waiting for coordinator command: ${config.name}',
      );
    }

    return stream;
  }

  Future<LSLDataStream> _createDataStream(DataStreamConfig config) async {
    final factory = LSLNetworkStreamFactory();
    final stream = await factory.createDataStream(config, this);

    await stream.create();
    _dataStreams[config.name] = stream;

    logger.info('Created data stream: ${config.name}');
    return stream;
  }

  // Coordinator methods - only work if this node is the coordinator
  Future<void> pauseAcceptingNodes() async {
    await _controller.pauseAcceptingNodes();
  }

  Future<void> resumeAcceptingNodes() async {
    await _controller.resumeAcceptingNodes();
  }

  bool get isAcceptingNodes => _controller.isAcceptingNodes;

  Future<void> startStream(String streamName, {DateTime? startAt}) async {
    final stream = _dataStreams[streamName];
    if (stream == null) {
      throw ArgumentError('Stream not found: $streamName');
    }

    await _controller.startStream(streamName, stream.config, startAt: startAt);
  }

  Future<void> stopStream(String streamName) async {
    await _controller.stopStream(streamName);
  }

  Future<void> sendUserMessage(
    String messageId,
    String description, [
    Map<String, dynamic>? payload,
  ]) async {
    await _controller.sendUserMessage(messageId, description, payload ?? {});
  }

  Future<void> updateConfig(Map<String, dynamic> config) async {
    await _controller.updateConfig(config);
  }

  // Convenience method for common coordination patterns
  Future<void> waitForMinNodes(int minNodes, {Duration? timeout}) async {
    if (connectedNodes.length >= minNodes) return;

    final completer = Completer<void>();
    late StreamSubscription subscription;
    Timer? timeoutTimer;

    subscription = nodeJoined.listen((_) {
      if (connectedNodes.length >= minNodes) {
        timeoutTimer?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('Timeout waiting for minimum nodes', timeout),
          );
        }
      });
    }

    return completer.future;
  }

  /// Wait for a specific user message
  Future<UserCoordinationMessage> waitForUserMessage(
    String messageId, {
    Duration? timeout,
  }) async {
    final completer = Completer<UserCoordinationMessage>();
    late StreamSubscription subscription;
    Timer? timeoutTimer;

    subscription = userMessages.listen((message) {
      if (message.messageId == messageId) {
        timeoutTimer?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete(message);
        }
      }
    });

    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('Timeout waiting for message $messageId', timeout),
          );
        }
      });
    }

    return completer.future;
  }

  @override
  Future<void> leave() async {
    await super.leave();

    // Dispose controller (handles cleanup and leaving messages)
    await _controller.dispose();

    // Dispose streams
    for (final stream in _dataStreams.values) {
      await stream.dispose();
    }
    _dataStreams.clear();

    logger.info('Left coordination session');
  }

  @override
  Future<void> dispose() async {
    if (joined) {
      await leave();
    }

    await _transport.dispose();
    await super.dispose();

    logger.info('Disposed LSL Coordination Session V2');
  }

  // Resource manager methods - delegate to transport
  @override
  Future<void> manageResource<R extends IResource>(R resource) async {
    _transport.manageResource(resource);
  }

  @override
  Future<R> releaseResource<R extends IResource>(String resourceUID) async {
    return _transport.releaseResource(resourceUID);
  }
}
