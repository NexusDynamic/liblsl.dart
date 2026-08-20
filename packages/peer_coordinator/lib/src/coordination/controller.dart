import 'dart:async';
import 'dart:math';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/config.dart';

/// Controls the coordination flow with clear phases and event-driven logic.
///
/// Owns election, the heartbeat and node-timeout timers, the discovery loop,
/// and the coordinator/participant command API. None of that is
/// transport-specific: it talks to an [ITransport], a [CoordinationStream] and
/// an [IDiscovery], and the transport supplies whichever implementations it
/// has.
///
/// Emits all coordination events through a single [events] stream.
/// Use the [ControllerEventStreamExtensions] for convenient filtering.
class CoordinationController {
  final CoordinationConfig coordinationConfig;
  final ITransport transport;
  Node get thisNode => _thisNode;
  Node _thisNode;
  final CoordinationSession session;

  late final CoordinationState _state;
  late final CoordinationStream _coordinationStream;

  /// Whether [_coordinationStream] has been assigned.
  ///
  /// [_setupStateListeners] runs in the constructor, before [initialize], and
  /// the stream is `late final` — so the departure handler has to be able to
  /// tell "not yet" from "gone".
  bool _coordinationStreamReady = false;

  /// Clock-offset estimates for the coordination stream's peers.
  ///
  /// Worth exposing separately from the data streams' own `clockSyncs`: the
  /// coordination stream is up for the whole session, while data streams come
  /// and go with phases. It is therefore the only continuous record of how the
  /// peers' clocks are drifting — including across stretches where no data
  /// stream exists at all.
  ///
  /// Empty until [initialize] has built the stream, rather than throwing on the
  /// `late final`: a consumer subscribing early should get nothing, not a crash.
  Stream<ClockSyncSample> get coordinationClockSyncs =>
      _coordinationStreamReady
      ? _coordinationStream.clockSyncs
      : const Stream.empty();
  late final IDiscovery _discovery;

  bool _stopping = false;

  /// Guards against handling the same coordinator loss twice — the heartbeat
  /// timeout and an announced departure can both fire for one event.
  bool _handlingCoordinatorLoss = false;

  /// Why this session ended, for the error a later send throws. Null while live.
  SessionEndReason? _endReason;

  /// Tracks node UIDs with a pending inlet creation or join offer in progress,
  /// to prevent duplicate addInlet/sendJoinOffer calls every discovery cycle.
  final Set<String> _pendingJoinNodeUIds = {};

  CoordinatorMessageHandler? _coordinatorHandler;
  ParticipantMessageHandler? _participantHandler;

  Timer? _heartbeatTimer;
  Timer? _nodeTimeoutTimer;

  /// Estimates each peer's clock offset, or null when the transport does not
  /// need it. See [_clockSyncNeeded].
  ClockSyncService? _clockSync;
  StreamSubscription? _coordinationSubscription;
  StreamSubscription? _handlerSubscription;
  StreamSubscription? _handlerEventSubscription;
  StreamSubscription? _discoverySubscription;
  StreamSubscription? _stateEventSubscription;

  /// Single event stream for all coordination events.
  final StreamController<ControllerEvent> _eventController =
      StreamController<ControllerEvent>.broadcast();

  /// Single public stream for all coordination events.
  ///
  /// Use the extension methods for convenient filtering:
  /// ```dart
  /// controller.events.phaseChanges.listen((e) => ...);
  /// controller.events.streamCreate.listen((e) => ...);
  /// controller.events.nodeJoined.listen((e) => ...);
  /// ```
  Stream<ControllerEvent> get events => _eventController.stream;

  CoordinationPhase get currentPhase => _state.phase;
  bool get isCoordinator => _state.isCoordinator;
  String? get coordinatorUId => _state.coordinatorUId;
  List<Node> get connectedNodes => _state.connectedNodes;
  List<Node> get connectedParticipantNodes => _state.connectedParticipantNodes;

  CoordinationController({
    required this.coordinationConfig,
    required this.transport,
    required this._thisNode,
    required this.session,
  }) {
    _state = CoordinationState();
    _setupStateListeners();
  }

  void _setupStateListeners() {
    // Forward state events to the unified event stream
    _stateEventSubscription = _state.events.listen((event) {
      _eventController.add(event);
      // Clean up pending join tracking when a node successfully joins
      if (event is NodeJoinedEvent) {
        _pendingJoinNodeUIds.remove(event.node.uId);
      }
      // Every removal path funnels through here — voluntary leave, topology
      // update and the timeout sweep all go via state.removeNode — so this is
      // the one place that catches them all.
      if (event is NodeLeftEvent) {
        _untrackPeerClock(event.node.uId);
        // Release the coordination-stream inlet too. Inert on a relay
        // transport, but a peer-to-peer one holds a live connection behind it,
        // and there is no other point where it learns the peer is gone.
        if (_coordinationStreamReady) {
          unawaited(
            _coordinationStream.removeInlet(event.node.uId).catchError((
              Object e,
            ) {
              logger.warning(
                'Failed to remove coordination inlet for ${event.node.uId}: $e',
              );
            }),
          );
        }
      }
    });
  }

  /// Initialize the controller - creates streams and discovery
  Future<void> initialize() async {
    logger.info('Initializing coordination controller');

    // Create coordination stream
    final factory = transport.streamFactory;
    _coordinationStream = await factory.createCoordinationStream(
      coordinationConfig.streamConfig,
      session, // We'll manage this ourselves
    );
    _coordinationStreamReady = true;

    await _coordinationStream.create();
    await _coordinationStream.createOutlet();
    await _coordinationStream.start();

    // Create discovery
    _discovery = await transport.createDiscovery(
      streamConfig: coordinationConfig.streamConfig,
      coordinationConfig: coordinationConfig,
      id: 'coordination-discovery',
    );

    logger.info('Coordination controller initialized');
  }

  /// Start the coordination process - begins election
  /// TODO: Don't always become coordinator based on capabilities
  /// - instead, follow correct strategy. For now it's fine.
  Future<void> start([Duration? timeout]) async {
    if (_state.phase != CoordinationPhase.idle) {
      throw StateError('Coordination already started');
    }

    logger.info('Starting coordination process...');
    _state.transitionTo(CoordinationPhase.discovering);
    if (_thisNode.capabilities.contains(NodeCapability.coordinator) &&
        !_thisNode.capabilities.contains(NodeCapability.participant)) {
      logger.warning(
        'This node is required to become coordinator based on capabilities, skipping election',
      );
      // Must be the node-metadata key, not the LSL wire key: this used to
      // write 'random_roll' while every reader looked for 'randomRoll'.
      _thisNode.setMetadata(PeerMetadataKeys.randomRoll, '1.0');
      await _becomeCoordinator();
    } else {
      await _startElection(
        timeout != null ? timeout - Duration(seconds: 1) : null,
      );
    }
  }

  /// Election process - discover coordinators or become one
  Future<void> _startElection([Duration? timeout]) async {
    logger.info('Starting coordinator election');
    _state.transitionTo(CoordinationPhase.electing);

    // Not every TopologyConfig carries a promotion strategy; an unguarded
    // cast here crashed election for any other topology type.
    final topologyConfig = coordinationConfig.topologyConfig;
    final strategy = topologyConfig is HierarchicalTopologyConfig
        ? topologyConfig.promotionStrategy
        : PromotionStrategyFirst();
    final isRandomStrategy = strategy is PromotionStrategyRandom;

    // Build election predicate
    final myRandomRoll = isRandomStrategy
        ? double.tryParse(
                thisNode.metadata[PeerMetadataKeys.randomRoll]?.toString() ??
                    '',
              ) ??
              1.0
        : null;
    final myStartTime = !isRandomStrategy
        ? thisNode.metadata[PeerMetadataKeys.nodeStartedAt] as String?
        : null;

    final electionQuery = PeerQueries.election(
      streamName: coordinationConfig.streamConfig.name,
      sessionName: coordinationConfig.sessionConfig.name,
      excludeNodeUId: thisNode.uId,
      isRandomStrategy: isRandomStrategy,
      myRandomRoll: myRandomRoll,
      myStartTime: myStartTime,
    );

    logger.finest('Election query: $electionQuery');

    // Only the discovery call is caught here. Setting up a role used to be
    // inside the same try, so a participant that could not reach its coordinator
    // fell through to "become coordinator" — which in a re-election is how two
    // survivors both promote themselves and split the session in half. A failure
    // to *join* is now the caller's problem to retry.
    final List<PeerHandle> candidates;
    try {
      candidates = await _discovery.discoverOnce(
        electionQuery,
        timeout:
            timeout ??
            coordinationConfig.sessionConfig.discoveryInterval *
                2, // Shorter timeout
        minPeers: 1,
        maxPeers: 1,
      );
    } catch (e) {
      logger.warning('Election discovery failed, becoming coordinator: $e');
      await _becomeCoordinator();
      return;
    }

    if (candidates.isNotEmpty) {
      // Found better candidate or coordinator - become participant.
      // The handles are one-shot and unmanaged; we only needed to know
      // whether anything matched, so release them.
      for (final candidate in candidates) {
        await candidate.dispose();
      }
      logger.info(
        'Election: Found existing coordinator or better candidate, becoming participant',
      );
      await _becomeParticipant();
    } else if (!_thisNode.capabilities.contains(NodeCapability.coordinator)) {
      throw StateError(
        'Election: No coordinator found but this node is not eligible to be coordinator',
      );
    } else {
      // No better candidates - become coordinator
      logger.info(
        'Election: No existing coordinator or better candidate found, becoming coordinator',
      );
      await _becomeCoordinator();
    }
  }

  /// Become the coordinator
  Future<void> _becomeCoordinator() async {
    logger.finer('Becoming coordinator');

    // Update node role and recreate outlet
    final coordinatorNode = thisNode.asCoordinator;
    _thisNode = coordinatorNode;
    _coordinationStream.updateNode(coordinatorNode);
    await _coordinationStream.recreateOutlet();
    // add self to state
    _state.addNode(_thisNode);
    // Update state
    _state.becomeCoordinator(thisNode.uId);

    // Create coordinator handler
    _coordinatorHandler = CoordinatorMessageHandler(
      state: _state,
      thisNode: coordinatorNode,
      sessionConfig: coordinationConfig.sessionConfig,
    )..onConnectionProbeReply = _onConnectionProbeReply;

    // Start coordinator services
    await _startCoordinatorServices();

    // Transition to accepting phase immediately
    _state.transitionTo(CoordinationPhase.accepting);

    logger.fine('Coordinator ready, accepting nodes');
    if (coordinationConfig
        .sessionConfig
        .consumeCoordinationStreamAsCoordinator) {
      // Connect to own coordinator stream as participant
      await _connectToCoordinator(thisNode.uId);
    } else {
      logger.info('Not consuming own coordinator stream as per configuration');
    }
  }

  /// Become a participant
  Future<void> _becomeParticipant() async {
    logger.finer('Becoming participant');

    // Update node role and recreate outlet
    final participantNode = thisNode.asParticipant;
    _thisNode = participantNode;
    _coordinationStream.updateNode(participantNode);
    await _coordinationStream.recreateOutlet();

    // Update state
    _state.becomeParticipant();

    // Create participant handler
    _participantHandler =
        ParticipantMessageHandler(
            state: _state,
            thisNode: participantNode,
            sessionConfig: coordinationConfig.sessionConfig,
          )
          ..onConnectionProbeReply = _onConnectionProbeReply
          ..onSessionEnd = (message) =>
              unawaited(_onCoordinatorLost(message.reason));

    // Connect to coordinator
    await _connectToCoordinator();

    // Start participant services
    await _startParticipantServices();

    logger.fine('Participant connected to coordinator');
  }

  /// Connect to coordinator stream
  Future<void> _connectToCoordinator([String? coordinatorUId]) async {
    logger.finest(
      '[CONTROLLER-${thisNode.uId}] Connecting to coordinator: (maybe:? $coordinatorUId)',
    );
    final query = PeerQueries.coordinator(
      streamName: coordinationConfig.streamConfig.name,
      sessionName: coordinationConfig.sessionConfig.name,
      // If null, matches whichever node currently holds the role.
      coordinatorUId: coordinatorUId,
    );

    logger.finest('attempting to find the coordinator stream: $query');
    // TODO: Timeouts all round...
    final peers = await _discovery.discoverOnce(
      query,
      timeout: coordinationConfig.sessionConfig.discoveryInterval * 10,
      minPeers: 1,
      maxPeers: 1,
    );

    if (peers.isEmpty) {
      logger.severe(
        '[CONTROLLER-${thisNode.uId}] Failed to find coordinator stream',
      );
      throw StateError('Failed to find coordinator stream');
    }

    final coordinator = peers.first;
    logger.finer(
      '[CONTROLLER-${thisNode.uId}] Found coordinator stream, adding inlet...',
    );
    if (thisNode.uId != coordinatorUId) {
      final nodeUId = coordinator.descriptor.nodeUId;
      logger.fine(
        '[CONTROLLER-${thisNode.uId}] Connecting to coordinator stream of node $nodeUId as participant',
      );
      // set coordinator UId in state
      _state.becomeParticipant(nodeUId);
      // Seed the coordinator's liveness clock at the moment the relationship
      // begins. Without this there is no _lastHeartbeats entry for it — only
      // addNode creates one, and the coordinator is not in this node's
      // connectedNodes — so a coordinator that died before its first heartbeat
      // would never be seen as stale.
      _state.updateNodeHeartbeat(nodeUId);
    } else {
      logger.fine(
        '[CONTROLLER-${thisNode.uId}] Connected to own coordinator stream (self-coordination)',
      );
    }

    final coordinatorNodeUId = coordinator.descriptor.nodeUId;
    await _coordinationStream.addInlet(coordinator);
    // One inlet, one estimator — the receiver estimates its producer's clock,
    // exactly as liblsl runs a time_receiver per inlet.
    _trackPeerClock(coordinatorNodeUId);
    logger.info(
      '[CONTROLLER-${thisNode.uId}] Connected to coordinator stream '
      'successfully (${coordinator.descriptor})',
    );
  }

  /// Start coordinator-specific services
  Future<void> _startCoordinatorServices() async {
    // Listen to coordination messages
    _coordinationSubscription = _coordinationStream.inbox.listen(
      (message) async => await _handleIncomingMessage(message),
      onError: (error) => logger.severe(
        '[CONTROLLER-${thisNode.uId}] Error in coordination message stream: $error',
      ),
    );

    // Listen to outgoing messages from handler
    _handlerSubscription = _coordinatorHandler!.outgoingMessages.listen(
      _sendMessage,
    );

    // Forward handler events to the unified event stream
    _handlerEventSubscription = _coordinatorHandler!.events.listen((event) {
      _eventController.add(event);
      if (event is NodeJoinRejectedEvent) {
        // Allow the node to be offered a join again if capacity frees up.
        _pendingJoinNodeUIds.remove(event.rejectedNodeUId);
      }
    });

    // Start heartbeat
    _startHeartbeat();

    // Start node discovery
    _startNodeDiscovery();

    // Start node timeout checking
    _startNodeTimeoutCheck();
  }

  /// Start participant-specific services
  Future<void> _startParticipantServices() async {
    // Listen to coordination messages
    _coordinationSubscription = _coordinationStream.inbox.listen(
      (message) async => await _handleIncomingMessage(message),
      onError: (error) => logger.severe(
        '[CONTROLLER-${thisNode.uId}] Error in coordination message stream: $error',
      ),
    );

    // Listen to outgoing messages from handler
    _handlerSubscription = _participantHandler!.outgoingMessages.listen(
      _sendMessage,
    );

    // Forward handler events to the unified event stream
    _handlerEventSubscription = _participantHandler!.events.listen(
      _eventController.add,
    );

    // Send join request
    logger.info('Sending join request to coordinator');
    await _participantHandler!.sendJoinRequest();

    // Start heartbeat
    _startHeartbeat();

    // Watch the coordinator's heartbeat, so its going away is noticed rather
    // than waited on forever.
    _startNodeTimeoutCheck();
  }

  Future<void> _handleIncomingMessage(StringMessage message) async {
    try {
      final CoordinationMessage coordMessage;
      try {
        coordMessage = CoordinationMessage.fromJson(message.data.first);
        // Carry the transport's timing across the decode. Without this the
        // StringMessage — and everything the transport measured about the trip
        // it just made — goes out of scope here, which is why coordination
        // traffic used to be invisible to latency characterisation even though
        // the transport had already timed it.
        coordMessage.transportTiming = _timingFor(message, coordMessage);
      } catch (e) {
        logger.severe(
          '[CONTROLLER-${thisNode.uId}] Invalid coordination message JSON: $e\nRaw message data: ${message.data}',
        );
        return;
      }

      // Route to appropriate handler
      if (_coordinatorHandler?.canHandle(coordMessage.type) == true) {
        try {
          await _coordinatorHandler!.handleMessage(coordMessage);
        } catch (e) {
          logger.severe(
            '[CONTROLLER-${thisNode.uId}] Error in coordinator handler for ${coordMessage.type}: $e',
          );
        }
      } else if (_participantHandler?.canHandle(coordMessage.type) == true) {
        try {
          await _participantHandler!.handleMessage(coordMessage);
        } catch (e) {
          logger.severe(
            '[CONTROLLER-${thisNode.uId}] Error in participant handler for ${coordMessage.type}: $e',
          );
        }
      } else {
        logger.warning(
          '[CONTROLLER-${thisNode.uId}] No handler for message type: ${coordMessage.type}',
        );
      }
    } catch (e) {
      logger.severe(
        '[CONTROLLER-${thisNode.uId}] Failed to parse coordination message: $e\nRaw message data: ${message.data}',
      );
    }
  }

  /// Resolves the timing to attach to a decoded coordination message.
  ///
  /// Prefers what the transport measured. When the transport has no sender
  /// clock of its own, it stamped one into the envelope on the way out (see
  /// [_sendMessage]), so recover it here and pair it with a local reading.
  MessageTiming? _timingFor(
    StringMessage message,
    CoordinationMessage coordMessage,
  ) {
    final transportTiming = message.timing;
    if (transportTiming != null && transportTiming.sourceClock != null) {
      return transportTiming;
    }
    final senderClock = coordMessage.senderClock;
    if (senderClock == null) return transportTiming;

    // Zero only when both ends demonstrably read the same clock; otherwise the
    // estimator's value if it has one, else whatever the transport knows —
    // which for a cross-process transport with no estimate yet is null, so
    // transitSeconds stays null rather than reporting the difference of two
    // unrelated monotonic clocks.
    final double? clockOffset;
    final double? uncertainty;
    if (_coordinationStream.sharesSenderClockDomain) {
      clockOffset = 0.0;
      uncertainty = 0.0;
    } else {
      final peer = coordMessage.fromNodeUId;
      clockOffset =
          _clockSync?.offsets.offsetFor(peer) ?? transportTiming?.clockOffset;
      uncertainty =
          _clockSync?.offsets.uncertaintyFor(peer) ??
          transportTiming?.uncertainty;
    }

    return MessageTiming(
      sourceClock: senderClock,
      clockOffset: clockOffset,
      uncertainty: uncertainty,
      receivedClock: transportTiming?.receivedClock ?? PeerClock.now(),
      sourceId: transportTiming?.sourceId ?? coordMessage.fromNodeUId,
    );
  }

  /// Whether this transport needs a clock-offset estimate at all.
  ///
  /// LSL carries the sender's own clock and has real native corrections; the
  /// in-memory transport shares one clock, so its offset is a known zero.
  /// Neither should pay for probe traffic. That leaves the WebSocket transport,
  /// where the two peers' monotonic epochs are unrelated and nothing else
  /// reconciles them.
  bool get _clockSyncNeeded =>
      !_coordinationStream.carriesSenderClock &&
      !_coordinationStream.sharesSenderClockDomain;

  /// Per-peer clock offsets, or null when this transport does not estimate
  /// them. Shared with the transport so data streams read the same table.
  PeerClockOffsets? get clockOffsets => _clockSync?.offsets;

  void _startClockSync() {
    if (_clockSync != null || !_clockSyncNeeded) return;

    final config = coordinationConfig.sessionConfig.clockSyncConfig;
    _clockSync = ClockSyncService(
      config: config,
      offsets: transport.clockOffsets ?? PeerClockOffsets(),
      sendProbe: (peerUId, waveId, probeIndex) {
        if (_stopping) return;
        final handler = _activeHandler;
        if (handler == null) return;
        // Fire and forget: a probe that fails to send is one fewer sample in
        // the burst, which the minimum-probe gate already handles.
        unawaited(
          handler.sendConnectionProbe(peerUId, waveId, probeIndex).catchError((
            Object e,
          ) {
            logger.finer('Clock probe to $peerUId failed to send: $e');
          }),
        );
      },
    );
    logger.fine(
      '[CONTROLLER-${thisNode.uId}] Clock sync enabled '
      '(${config.timeProbeCount} probes every ${config.timeUpdateInterval})',
    );
  }

  /// Whichever handler is currently live. Probes go out through it because the
  /// role can flip mid-session and the estimators outlive the flip.
  ConnectionProbeMixin? get _activeHandler =>
      _state.isCoordinator ? _coordinatorHandler : _participantHandler;

  /// Begins probing a peer we have just taken an inlet from.
  ///
  /// Called at every `addInlet` site, which is what makes this per-inlet in the
  /// same sense liblsl means it: the receiver estimates, one estimator per
  /// producer it reads.
  void _trackPeerClock(String peerUId) {
    if (peerUId == thisNode.uId) return; // never probe ourselves
    _startClockSync();
    _clockSync?.trackPeer(peerUId);
  }

  /// Stops probing a peer whose inlet has gone away. A stale offset for a
  /// departed peer is worse than no offset.
  void _untrackPeerClock(String peerUId) => _clockSync?.untrackPeer(peerUId);

  /// Feeds a probe reply to the estimator, closing the NTP quadruple.
  ///
  /// `t0`/`t1` were echoed by the responder; `t2` is the reply's own sender
  /// stamp and `t3` its arrival stamp, both already on [MessageTiming] by the
  /// time a handler sees the message.
  void _onConnectionProbeReply(ConnectionTestResponseMessage reply) {
    final clockSync = _clockSync;
    if (clockSync == null) return;

    final t0 = reply.requestSenderClock;
    final t1 = reply.requestReceivedClock;
    final t2 = reply.senderClock;
    final t3 = reply.transportTiming?.receivedClock;
    final waveId = reply.waveId;
    if (t0 == null ||
        t1 == null ||
        t2 == null ||
        t3 == null ||
        waveId == null) {
      return;
    }

    clockSync.recordReply(
      reply.fromNodeUId,
      waveId,
      ClockProbeSample(t0: t0, t1: t1, t2: t2, t3: t3),
    );
  }

  Future<void> _sendMessage(CoordinationMessage message) async {
    logger.finest('[CONTROLLER-${thisNode.uId}] Sending ${message.type}');
    // Stamped at transmit rather than at construction: messages queue in the
    // handler's outgoing controller between the two, and the point of the
    // stamp is to time the wire, not the queue.
    //
    // Skipped for transports that already put a sender clock on the wire — an
    // LSL sample's timestamp is the sender's `lsl_local_clock()` reading, and a
    // second, weaker stamp beside it would only be something to disagree with.
    if (!_coordinationStream.carriesSenderClock) {
      message.metadata[CoordinationMessage.senderClockKey] = PeerClock.now();
    }
    final stringMessage = MessageFactory.stringMessage(
      data: IList([message.toJson()]),
      channels: 1,
    );
    await _coordinationStream.sendMessage(stringMessage);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      coordinationConfig.sessionConfig.heartbeatInterval,
      (_) async {
        if (_stopping) return;

        logger.finest('[${thisNode.uId}] Sending heartbeat');
        if (_state.isCoordinator) {
          // Coordinator sends heartbeat through normal message flow
          final heartbeat = HeartbeatMessage(
            fromNodeUId: thisNode.uId,
            nodeRole: thisNode.role,
            isCoordinator: true,
          );
          await _coordinatorHandler!.sendMessage(heartbeat);
        } else {
          // Participant sends heartbeat
          await _participantHandler!.sendHeartbeat();
        }
      },
    );
  }

  Future<void> _startNodeDiscovery() async {
    if (!_state.isCoordinator) return;

    await _discoverySubscription?.cancel();
    _discoverySubscription = _discovery.events.listen((discoveryEvent) {
      if (_stopping) return;
      if (discoveryEvent is PeersDiscoveredEvent) {
        for (final peer in discoveryEvent.peers) {
          try {
            final descriptor = peer.descriptor;
            final nodeUId = descriptor.nodeUId;
            final nodeId = descriptor.nodeId;
            final nodeRole = descriptor.nodeRole;
            if (nodeUId == thisNode.uId) {
              // Ignore our own stream
              continue;
            }
            if (_state.connectedNodes.any((n) => n.uId == nodeUId)) {
              // Already connected
              continue;
            }
            if (_pendingJoinNodeUIds.contains(nodeUId)) {
              // Inlet creation / join offer already in progress for this node
              logger.finer(
                'Join already in progress for node $nodeId ($nodeUId), skipping',
              );
              continue;
            }

            logger.info(
              'Discovered new node: $nodeId ($nodeUId), role: $nodeRole',
            );

            final nodeConfig = NodeConfig(
              id: nodeId,
              name: 'participant-$nodeId',
              uId: nodeUId,
              capabilities: {NodeCapability.participant},
              metadata: {'discoveredAt': DateTime.now().toIso8601String()},
            );
            final newNode = ParticipantNode(nodeConfig);

            // Ownership of the peer handle transfers to the stream inside
            // addInlet, which calls take() before touching it. That closes the
            // window in which the next discovery cycle could free the
            // underlying resource out from under us.
            _pendingJoinNodeUIds.add(nodeUId);

            _coordinationStream
                .addInlet(peer)
                .then((_) {
                  logger.finest(
                    'Added inlet for discovered node $nodeId ($nodeUId), sending join offer',
                  );
                  // Per inlet: the coordinator reads from this participant, so
                  // it estimates this participant's clock.
                  _trackPeerClock(nodeUId);
                  if (!_state.canAcceptNodes) {
                    logger.warning(
                      'Not accepting new nodes, skipping join offer to $nodeId ($nodeUId)',
                    );
                    _pendingJoinNodeUIds.remove(nodeUId);
                    return;
                  }
                  _coordinatorHandler!.sendJoinOffer(newNode);
                  // _pendingJoinNodeUIds entry removed via NodeJoinedEvent in
                  // _setupStateListeners once the node successfully joins.
                })
                .catchError((Object e, StackTrace st) {
                  _pendingJoinNodeUIds.remove(nodeUId);
                  logger.severe(
                    'Failed to add inlet for discovered node $nodeId ($nodeUId): $e',
                    e,
                    st,
                  );
                });
          } catch (e, st) {
            logger.severe(
              'Error processing discovered peer ${peer.descriptor}: $e',
              e,
              st,
            );
          }
        }
      } else if (discoveryEvent is DiscoveryTimeoutEvent) {
        logger.severe('Unexpected discovery timeout event received');
      }
    });

    _discovery.start(
      query: PeerQueries.participants(
        streamName: coordinationConfig.streamConfig.name,
        sessionName: coordinationConfig.sessionConfig.name,
      ),
    );
  }

  /// Starts the liveness sweep, for either role.
  ///
  /// Both roles need one, and they watch opposite directions: a coordinator
  /// evicts participants that go silent, a participant notices that its
  /// coordinator has. This used to return early for participants, which is why
  /// losing a coordinator was silent — the node kept heartbeating and sending
  /// into a stream nobody consumed, with nothing to ever notice.
  void _startNodeTimeoutCheck() {
    _nodeTimeoutTimer?.cancel();
    final nodeTimeout = coordinationConfig.sessionConfig.nodeTimeout;
    // Half the timeout. Computed in microseconds because
    // `Duration(seconds: nodeTimeout.inSeconds ~/ 2)` truncates to *zero* for any
    // timeout under two seconds — and a zero-duration periodic timer fires every
    // event-loop turn. The example's tests use 400ms.
    final period = Duration(microseconds: nodeTimeout.inMicroseconds ~/ 2);
    _nodeTimeoutTimer = Timer.periodic(period, (_) {
      if (_stopping) return;
      if (_state.isCoordinator) {
        _sweepStaleNodes(nodeTimeout);
      } else {
        _checkCoordinatorLiveness(nodeTimeout);
      }
    });
  }

  /// Coordinator side: drop participants that have gone silent.
  void _sweepStaleNodes(Duration nodeTimeout) {
    final staleNodes = _state.getStaleNodes(nodeTimeout);
    for (final nodeUId in staleNodes) {
      if (nodeUId == thisNode.uId) continue;
      logger.warning('Node $nodeUId timed out');
      // Best effort, and deliberately before the removal so the topology update
      // that follows is the last word: tell the node it is out, so it can stop
      // now rather than waiting out its own timer. It may well be unreachable —
      // that is why it is being evicted — so failure here is not interesting.
      unawaited(
        _coordinatorHandler!
            .broadcastSessionEnd(
              SessionEndReason.evicted,
              targetNodeUId: nodeUId,
            )
            .catchError((Object e) {
              logger.finer('Failed to notify evicted node $nodeUId: $e');
            }),
      );
      _state.removeNode(nodeUId);
      // A stale offset for a departed peer is worse than no offset.
      _untrackPeerClock(nodeUId);
      // Broadcast topology update will happen automatically via state listener
      _coordinatorHandler!.broadcastTopologyUpdate();
    }
  }

  /// Participant side: notice that the coordinator has gone silent.
  void _checkCoordinatorLiveness(Duration nodeTimeout) {
    final coordinatorUId = _state.coordinatorUId;
    // No coordinator recorded yet (still electing or joining), or we are our own
    // coordinator, in which case there is nothing to watch.
    if (coordinatorUId == null || coordinatorUId == thisNode.uId) return;
    if (!_state.isStale(coordinatorUId, nodeTimeout)) return;

    logger.warning(
      'Coordinator $coordinatorUId has been silent for more than $nodeTimeout',
    );
    unawaited(_onCoordinatorLost(SessionEndReason.coordinatorTimedOut));
  }

  // ===========================================================================
  // Coordinator loss
  // ===========================================================================

  /// Whether this session has ended and must not send anything further.
  bool get sessionEnded => _state.phase == CoordinationPhase.ended;

  /// Why the session ended, or null while it is live.
  SessionEndReason? get endReason => _endReason;

  /// Throws if the session is no longer able to send.
  ///
  /// The point is that a send after the coordinator has gone *fails loudly*
  /// instead of vanishing: a participant used to be able to keep publishing into
  /// a stream with no consumer indefinitely, with nothing to tell it or its
  /// application otherwise.
  void _ensureLive(String action) {
    if (_state.phase == CoordinationPhase.ended) {
      throw StateError(
        'Cannot $action: the coordination session has ended '
        '(${_endReason?.name ?? 'unknown reason'})',
      );
    }
    if (_state.phase == CoordinationPhase.disposing) {
      throw StateError('Cannot $action: the coordination session is disposing');
    }
  }

  /// The single funnel for "the coordinator is gone", whichever way we found out.
  ///
  /// What happens next is [CoordinationSessionConfig.coordinatorLossPolicy]; a
  /// [SessionEndedEvent] is emitted under every policy so an application has one
  /// place to listen regardless.
  Future<void> _onCoordinatorLost(SessionEndReason reason) async {
    // A timeout and an announced departure can both fire for the same event, and
    // the timer keeps ticking while an async policy runs.
    if (_handlingCoordinatorLoss || _stopping) return;
    if (_state.phase == CoordinationPhase.ended ||
        _state.phase == CoordinationPhase.disposing) {
      return;
    }
    _handlingCoordinatorLoss = true;

    final policy = coordinationConfig.sessionConfig.coordinatorLossPolicy;
    final lostCoordinatorUId = _state.coordinatorUId;
    logger.warning(
      '[CONTROLLER-${thisNode.uId}] Coordinator lost '
      '(${reason.name}); policy: ${policy.name}',
    );

    try {
      switch (policy) {
        case CoordinatorLossPolicy.remainOpen:
          _emitSessionEnded(reason, policy, lostCoordinatorUId);
        case CoordinatorLossPolicy.endSession:
          // Torn down before the event, so a listener that reacts by sending gets
          // the StateError rather than a silent no-op.
          await _endSession(reason);
          _emitSessionEnded(reason, policy, lostCoordinatorUId);
        case CoordinatorLossPolicy.reelect:
          await _teardownRole();
          _emitSessionEnded(reason, policy, lostCoordinatorUId);
          // Not awaited: this is called from a message handler or a timer tick,
          // and a re-election takes discovery timeouts to complete.
          unawaited(_reelect());
      }
    } finally {
      _handlingCoordinatorLoss = false;
    }
  }

  void _emitSessionEnded(
    SessionEndReason reason,
    CoordinatorLossPolicy policy,
    String? coordinatorUId,
  ) {
    if (_eventController.isClosed) return;
    _eventController.add(
      SessionEndedEvent(
        reason: reason,
        policy: policy,
        coordinatorUId: coordinatorUId,
        fromNodeUId: coordinatorUId ?? thisNode.uId,
      ),
    );
  }

  /// Stops this node coordinating or participating, without tearing down the
  /// transport — the application owns that, through `PeerSession.leave()`.
  Future<void> _endSession(SessionEndReason reason) async {
    _endReason = reason;
    // Silences the heartbeat and the discovery callbacks in one flag, the same
    // way dispose does.
    _stopping = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _nodeTimeoutTimer?.cancel();
    _nodeTimeoutTimer = null;
    _clockSync?.dispose();
    _clockSync = null;
    _discovery.stop();
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    _pendingJoinNodeUIds.clear();
    _state.clearNodes();
    _state.transitionTo(CoordinationPhase.ended);
  }

  /// Drops this node's role — timers, handlers, subscriptions, topology — while
  /// leaving the coordination stream and the transport up, so a new role can be
  /// established over the same connection.
  Future<void> _teardownRole() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _nodeTimeoutTimer?.cancel();
    _nodeTimeoutTimer = null;
    _discovery.stop();
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    await _coordinationSubscription?.cancel();
    _coordinationSubscription = null;
    await _handlerSubscription?.cancel();
    _handlerSubscription = null;
    await _handlerEventSubscription?.cancel();
    _handlerEventSubscription = null;
    _coordinatorHandler?.dispose();
    _coordinatorHandler = null;
    _participantHandler?.dispose();
    _participantHandler = null;
    _pendingJoinNodeUIds.clear();
    // Clears the clock estimators too, via NodeLeftEvent — the peer set is about
    // to change and a stale offset is worse than none.
    _state.clearNodes();
  }

  /// Re-runs the election among the survivors.
  ///
  /// The inlet to the departed coordinator is left in place: there is no
  /// remove-inlet in the stream contract, and it is inert — nothing arrives on
  /// it. The new coordinator publishes under a different endpoint, so
  /// [_connectToCoordinator] installs a fresh subscription rather than colliding
  /// with the dead one.
  Future<void> _reelect() async {
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_stopping || _state.phase == CoordinationPhase.ended) return;

      // Jittered, and before the first attempt as well: every survivor notices
      // the loss at roughly the same moment, and going straight into discovery in
      // lockstep is how they all fail to find each other's new role.
      await Future<void>.delayed(_reelectBackoff(attempt));
      if (_stopping || _state.phase == CoordinationPhase.ended) return;

      try {
        // A fresh election, which also means a fresh discovery query. That
        // matters on a relay transport, where live query results are only pushed
        // when the matching set *grows*: the survivors were already reported
        // under the old query id and would never be reported again.
        await _startElection();
        logger.info(
          '[CONTROLLER-${thisNode.uId}] Re-election complete as '
          '${_state.isCoordinator ? 'COORDINATOR' : 'PARTICIPANT'}',
        );
        return;
      } catch (e) {
        logger.warning(
          '[CONTROLLER-${thisNode.uId}] Re-election attempt '
          '$attempt/$maxAttempts failed: $e',
        );
        await _teardownRole();
      }
    }

    logger.severe(
      '[CONTROLLER-${thisNode.uId}] Re-election failed after $maxAttempts '
      'attempts; ending the session',
    );
    await _endSession(SessionEndReason.coordinatorTimedOut);
    _emitSessionEnded(
      SessionEndReason.coordinatorTimedOut,
      CoordinatorLossPolicy.reelect,
      null,
    );
  }

  /// Exponential-ish backoff with jitter, capped at the discovery interval.
  Duration _reelectBackoff(int attempt) {
    final base = coordinationConfig.sessionConfig.heartbeatInterval;
    final scaled = base * attempt;
    final capped = scaled > coordinationConfig.sessionConfig.discoveryInterval
        ? coordinationConfig.sessionConfig.discoveryInterval
        : scaled;
    // Full jitter over the window, so two survivors with identical config do not
    // wake at the same instant.
    return Duration(
      microseconds: _random.nextInt(max(1, capped.inMicroseconds)),
    );
  }

  static final Random _random = Random();

  // Public coordinator methods
  Future<void> pauseAcceptingNodes() async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can pause accepting nodes');
    }
    _coordinatorHandler!.pauseAcceptingNodes();
  }

  Future<void> resumeAcceptingNodes() async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can resume accepting nodes');
    }
    _coordinatorHandler!.resumeAcceptingNodes();
  }

  bool get isAcceptingNodes => _coordinatorHandler?.isAcceptingNodes ?? false;

  Future<void> createStream(String streamName, DataStreamConfig config) async {
    _ensureLive('create a stream');
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can create streams');
    }
    await _coordinatorHandler!.broadcastCreateStream(streamName, config);
  }

  Future<void> startStream(
    String streamName,
    DataStreamConfig config, {
    DateTime? startAt,
  }) async {
    _ensureLive('start a stream');
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can start streams');
    }
    await _coordinatorHandler!.broadcastStartStream(
      streamName,
      config,
      startAt: startAt,
    );
  }

  Future<void> markStreamReady(String streamName) async {
    if (_state.isCoordinator) {
      await _coordinatorHandler!.broadcastStreamReady(streamName);
    } else {
      await _participantHandler!.broadcastStreamReady(streamName);
    }
  }

  Future<void> stopStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can stop streams');
    }
    await _coordinatorHandler!.broadcastStopStream(streamName);
  }

  Future<void> pauseStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can pause streams');
    }
    await _coordinatorHandler!.broadcastPauseStream(streamName);
  }

  Future<void> resumeStream(
    String streamName, {
    bool flushBeforeResume = true,
  }) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can resume streams');
    }
    await _coordinatorHandler!.broadcastResumeStream(
      streamName,
      flushBeforeResume: flushBeforeResume,
    );
  }

  Future<void> flushStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can flush streams');
    }
    await _coordinatorHandler!.broadcastFlushStream(streamName);
  }

  Future<void> destroyStream(String streamName) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can destroy streams');
    }
    await _coordinatorHandler!.broadcastDestroyStream(streamName);
  }

  Future<void> sendUserMessage(
    String messageType,
    String description,
    Map<String, dynamic> payload, {
    String? parentMessageId,
  }) async {
    _ensureLive('send a user message');
    if (!_state.isCoordinator) {
      // @TODO: Implement properly
      await _participantHandler!.sendMessage(
        UserParticipantMessage(
          fromNodeUId: thisNode.uId,
          messageType: messageType,
          description: description,
          payload: payload,
          parentMessageId: parentMessageId,
        ),
      );
      return;
    }
    await _coordinatorHandler!.broadcastUserMessage(
      messageType,
      description,
      payload,
      parentMessageId,
    );
  }

  Future<void> updateConfig(Map<String, dynamic> config) async {
    if (!_state.isCoordinator) {
      throw StateError('Only coordinator can update config');
    }
    await _coordinatorHandler!.broadcastConfig(config);
  }

  /// Announces this node's departure and waits for it to reach the wire.
  ///
  /// Sent through [_sendMessage] directly rather than through a handler's
  /// outgoing queue: that queue is drained by a stream listener on a microtask,
  /// so `await handler.announceLeaving()` returned before anything had been
  /// written, and the stream teardown that follows raced it away —
  /// `WsStreamMixin.sendMessage` silently drops once disposed. That is why leave
  /// notices went missing.
  Future<void> _announceDeparture() async {
    // Nothing to announce: either the session already ended under us, or we never
    // took a role.
    if (_state.phase == CoordinationPhase.ended) return;

    final CoordinationMessage message;
    if (_state.isCoordinator) {
      if (_coordinatorHandler == null) return;
      // The counterpart to a participant's leave notice. Without it, every
      // survivor has to wait out nodeTimeout to discover that the session is
      // over.
      message = SessionEndMessage(
        fromNodeUId: thisNode.uId,
        reason: SessionEndReason.coordinatorLeft,
      );
    } else if (_participantHandler != null) {
      message = NodeLeavingMessage(
        fromNodeUId: thisNode.uId,
        leavingNodeUId: thisNode.uId,
      );
    } else {
      return;
    }

    try {
      logger.info('Announcing departure (${message.type.name})');
      await _sendMessage(message);
      // One turn of the event loop, so a transport that fans out on a microtask
      // (the in-memory bus) has handed the frame on before we tear down.
      await Future<void>.delayed(Duration.zero);
    } catch (e) {
      logger.warning('Failed to announce departure: $e');
    }
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    // Before the phase moves to disposing, because sendMessage on the stream is
    // gated on the stream's own state and this is the last chance to speak.
    await _announceDeparture();
    _state.transitionTo(CoordinationPhase.disposing);
    _stopping = true;
    logger.info('Disposing coordination controller');
    _heartbeatTimer?.cancel();
    _nodeTimeoutTimer?.cancel();
    // Cancels every in-flight probe and aggregation timer; a burst leaves up to
    // timeProbeCount + 1 of them pending, and the teardown-leak tests will
    // notice if any survives.
    _clockSync?.dispose();
    _clockSync = null;
    _discovery.stop();
    await _discoverySubscription?.cancel();
    await _stateEventSubscription?.cancel();
    await _handlerEventSubscription?.cancel();
    // The departure notice went out in _announceDeparture, before the phase
    // change — it used to be enqueued here and disposed away a line later.
    await _coordinationStream.dispose();
    _coordinatorHandler?.dispose();
    _participantHandler?.dispose();

    await _discovery.dispose();

    await _coordinationSubscription?.cancel();
    await _handlerSubscription?.cancel();

    _state.dispose();
    await _eventController.close();
    logger.info('Coordination controller disposed');
  }
}
