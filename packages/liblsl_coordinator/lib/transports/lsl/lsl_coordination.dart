import 'dart:async';
import 'dart:math';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'lsl_coordination_controller.dart';

/// Simplified coordination session using the controller pattern
class LSLCoordinationSession extends CoordinationSession with RuntimeTypeUID {
  @override
  String get id => 'lsl-coordination-session';
  @override
  String get name => 'LSL Coordination Session';
  @override
  String get description =>
      'Simplified LSL coordination session using controller pattern';

  late final LSLTransport _transport;
  late final CoordinationController _controller;
  final Map<String, LSLDataStream> _dataStreams = {};

  // Public streams - forward from controller
  Stream<CoordinationPhase> get phaseChanges => _controller.phaseChanges;
  Stream<CreateStreamMessage> get streamCreateCommands =>
      _controller.streamCreateCommands;
  Stream<StartStreamMessage> get streamStartCommands =>
      _controller.streamStartCommands;

  Stream<StreamReadyMessage> get streamReadyNotifications =>
      _controller.streamReadyNotifications;

  Stream<StopStreamMessage> get streamStopCommands =>
      _controller.streamStopCommands;

  // @TODO: We really need to refactor all the individual commands into
  // a singl stream, this is way too messy and inovlves recreating the same
  // pathway every time.
  Stream<PauseStreamMessage> get streamPauseCommands =>
      _controller.streamPauseCommands;

  Stream<ResumeStreamMessage> get streamResumeCommands =>
      _controller.streamResumeCommands;

  Stream<FlushStreamMessage> get streamFlushCommands =>
      _controller.streamFlushCommands;

  Stream<DestroyStreamMessage> get streamDestroyCommands =>
      _controller.streamDestroyCommands;

  Stream<UserCoordinationMessage> get userMessages => _controller.userMessages;
  Stream<UserParticipantMessage> get userParticipantMessages =>
      _controller.userParticipantMessages;
  Stream<ConfigUpdateMessage> get configUpdates => _controller.configUpdates;
  Stream<Node> get nodeJoined => _controller.nodeJoined;
  Stream<Node> get nodeLeft => _controller.nodeLeft;

  // Public state access
  CoordinationPhase get currentPhase => _controller.currentPhase;
  bool get isCoordinator => _controller.isCoordinator;
  String? get coordinatorUId => _controller.coordinatorUId;
  List<Node> get connectedNodes => _controller.connectedNodes;
  List<Node> get connectedParticipantNodes =>
      _controller.connectedParticipantNodes;

  @override
  LSLTransport get transport => _transport;

  LSLCoordinationSession(super.config, {super.thisNodeConfig}) {
    _transport = (coordinationConfig.transportConfig is LSLTransportConfig)
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
    // Handle createStream commands - prepare stream but don't start
    streamCreateCommands.listen((command) async {
      // Create the stream but don't start it yet
      if (!_dataStreams.containsKey(command.streamName)) {
        await createDataStream(command.streamConfig);
      }

      // Notify coordinator we're ready
      await _controller.markStreamReady(command.streamName);
      logger.finest('Stream prepared and marked ready: ${command.streamName}');
    });

    // Handle startStream commands - actually start the stream
    streamStartCommands.listen((command) async {
      logger.finest('Received start stream command: ${command.streamName}');

      final stream = _dataStreams[command.streamName];
      if (stream != null) {
        if (!stream.started) {
          await stream.start();
          logger.info('Started stream: ${command.streamName}');
        } else {
          logger.warning(
            'Stream ${command.streamName} already started, skipping',
          );
        }
      } else {
        logger.warning('Stream ${command.streamName} not found');
      }
    });

    streamStopCommands.listen((command) async {
      final stream = _dataStreams[command.streamName];
      if (stream != null && stream.started) {
        await stream.stop(); // Now just pauses polling, doesn't dispose
        logger.info('PARTICIPANT Stopped stream: ${command.streamName}');
      }
    });

    // Handle pauseStream commands
    streamPauseCommands.listen((command) async {
      final stream = _dataStreams[command.streamName];
      if (stream != null && stream.started && !stream.paused) {
        await stream.pauseStream();
        logger.info('PARTICIPANT Paused stream: ${command.streamName}');
      }
    });

    // Handle resumeStream commands
    streamResumeCommands.listen((command) async {
      final stream = _dataStreams[command.streamName];
      if (stream != null && stream.started && stream.paused) {
        await stream.resumeStream(flushBeforeResume: command.flushBeforeResume);
        logger.info(
          'PARTICIPANT Resumed stream: ${command.streamName}, flush: ${command.flushBeforeResume}',
        );
      }
    });

    // Handle flushStream commands
    streamFlushCommands.listen((command) async {
      final stream = _dataStreams[command.streamName];
      if (stream != null && stream.started) {
        await stream.flushStreams();
        logger.info('PARTICIPANT Flushed stream: ${command.streamName}');
      }
    });

    // Handle destroyStream commands
    streamDestroyCommands.listen((command) async {
      final stream = _dataStreams[command.streamName];
      if (stream != null) {
        await stream.destroyStream();
        _dataStreams.remove(command.streamName);
        logger.info('PARTICIPANT Destroyed stream: ${command.streamName}');
      }
    });
  }

  @override
  Future<void> create() async {
    await super.create();
    logger.fine('LSL Coordination Session created');
  }

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Initialize transport
    await _transport.initialize();
    await _transport.create();

    // Initialize controller
    await _controller.initialize();

    logger.fine('LSL Coordination Session initialized');
  }

  @override
  Future<void> join() async {
    await super.join();

    logger.info('Joining coordination session...');
    await _controller.start();

    // Wait for coordination to be established
    try {
      // TODO: make timeout configurable
      await _waitForPhase({
        CoordinationPhase.accepting,
        CoordinationPhase.ready,
      }, timeout: Duration(seconds: config.discoveryInterval.inSeconds * 10));
      logger.info(
        '✅ Joined coordination session as ${_controller.isCoordinator ? 'COORDINATOR' : 'PARTICIPANT'}',
      );
    } catch (e) {
      logger.severe('❌ COORDINATION FAILED: $e');
      throw StateError('Failed to establish coordination: $e');
    }
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
    Set<CoordinationPhase> targetPhase, {
    Duration? timeout,
  }) async {
    if (targetPhase.contains(currentPhase)) {
      return;
    }

    final completer = Completer<void>();
    late StreamSubscription subscription;
    Timer? timeoutTimer;

    subscription = phaseChanges.listen((phase) {
      if (targetPhase.contains(phase)) {
        timeoutTimer?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        logger.warning(
          'Timeout waiting for phase $targetPhase after ${timeout.inSeconds}s (current: $currentPhase)',
        );
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

    // Create outlets and inlets but don't start yet (new flow)
    if (isCoordinator) {
      // Coordinator broadcasts createStream to all participants
      // This happens before inlet creation to ensure that the first step
      // of any data stream is the outlet, and then inlets are created after,
      // as the streams will be available.
      await _controller.createStream(config.name, config);

      if (config.participationMode !=
          StreamParticipationMode.sendParticipantsReceiveCoordinator) {
        await stream.createOutlet();
      }

      /// now we can create inlets from each expected sender
      if (config.participationMode != StreamParticipationMode.coordinatorOnly) {
        // Wait for all participants to create their outlets and signal ready
        final producers = await getProducersForStream(config.name);
        logger.info(
          'Coordinator waiting for ${producers.length} participants to be ready for stream: ${config.name}',
        );

        await _waitForParticipantStreamsReady(
          config.name,
          producers,
          timeout: const Duration(seconds: 10),
        );

        logger.info(
          'All participants ready, creating inlets for producers: ${producers.map((e) => "${e.uId} ${e.role}").join(', ')}',
        );
        await stream.createResolvedInletsForStream(producers);
      }

      // Coordinator marks itself as ready
      await _controller.markStreamReady(config.name);
      logger.info(
        'Coordinator created stream and broadcasted to participants: ${config.name}',
      );
    } else {
      if (config.participationMode != StreamParticipationMode.coordinatorOnly) {
        logger.finest(
          'Participant creating outlet for stream: ${config.name}, ${config.participationMode}',
        );
        await stream.createOutlet();
      }

      /// now we can create inlets from each expected sender
      if (config.participationMode !=
          StreamParticipationMode.sendParticipantsReceiveCoordinator) {
        // Create inlets for all existing nodes
        final producers = await getProducersForStream(config.name);
        await stream.createResolvedInletsForStream(producers);
      }
      await _controller.markStreamReady(config.name);
      logger.info(
        'Participant created stream, waiting for coordinator command: ${config.name}',
      );
    }

    return stream;
  }

  Future<LSLDataStream> _createDataStream(DataStreamConfig config) async {
    if (_dataStreams.containsKey(config.name)) {
      logger.warning('Stream already exists, not recreating: ${config.name}');
      return _dataStreams[config.name]!;
    }
    final factory = LSLNetworkStreamFactory();
    final stream = await factory.createDataStream(config, this);

    await stream.create();
    _dataStreams[config.name] = stream;

    logger.info('Created data stream: ${config.name}');
    return stream;
  }

  Future<LSLDataStream> getDataStream(String name) async {
    if (!_dataStreams.containsKey(name)) {
      throw ArgumentError('Stream not found: $name');
    }
    return _dataStreams[name]!;
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
    // Start the stream ourselves
    await stream.start();

    /// Send start command to all participants
    await _controller.startStream(streamName, stream.config, startAt: startAt);
  }

  /// Wait for all participants to signal they are ready for the specified stream
  /// by listening to streamReadyNotifications.
  /// Throws TimeoutException if not all participants signal ready within timeout.
  Future<void> _waitForParticipantStreamsReady(
    String streamName,
    Set<Node> expectedProducers, {
    required Duration timeout,
  }) async {
    if (expectedProducers.isEmpty) {
      logger.info('No participants to wait for (coordinator-only stream)');
      return;
    }

    final expectedNodeUIds = expectedProducers.map((node) => node.uId).toSet();
    final readyNodes = <String>{};

    logger.info(
      'Waiting for ${expectedNodeUIds.length} participants to be ready for stream $streamName: $expectedNodeUIds',
    );

    final completer = Completer<void>();
    StreamSubscription<StreamReadyMessage>? subscription;

    // Set up timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        final missingNodes = expectedNodeUIds.difference(readyNodes);
        logger.severe(
          'Timeout waiting for participants to be ready for stream $streamName. Missing: $missingNodes',
        );
        completer.completeError(
          TimeoutException(
            'Timeout waiting for participants to be ready for stream $streamName. Missing nodes: $missingNodes',
            timeout,
          ),
        );
      }
    });

    // Listen for streamReady messages
    subscription = streamReadyNotifications.listen((message) {
      if (message.streamName == streamName &&
          expectedNodeUIds.contains(message.fromNodeUId)) {
        readyNodes.add(message.fromNodeUId);
        logger.info(
          'Participant ${message.fromNodeUId} ready for stream $streamName (${readyNodes.length}/${expectedNodeUIds.length})',
        );

        // Check if all participants are ready
        if (readyNodes.length == expectedNodeUIds.length) {
          logger.info(
            'All ${expectedNodeUIds.length} participants ready for stream $streamName',
          );
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      }
    });

    try {
      await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<Set<Node>> getProducersForStream(String streamName) async {
    final stream = _dataStreams[streamName];
    if (stream == null) {
      throw ArgumentError('Stream not found: $streamName');
    }
    if (stream.config.participationMode ==
        StreamParticipationMode.coordinatorOnly) {
      return connectedNodes
          .where(
            (streamNode) =>
                streamNode.role == NodeCapability.coordinator.shortString,
          )
          .toSet();
    } else if (stream.config.participationMode ==
        StreamParticipationMode.sendParticipantsReceiveCoordinator) {
      return connectedNodes
          .where(
            (streamNode) =>
                streamNode.role != NodeCapability.coordinator.shortString,
          )
          .toSet();
    } else if (stream.config.participationMode ==
            StreamParticipationMode.allNodes ||
        stream.config.participationMode ==
            StreamParticipationMode.sendAllReceiveCoordinator) {
      return connectedNodes.toSet();
    } else {
      return {};
    }
  }

  Future<Set<Node>> getConsumersForStream(String streamName) async {
    final stream = _dataStreams[streamName];
    if (stream == null) {
      throw ArgumentError('Stream not found: $streamName');
    }
    if (stream.config.participationMode ==
        StreamParticipationMode.coordinatorOnly) {
      return connectedNodes
          .where(
            (streamNode) =>
                streamNode.role != NodeCapability.coordinator.shortString,
          )
          .toSet();
    } else if (stream.config.participationMode ==
            StreamParticipationMode.sendParticipantsReceiveCoordinator ||
        stream.config.participationMode ==
            StreamParticipationMode.sendAllReceiveCoordinator) {
      return connectedNodes
          .where(
            (streamNode) =>
                streamNode.role == NodeCapability.coordinator.shortString,
          )
          .toSet();
    } else if (stream.config.participationMode ==
        StreamParticipationMode.allNodes) {
      return connectedNodes.toSet();
    } else {
      return {};
    }
  }

  /// Pause a stream (stop polling but keep resources alive) - coordinator broadcasts to all nodes
  Future<void> pauseStream(String streamName) async {
    await _controller.pauseStream(streamName);
    // If coordinator, also handle local stream
    if (isCoordinator) {
      final stream = _dataStreams[streamName];
      if (stream != null && stream.started && !stream.paused) {
        await stream.pauseStream();
        logger.info('COORDINATOR Paused stream: $streamName');
      }
    }
  }

  /// Resume a stream with optional flushing - coordinator broadcasts to all nodes
  Future<void> resumeStream(
    String streamName, {
    bool flushBeforeResume = true,
  }) async {
    await _controller.resumeStream(
      streamName,
      flushBeforeResume: flushBeforeResume,
    );
    // If coordinator, also handle local stream
    if (isCoordinator) {
      final stream = _dataStreams[streamName];
      if (stream != null && stream.started && stream.paused) {
        await stream.resumeStream(flushBeforeResume: flushBeforeResume);
        logger.info(
          'COORDINATOR Resumed stream: $streamName, flush: $flushBeforeResume',
        );
      }
    }
  }

  /// Flush a stream to clear pending messages - coordinator broadcasts to all nodes
  Future<void> flushStream(String streamName) async {
    await _controller.flushStream(streamName);
    // If coordinator, also handle local stream
    if (isCoordinator) {
      final stream = _dataStreams[streamName];
      if (stream != null && stream.started) {
        await stream.flushStreams();
        logger.info('COORDINATOR Flushed stream: $streamName');
      }
    }
  }

  /// Stop a stream (pause polling, keep stream in registry for potential resumption)
  Future<void> stopStream(String streamName) async {
    await _controller.stopStream(streamName);
    // If coordinator, also handle local stream
    if (isCoordinator) {
      final stream = _dataStreams[streamName];
      if (stream != null && stream.started) {
        await stream.stop(); // This now just pauses polling
        logger.info('COORDINATOR Stopped stream: $streamName');
      }
    }
  }

  /// Destroy a stream completely (remove from registry and dispose all resources)
  Future<void> destroyStream(String streamName) async {
    await _controller.destroyStream(streamName);
    // If coordinator, also handle local stream
    if (isCoordinator) {
      final stream = _dataStreams[streamName];
      if (stream != null) {
        await stream.destroyStream();
        _dataStreams.remove(streamName);
        logger.info('COORDINATOR Destroyed stream: $streamName');
      }
    }
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
    if (!joined) {
      logger.warning('Not joined, cannot leave coordination session');
      return;
    }
    await super.leave();

    // Dispose streams
    logger.finest('Disposing ${_dataStreams.length} data streams...');
    for (final stream in _dataStreams.values) {
      await stream.dispose();
    }
    _dataStreams.clear();

    // Dispose controller (handles cleanup and leaving messages)
    logger.finest('Leaving coordination session...');
    await _transport.dispose();
    await _controller.dispose();

    logger.info('Left coordination session');
  }

  @override
  // @TODO: not mix dispose and leave
  Future<void> dispose() async {
    if (joined) {
      await leave();
    }
    await super.dispose();

    logger.finest('Disposed LSL Coordination Session');
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
