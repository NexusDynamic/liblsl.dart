import 'dart:async';
import 'dart:math';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'lsl_coordination_controller.dart';

/// Simplified coordination session using the controller pattern.
///
/// All coordination events are emitted through a single [events] stream.
/// Use the [ControllerEventStreamExtensions] for convenient filtering:
/// ```dart
/// session.events.phaseChanges.listen((e) => print('Phase: ${e.phase}'));
/// session.events.streamCreate.listen((e) => print('Create: ${e.streamName}'));
/// session.events.nodeJoined.listen((e) => print('Joined: ${e.node.id}'));
/// ```
class LSLCoordinationSession extends CoordinationSession with RuntimeTypeUID {
  @override
  String get id => 'lsl-coordination-session';
  @override
  String get name => 'LSL Coordination Session';
  @override
  String get description =>
      'LSL coordination session';

  late final LSLTransport _transport;
  late final CoordinationController _controller;
  final Map<String, LSLDataStream> _dataStreams = {};

  /// Single event stream for all coordination events.
  ///
  /// Use the extension methods for convenient filtering:
  /// ```dart
  /// session.events.phaseChanges.listen((e) => ...);
  /// session.events.streamCreate.listen((e) => ...);
  /// session.events.nodeJoined.listen((e) => ...);
  /// ```
  Stream<ControllerEvent> get events => _controller.events;

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
    // Handle all stream lifecycle events through the unified event stream
    events.streamLifecycle.listen((event) async {
      switch (event) {
        case StreamCreateEvent e:
          await _handleStreamCreate(e);
        case StreamStartEvent e:
          await _handleStreamStart(e);
        case StreamReadyEvent _:
          // StreamReady events are for coordination, no local action needed
          break;
        case StreamStopEvent e:
          await _handleStreamStop(e);
        case StreamPauseEvent e:
          await _handleStreamPause(e);
        case StreamResumeEvent e:
          await _handleStreamResume(e);
        case StreamFlushEvent e:
          await _handleStreamFlush(e);
        case StreamDestroyEvent e:
          await _handleStreamDestroy(e);
      }
    });
  }

  Future<void> _handleStreamCreate(StreamCreateEvent event) async {
    // Create the stream but don't start it yet
    if (!_dataStreams.containsKey(event.streamName)) {
      await createDataStream(event.streamConfig);
    }

    // Notify coordinator we're ready
    await _controller.markStreamReady(event.streamName);
    logger.finest('Stream prepared and marked ready: ${event.streamName}');
  }

  Future<void> _handleStreamStart(StreamStartEvent event) async {
    logger.finest('Received start stream command: ${event.streamName}');

    final stream = _dataStreams[event.streamName];
    if (stream != null) {
      if (!stream.started) {
        await stream.start();
        logger.info('Started stream: ${event.streamName}');
      } else {
        logger.warning(
          'Stream ${event.streamName} already started, skipping',
        );
      }
    } else {
      logger.warning('Stream ${event.streamName} not found');
    }
  }

  Future<void> _handleStreamStop(StreamStopEvent event) async {
    final stream = _dataStreams[event.streamName];
    if (stream != null && stream.started) {
      await stream.stop(); // Now just pauses polling, doesn't dispose
      logger.info('PARTICIPANT Stopped stream: ${event.streamName}');
    }
  }

  Future<void> _handleStreamPause(StreamPauseEvent event) async {
    final stream = _dataStreams[event.streamName];
    if (stream != null && stream.started && !stream.paused) {
      await stream.pauseStream();
      logger.info('PARTICIPANT Paused stream: ${event.streamName}');
    }
  }

  Future<void> _handleStreamResume(StreamResumeEvent event) async {
    final stream = _dataStreams[event.streamName];
    if (stream != null && stream.started && stream.paused) {
      await stream.resumeStream(flushBeforeResume: event.flushBeforeResume);
      logger.info(
        'PARTICIPANT Resumed stream: ${event.streamName}, flush: ${event.flushBeforeResume}',
      );
    }
  }

  Future<void> _handleStreamFlush(StreamFlushEvent event) async {
    final stream = _dataStreams[event.streamName];
    if (stream != null && stream.started) {
      await stream.flushStreams();
      logger.info('PARTICIPANT Flushed stream: ${event.streamName}');
    }
  }

  Future<void> _handleStreamDestroy(StreamDestroyEvent event) async {
    final stream = _dataStreams[event.streamName];
    if (stream != null) {
      await stream.destroyStream();
      _dataStreams.remove(event.streamName);
      logger.info('PARTICIPANT Destroyed stream: ${event.streamName}');
    }
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
        'Joined coordination session as ${_controller.isCoordinator ? 'COORDINATOR' : 'PARTICIPANT'}',
      );
    } catch (e) {
      logger.severe('COORDINATION FAILED: $e');
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

    subscription = events.phaseChanges.listen((event) {
      if (targetPhase.contains(event.phase)) {
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

    // If we are in the expected nodes, mark ourselves as ready
    if (expectedNodeUIds.contains(thisNode.uId)) {
      readyNodes.add(thisNode.uId);
      logger.info('Coordinator marked self as ready for stream $streamName');
    }

    if (readyNodes.length == expectedNodeUIds.length) {
      logger.info('All participants already ready for stream $streamName');
      return;
    }

    logger.info(
      'Waiting for ${expectedNodeUIds.length} participants to be ready for stream $streamName: $expectedNodeUIds',
    );

    final completer = Completer<void>();
    StreamSubscription<StreamReadyEvent>? subscription;

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

    // Listen for streamReady events
    subscription = events.streamReady.listen((event) {
      if (event.streamName == streamName &&
          expectedNodeUIds.contains(event.fromNodeUId)) {
        readyNodes.add(event.fromNodeUId);
        logger.info(
          'Participant ${event.fromNodeUId} ready for stream $streamName (${readyNodes.length}/${expectedNodeUIds.length})',
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

    subscription = events.nodeJoined.listen((_) {
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
  Future<UserCoordinationEvent> waitForUserMessage(
    String messageId, {
    Duration? timeout,
  }) async {
    final completer = Completer<UserCoordinationEvent>();
    late StreamSubscription subscription;
    Timer? timeoutTimer;

    subscription = events.userCoordinationMessages.listen((event) {
      if (event.messageId == messageId) {
        timeoutTimer?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete(event);
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
