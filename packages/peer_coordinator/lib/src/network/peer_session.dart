import 'dart:async';
import 'dart:math';
import 'package:peer_coordinator/config.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:synchronized/synchronized.dart';

/// A coordination session, independent of any transport.
///
/// This is the user-facing surface: initialize, join, create and drive data
/// streams, exchange user messages, leave. It owns the [CoordinationController]
/// and the data-stream registry, and delegates everything wire-related to the
/// [ITransport] it is given.
///
/// Construct one with [PeerSession.create] to have the transport built from
/// the config, or pass a transport explicitly. A transport package may
/// subclass this to narrow return types to its own stream classes — see
/// `LSLCoordinationSession`.
///
/// All coordination events are emitted through a single [events] stream.
/// Use the [ControllerEventStreamExtensions] for convenient filtering:
/// ```dart
/// session.events.phaseChanges.listen((e) => print('Phase: ${e.phase}'));
/// session.events.streamCreate.listen((e) => print('Create: ${e.streamName}'));
/// session.events.nodeJoined.listen((e) => print('Joined: ${e.node.id}'));
/// ```
class PeerSession extends CoordinationSession with InstanceUID {
  @override
  String get id => 'peer-coordination-session';
  @override
  String get name => 'Peer Coordination Session';
  @override
  String get description => 'Transport-neutral coordination session';

  final ITransport _transport;
  late final CoordinationController _controller;
  final Map<String, DataStream> _dataStreams = {};

  /// Creates currently in flight, by stream name.
  ///
  /// [_streamLock] only covers registration in [_dataStreams]; the outlet and
  /// inlet wiring that follows runs unlocked and can take the best part of a
  /// second. Anything that looks a stream up in that window sees nothing and
  /// concludes it does not exist — which is a lie, it is being built right now.
  /// Awaiting the in-flight future instead turns that race into a queue.
  ///
  /// Deliberately consulted only by the *external* lookups ([getDataStream],
  /// [_awaitDataStream]). Internal callers use [_getDataStreamLocked], which
  /// must not await this: [createDataStream] itself calls them while its own
  /// future sits in this map, and awaiting it would deadlock on itself.
  final Map<String, Future<DataStream>> _creating = {};

  final Lock _streamLock = Lock();
  StreamSubscription<StreamLifecycleEvent>? _lifecycleSubscription;
  StreamSubscription<NodeLeftEvent>? _departureSubscription;

  /// Single event stream for all coordination events.
  ///
  /// Use the extension methods for convenient filtering:
  /// ```dart
  /// session.events.phaseChanges.listen((e) => ...);
  /// session.events.streamCreate.listen((e) => ...);
  /// session.events.nodeJoined.listen((e) => ...);
  /// ```
  Stream<ControllerEvent> get events => _controller.events;

  /// See [CoordinationController.coordinationClockSyncs].
  Stream<ClockSyncSample> get coordinationClockSyncs =>
      _controller.coordinationClockSyncs;

  /// See [CoordinationController.coordinationOutletConsumers].
  Stream<bool> get coordinationOutletConsumers =>
      _controller.coordinationOutletConsumers;

  /// See [CoordinationController.noteNodeActivity].
  void noteNodeActivity(String nodeUId) =>
      _controller.noteNodeActivity(nodeUId);

  /// See [CoordinationController.sinceLastHeard].
  Duration? sinceLastHeard(String nodeUId) =>
      _controller.sinceLastHeard(nodeUId);

  /// See [CoordinationController.coordinationSendFailures].
  int get coordinationSendFailures => _controller.coordinationSendFailures;

  // Public state access
  CoordinationPhase get currentPhase => _controller.currentPhase;
  bool get isCoordinator => _controller.isCoordinator;
  String? get coordinatorUId => _controller.coordinatorUId;
  List<Node> get connectedNodes => _controller.connectedNodes;
  List<Node> get connectedParticipantNodes =>
      _controller.connectedParticipantNodes;

  @override
  ITransport get transport => _transport;

  /// Creates a session over an explicitly supplied [transport].
  PeerSession(super.config, {required this._transport, super.thisNodeConfig}) {
    // Election inputs. Seeded here rather than in Node's constructor because
    // they are session-scoped facts, not properties of the node itself.
    thisNode.setMetadata('sessionId', config.name);
    thisNode.setMetadata('appId', coordinationConfig.name);
    if (!thisNode.metadata.containsKey(PeerMetadataKeys.randomRoll)) {
      thisNode.setMetadata(
        PeerMetadataKeys.randomRoll,
        Random().nextDouble().toString(),
      );
    }
    thisNode.setMetadata(
      PeerMetadataKeys.nodeStartedAt,
      DateTime.now().toIso8601String(),
    );

    // A relay-backed transport authenticates as this node, and the hub checks
    // every endpoint it later claims against that identity. Set before
    // initialize() connects anything.
    final transport = _transport;
    if (transport is IAuthenticatedTransport) {
      (transport as IAuthenticatedTransport).localNodeUId = thisNode.uId;
    }

    _controller = CoordinationController(
      coordinationConfig: coordinationConfig,
      transport: _transport,
      thisNode: thisNode,
      session: this,
    );

    _setupStreamCommandHandlers();
    _setupDepartureHandler();
  }

  /// Creates a session, building the transport from
  /// [CoordinationConfig.transportConfig].
  ///
  /// This is what keeps the core free of transport imports: the config carries
  /// the factory, so nothing here needs to know which backends exist.
  factory PeerSession.create(
    CoordinationConfig config, {
    NodeConfig? thisNodeConfig,
  }) => PeerSession(
    config,
    transport: config.transportConfig.createTransport(),
    thisNodeConfig: thisNodeConfig,
  );

  /// Releases every data stream's inlet to a node that has left.
  ///
  /// The controller does this for the coordination stream; data streams are
  /// owned here, so the fan-out is here too. On a relay transport the inlet is
  /// inert either way, but a transport holding a real per-peer resource — an
  /// LSL inlet, an `RTCPeerConnection` — leaks one per departure without this.
  void _setupDepartureHandler() {
    _departureSubscription = events.nodeLeft.listen((event) async {
      // A snapshot: removeInlet is async and a stream may be destroyed while
      // the fan-out is in flight.
      for (final stream in _dataStreams.values.toList(growable: false)) {
        try {
          await stream.removeInlet(event.node.uId);
        } catch (e) {
          logger.warning(
            'Failed to remove inlet for ${event.node.uId} from '
            '"${stream.name}": $e',
          );
        }
      }
    });
  }

  void _setupStreamCommandHandlers() {
    // Handle all stream lifecycle events through the unified event stream
    _lifecycleSubscription = events.streamLifecycle.listen((event) async {
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
    final DataStream? stream = await _getDataStreamLocked(event.streamName);
    if (stream == null) {
      await createDataStream(event.streamConfig);
    }

    // Notify coordinator we're ready this is duplicated, createDataStream already
    // marks stream ready
    // await _controller.markStreamReady(event.streamName);
    logger.finest('Stream prepared and marked ready: ${event.streamName}');
  }

  Future<void> _handleStreamStart(StreamStartEvent event) async {
    logger.finest('Received start stream command: ${event.streamName}');
    // _awaitDataStream, not _getDataStreamLocked: a start command can overtake
    // the create it belongs to, and the lock only covers registration, not the
    // outlet and inlet wiring that follows. Looking up unlocked found nothing,
    // logged a warning, and left a stream that the coordinator believed was
    // running permanently unstarted.
    final DataStream? stream = await _awaitDataStream(event.streamName);

    if (stream != null) {
      if (!stream.started) {
        await stream.start();
        logger.info('Started stream: ${event.streamName}');
        // Notify coordinator we're ready
        await _controller.markStreamReady(event.streamName);
      } else {
        logger.warning('Stream ${event.streamName} already started, skipping');
        // Notify coordinator we're ready
        await _controller.markStreamReady(event.streamName);
      }
    } else {
      // Severe, not a warning: the coordinator is about to send data into a
      // stream this node will never start, and nothing retries. Silence here
      // is what made the failure look like an unexplained 30 s stall further
      // downstream instead of a missing stream here.
      logger.severe(
        'Stream ${event.streamName} not found and not being created — '
        'cannot start it',
      );
    }
  }

  Future<DataStream?> _getDataStreamLocked(String streamName) async {
    return await _streamLock.synchronized(() {
      return _dataStreams[streamName];
    });
  }

  Future<void> _handleStreamStop(StreamStopEvent event) async {
    final DataStream? stream = await _getDataStreamLocked(event.streamName);

    if (stream != null) {
      if (stream.started) {
        await stream.stop(); // Now just pauses polling, doesn't dispose
        logger.info('PARTICIPANT Stopped stream: ${event.streamName}');
      } else {
        logger.warning(
          'PARTICIPANT Requested stream is already stopped:  ${event.streamName}',
        );
      }
      // Notify coordinator we're ready
      await _controller.markStreamReady(event.streamName);
    }
  }

  Future<void> _handleStreamPause(StreamPauseEvent event) async {
    final DataStream? stream = await _getDataStreamLocked(event.streamName);
    if (stream != null && stream.started && !stream.paused) {
      await stream.pauseStream();
      logger.info('PARTICIPANT Paused stream: ${event.streamName}');
      // Notify coordinator we're ready
      await _controller.markStreamReady(event.streamName);
    }
  }

  Future<void> _handleStreamResume(StreamResumeEvent event) async {
    final DataStream? stream = await _getDataStreamLocked(event.streamName);
    if (stream != null && stream.started && stream.paused) {
      await stream.resumeStream(flushBeforeResume: event.flushBeforeResume);
      logger.info(
        'PARTICIPANT Resumed stream: ${event.streamName}, flush: ${event.flushBeforeResume}',
      );
      // Notify coordinator we're ready
      await _controller.markStreamReady(event.streamName);
    }
  }

  Future<void> _handleStreamFlush(StreamFlushEvent event) async {
    final DataStream? stream = await _getDataStreamLocked(event.streamName);
    if (stream != null && stream.started) {
      await stream.flushStreams();
      logger.info('PARTICIPANT Flushed stream: ${event.streamName}');
      // Notify coordinator we're ready
      await _controller.markStreamReady(event.streamName);
    }
  }

  Future<void> _handleStreamDestroy(StreamDestroyEvent event) async {
    await _streamLock.synchronized(() async {
      final stream = _dataStreams[event.streamName];
      if (stream != null) {
        await stream.destroyStream();
        _dataStreams.remove(event.streamName);
        logger.info('PARTICIPANT Destroyed stream: ${event.streamName}');
        // Notify coordinator we're ready
        await _controller.markStreamReady(event.streamName);
      }
    });
  }

  @override
  Future<void> create() async {
    await super.create();
    logger.fine('Coordination session created');
  }

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Initialize transport
    await _transport.initialize();
    await _transport.create();

    // Initialize controller
    await _controller.initialize();

    logger.fine('Coordination session initialized');
  }

  @override
  Future<void> join([Duration? timeout]) async {
    await super.join();

    logger.info('Joining coordination session...');
    await _controller.start(timeout);

    // Wait for coordination to be established
    try {
      // TODO: make timeout configurable
      await _waitForPhase(
        {CoordinationPhase.accepting, CoordinationPhase.ready},
        timeout:
            timeout ??
            Duration(seconds: config.discoveryInterval.inSeconds * 10),
      );
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
    throw UnimplementedError('Pause not yet implemented in PeerSession');
  }

  /// not yet implementd
  @override
  Future<void> resume() async {
    super.resume();
    throw UnimplementedError('Resume not yet implemented in PeerSession');
  }

  /// Wait for a specific coordination phase
  Future<void> _waitForPhase(
    Set<CoordinationPhase> targetPhase, {
    Duration? timeout,
  }) async {
    if (targetPhase.contains(currentPhase)) {
      return;
    }
    await waitForEvent<PhaseChangedEvent>(
      events.phaseChanges,
      (event) => targetPhase.contains(event.phase),
      timeout: timeout,
      description: 'phase $targetPhase (current: $currentPhase)',
    );
  }

  /// Create a data stream with automatic setup.
  ///
  /// Idempotent: calling this twice for the same stream returns the existing
  /// one without re-running any wiring.
  ///
  /// That guarantee is load-bearing. Participants build their streams
  /// automatically when the coordinator's `createStream` command arrives, so
  /// application code that also calls this — a reasonable thing to try after
  /// seeing a `streamCreate` event — used to reach the setup path twice. The
  /// second pass called `createOutlet()` on a stream that already had one,
  /// which threw `Bad state: Stream has already been listened to` from inside
  /// the transport and left the first outlet orphaned: still published on the
  /// network, no longer reachable, and so never disposed. It looked exactly
  /// like a teardown leak.
  Future<DataStream> createDataStream(DataStreamConfig config) async {
    if (!initialized) throw StateError('Session must be initialized');

    // Everything up to the registration below runs in the caller's turn, on
    // purpose: a lookup issued in the same turn as this call — which is what
    // a `streamStart` handler reacting to the matching `createStream` does —
    // must already be able to see the in-flight future.
    final inFlight = _creating[config.name];
    if (inFlight != null) {
      // Two concurrent creates for one name must share a setup, not race it.
      // The second used to find nothing registered yet, fall through, and run
      // the whole wiring again on the stream the first had just registered —
      // calling createOutlet() on a stream that already had one, which throws
      // from inside the transport and orphans the first outlet.
      logger.fine('Create already in flight, awaiting it: ${config.name}');
      return inFlight;
    }

    final pending = _createOrReuseDataStream(config);
    _creating[config.name] = pending;
    try {
      return await pending;
    } finally {
      _creating.remove(config.name);
    }
  }

  Future<DataStream> _createOrReuseDataStream(DataStreamConfig config) async {
    final existing = await _getDataStreamLocked(config.name);
    if (existing != null) {
      logger.fine(
        'Data stream already set up, returning it unchanged: ${config.name}',
      );
      return existing;
    }
    return _setUpDataStream(config);
  }

  Future<DataStream> _setUpDataStream(DataStreamConfig config) async {
    final stream = await _createDataStream(config);

    // Create outlets and inlets but don't start yet (new flow)
    if (isCoordinator) {
      final isCoordinatorOnly =
          config.participationMode == StreamParticipationMode.coordinatorOnly;

      // Who must have this stream up before creation can be called complete.
      // For a normal stream that is its producers, whose outlets we need to
      // build inlets from. For a coordinatorOnly stream the participants are
      // pure consumers — nothing here depends on them technically, but the
      // *caller* almost always issues startStream() next, and a start command
      // that overtakes its own create leaves the participant with a stream it
      // never starts. Waiting for consumers here is what makes the create →
      // start ordering a guarantee rather than a hope.
      final awaited = isCoordinatorOnly
          ? await getConsumersForStream(config.name)
          : await getProducersForStream(config.name);

      // Started before the broadcast below, not after the outlet exists: acks
      // can land as soon as participants can see us, and this collector is
      // forward-only.
      final acks = _collectStreamReadyAcks(config.name, awaited);
      try {
        // Coordinator broadcasts createStream to all participants
        // This happens before inlet creation to ensure that the first step
        // of any data stream is the outlet, and then inlets are created after,
        // as the streams will be available.
        await _controller.createStream(config.name, config);

        if (config.participationMode !=
            StreamParticipationMode.sendParticipantsReceiveCoordinator) {
          await stream.createOutlet();
        }

        logger.info(
          'Coordinator waiting for ${awaited.length} participants to be ready '
          'for stream: ${config.name}',
        );

        if (isCoordinatorOnly) {
          // Non-fatal, unlike the producers path below. Our outlet is valid
          // whether or not a participant acked in time, and the application
          // can still attach late (RiseTogether does, off its own streamReady).
          // Turning one slow tablet into a hard phase failure mid-experiment
          // would be a worse outcome than the ordering bug this wait fixes.
          try {
            await acks.wait(timeout: const Duration(seconds: 10));
          } on TimeoutException catch (e) {
            logger.severe(
              'Continuing without all consumers ready for stream '
              '${config.name}: $e',
            );
          }
        } else {
          /// now we can create inlets from each expected sender
          await acks.wait(timeout: const Duration(seconds: 10));

          logger.info(
            'All participants ready, creating inlets for producers: ${awaited.map((e) => "${e.uId} ${e.role}").join(', ')}',
          );
          await stream.createInletsForNodes(awaited);
        }
      } finally {
        await acks.cancel();
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
        await stream.createInletsForNodes(producers);
      }
      await _controller.markStreamReady(config.name);
      logger.info(
        'Participant created stream, waiting for coordinator command: ${config.name}',
      );
    }

    return stream;
  }

  Future<DataStream> _createDataStream(DataStreamConfig config) async {
    return await _streamLock.synchronized(() async {
      if (_dataStreams.containsKey(config.name)) {
        logger.warning('Stream already exists, not recreating: ${config.name}');
        return _dataStreams[config.name]!;
      }
      final factory = _transport.streamFactory;
      final stream = await factory.createDataStream(config, this);

      await stream.create();
      _dataStreams[config.name] = stream;

      logger.info('Created data stream: ${config.name}');
      return stream;
    });
  }

  /// The stream registered under [name], waiting for an in-flight create.
  ///
  /// Throws [ArgumentError] when no such stream exists and none is being
  /// built. Callers reacting to a lifecycle event should expect that: a
  /// `streamStart` can arrive while the matching create is still running, and
  /// a `streamReady` can arrive for a stream a destroy has just removed.
  Future<DataStream> getDataStream(String name) async {
    final stream = await _awaitDataStream(name);
    if (stream == null) {
      throw ArgumentError('Stream not found: $name');
    }
    return stream;
  }

  /// [_getDataStreamLocked], but queued behind an in-flight [createDataStream]
  /// for the same name. Null only once the stream genuinely is not there.
  Future<DataStream?> _awaitDataStream(String name) async {
    final pending = _creating[name];
    if (pending != null) {
      // Its own failure is the caller's problem to report, not ours; fall
      // through to the registry lookup either way.
      await pending.then((_) {}, onError: (_) {});
    }
    return _getDataStreamLocked(name);
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
    final DataStream? stream = await _getDataStreamLocked(streamName);
    if (stream == null) {
      throw ArgumentError('Stream not found: $streamName');
    }
    // Start the stream ourselves
    await stream.start();

    /// Send start command to all participants
    await _controller.startStream(streamName, stream.config, startAt: startAt);
  }

  /// Start collecting `streamReady` acks for [streamName] from [expected].
  ///
  /// Subscribing is split from awaiting on purpose. The wait this replaced was
  /// built on [waitForEvent], which is forward-only — it cannot see an ack that
  /// arrived before it subscribed. The coordinator only reached that wait
  /// *after* broadcasting `createStream` and building its outlet, so a
  /// participant quick enough to ack in that window was never counted and the
  /// wait burned its whole timeout on a message it had already been sent.
  ///
  /// Callers construct this before doing anything that lets a participant ack,
  /// and await it afterwards.
  _StreamReadyAcks _collectStreamReadyAcks(
    String streamName,
    Set<Node> expected,
  ) => _StreamReadyAcks(
    streamName: streamName,
    expectedNodeUIds: expected.map((node) => node.uId).toSet(),
    selfUId: thisNode.uId,
    acks: events.streamReady,
  );

  Future<Set<Node>> getProducersForStream(String streamName) async {
    final DataStream? stream = await _getDataStreamLocked(streamName);
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
    final DataStream? stream = await _getDataStreamLocked(streamName);
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
      final DataStream? stream = await _getDataStreamLocked(streamName);
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
      final DataStream? stream = await _getDataStreamLocked(streamName);
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
      final DataStream? stream = await _getDataStreamLocked(streamName);
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
      final DataStream? stream = await _getDataStreamLocked(streamName);
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
    // @TODO: remove some of the redundant isCoordinator checks
    // the controller most likely will throw if the node is not a coordinator.
    if (isCoordinator) {
      await _streamLock.synchronized(() async {
        final DataStream? stream = _dataStreams[streamName];
        if (stream != null) {
          await stream.destroyStream();
          _dataStreams.remove(streamName);
          logger.info('COORDINATOR Destroyed stream: $streamName');
        }
      });
    }
  }

  Future<void> sendUserMessage(
    String messageType,
    String description, [
    Map<String, dynamic>? payload,
    String? parentMessageId,
  ]) async {
    await _controller.sendUserMessage(
      messageType,
      description,
      payload ?? {},
      parentMessageId: parentMessageId,
    );
  }

  Future<void> updateConfig(Map<String, dynamic> config) async {
    await _controller.updateConfig(config);
  }

  // Convenience method for common coordination patterns
  Future<void> waitForMinNodes(int minNodes, {Duration? timeout}) async {
    if (connectedNodes.length >= minNodes) return;
    await waitForEvent<NodeJoinedEvent>(
      events.nodeJoined,
      (_) => connectedNodes.length >= minNodes,
      timeout: timeout,
      description: 'minimum of $minNodes nodes',
    );
  }

  /// Wait for a user message of the given [messageType] (the first positional
  /// argument passed to [sendUserMessage] on the sending node).
  ///
  /// Matches messages from either direction: coordinator broadcasts
  /// ([UserCoordinationEvent]) and participant-to-coordinator messages
  /// ([UserParticipantEvent]).
  Future<UserMessageEvent> waitForUserMessage(
    String messageType, {
    Duration? timeout,
  }) {
    return waitForEvent<UserMessageEvent>(
      events.userMessages,
      (event) => event.messageType == messageType,
      timeout: timeout,
      description: 'user message $messageType',
    );
  }

  Future<void> _disposeStreams() async {
    // Dispose streams
    await _streamLock.synchronized(() async {
      logger.finest('Disposing ${_dataStreams.length} data streams...');
      for (final stream in _dataStreams.values) {
        if (stream.started) {
          await stream.stop();
        }
        await stream.dispose();
      }
      _dataStreams.clear();
    });
  }

  @override
  Future<void> leave() async {
    if (!joined) {
      logger.warning('Not joined, cannot leave coordination session');
      return;
    }
    await super.leave();
    await _disposeStreams();
    // Dispose the controller first: it still needs the transport-managed
    // discovery resource and the coordination stream to announce leaving.
    logger.finest('Leaving coordination session...');
    await _controller.dispose();
    await _transport.dispose();

    logger.info('Left coordination session');
  }

  @override
  Future<void> dispose() async {
    if (joined) {
      await leave();
    }
    await super.dispose();
    await _lifecycleSubscription?.cancel();
    _lifecycleSubscription = null;
    await _departureSubscription?.cancel();
    _departureSubscription = null;

    logger.finest('Disposed coordination session');
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

/// Accumulates `streamReady` acks for one stream from the moment it is built.
///
/// See [PeerSession._collectStreamReadyAcks] for why collecting and awaiting
/// are separate steps.
class _StreamReadyAcks {
  _StreamReadyAcks({
    required this.streamName,
    required Set<String> expectedNodeUIds,
    required String selfUId,
    required Stream<StreamReadyEvent> acks,
  }) : _expected = expectedNodeUIds {
    // We never send ourselves an ack, so count ourselves in immediately.
    if (_expected.contains(selfUId)) {
      _ready.add(selfUId);
      logger.info('Coordinator marked self as ready for stream $streamName');
    }
    if (_isSatisfied) return;

    _subscription = acks.listen((event) {
      if (event.streamName != streamName) return;
      if (!_expected.contains(event.fromNodeUId)) return;
      if (!_ready.add(event.fromNodeUId)) return;
      logger.info(
        'Participant ${event.fromNodeUId} ready for stream $streamName '
        '(${_ready.length}/${_expected.length})',
      );
      if (_isSatisfied && !_satisfied.isCompleted) _satisfied.complete();
    });
  }

  final String streamName;
  final Set<String> _expected;
  final Set<String> _ready = {};
  final Completer<void> _satisfied = Completer<void>();
  StreamSubscription<StreamReadyEvent>? _subscription;

  bool get _isSatisfied => _ready.length >= _expected.length;

  /// Node ids expected but not yet heard from.
  Set<String> get missing => _expected.difference(_ready);

  /// Wait until every expected node has acked.
  ///
  /// Throws [TimeoutException] naming the missing nodes. Returns immediately
  /// when there is nothing to wait for — an empty expectation set, or acks
  /// that all landed before this was awaited.
  Future<void> wait({required Duration timeout}) async {
    if (_expected.isEmpty) {
      logger.info('No participants to wait for on stream $streamName');
      return;
    }
    if (_isSatisfied) {
      logger.info('All participants already ready for stream $streamName');
      return;
    }

    logger.info(
      'Waiting for ${_expected.length} participants to be ready for stream '
      '$streamName: $_expected',
    );

    try {
      await _satisfied.future.timeout(timeout);
    } on TimeoutException {
      logger.severe(
        'Timeout waiting for participants to be ready for stream $streamName. '
        'Missing: $missing',
      );
      throw TimeoutException(
        'Timeout waiting for participants to be ready for stream $streamName. '
        'Missing nodes: $missing',
        timeout,
      );
    }
    logger.info(
      'All ${_expected.length} participants ready for stream $streamName',
    );
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
