/// The only file in this example that talks to `peer_coordinator`.
///
/// Everything the UI needs is exposed as [ValueNotifier]s, so the widgets never
/// import the package and never have to know what a coordinator is.
///
/// ## How a chat line reaches everyone
///
/// `peer_coordinator`'s user-message channel is not a mesh. It is shaped by the
/// coordination topology:
///
/// * a coordinator's `sendUserMessage` reaches **every participant**, arriving
///   as a `UserCoordinationEvent`;
/// * a participant's `sendUserMessage` reaches **only the coordinator**,
///   arriving as a `UserParticipantEvent`. Other participants never see it.
///
/// So for a chat, the coordinator relays: when it receives a participant's
/// line it re-broadcasts the payload verbatim, which is what preserves the
/// original author. That is [_relay].
///
/// The consequence is that a line can arrive at a node more than once — most
/// obviously on the coordinator, which subscribes to its own coordination
/// stream when `consumeCoordinationStreamAsCoordinator` is true (the default),
/// so its own broadcast comes back to it. Rather than reason about which
/// echoes exist on which transport, every node renders its own line locally on
/// send and dedupes everything by [ChatMessage.id]. That is correct whether or
/// not the echo arrives.
///
/// This example deliberately does *not* use a `DataStream` for chat. A data
/// stream is the right tool for a fixed set of nodes sampling at a rate; late
/// joiners are not wired into an existing stream's inlets, which is exactly
/// what a chat room needs to tolerate.
///
/// ## The coordinator is the room's host
///
/// A room lasts exactly as long as its coordinator. That is
/// `CoordinatorLossPolicy.endSession`, chosen here rather than inherited: when
/// the coordinator goes — cleanly or by vanishing — every other node's session
/// ends, a `SessionEndedEvent` arrives, and everyone lands back on the connect
/// screen. Reconnecting builds a whole new [PeerSession], so whoever gets there
/// first finds nobody to defer to and hosts the new room.
///
/// The alternative, `CoordinatorLossPolicy.reelect`, would keep the room alive
/// under a new host. It is the better fit for a long-running measurement
/// session; it is a worse fit for a room, where "who is the host" and "which
/// room is this" are the same question.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:peer_coordinator/peer_coordinator.dart';

import 'chat_message.dart';

/// The `messageType` this app claims on the user-message channel. Anything
/// else on the channel is ignored, so the session can be shared with other
/// traffic.
const String chatMessageType = 'chat';

enum ChatStatus { idle, connecting, connected, disconnected, failed }

/// A joined chat room, backed by one [PeerSession].
class ChatSession {
  ChatSession({
    required this.displayName,
    required this.roomName,
    required this.transportConfig,
    this.maxNodes = 8,
    this.heartbeatInterval = const Duration(seconds: 2),
    this.discoveryInterval = const Duration(seconds: 2),
    this.nodeTimeout = const Duration(seconds: 6),
    this.coordinatorLossPolicy = CoordinatorLossPolicy.endSession,
  });

  /// This node's name, shown to everyone else. Travels as `NodeConfig.name`.
  final String displayName;

  /// The coordination session name. Nodes only find each other within a room.
  final String roomName;

  final int maxNodes;

  /// Coordination timings. The defaults suit a hand-driven chat over a LAN;
  /// tests turn them right down so a whole room elects and joins in
  /// milliseconds. `nodeTimeout` must stay at least twice `heartbeatInterval`
  /// or `CoordinationSessionConfig` rejects it.
  final Duration heartbeatInterval;
  final Duration discoveryInterval;
  final Duration nodeTimeout;

  /// What happens to this node when the coordinator goes away.
  ///
  /// Stated explicitly rather than left to the library default, because it is
  /// the whole shape of a chat room: [CoordinatorLossPolicy.endSession] makes
  /// the coordinator the room's host, so when it goes the room goes with it and
  /// everyone lands back on the connect screen. Whoever reconnects first then
  /// finds nobody to defer to and opens a new room as its host.
  ///
  /// [CoordinatorLossPolicy.reelect] would instead keep the room alive with a
  /// new host, which is the right choice for a long-running session but makes
  /// "the room" a much vaguer thing.
  final CoordinatorLossPolicy coordinatorLossPolicy;

  /// Which backend carries the coordination traffic. The app passes a
  /// [WebSocketTransportConfig]; the tests pass an in-memory one, which is why
  /// this is injected rather than built here.
  final ITransportConfig transportConfig;

  final ValueNotifier<List<ChatMessage>> messages = ValueNotifier(const []);
  final ValueNotifier<List<ChatMember>> roster = ValueNotifier(const []);
  final ValueNotifier<ChatStatus> status = ValueNotifier(ChatStatus.idle);
  final ValueNotifier<bool> isCoordinator = ValueNotifier(false);

  /// Why [connect] failed, if it did.
  String? failureReason;

  /// Why the room closed, if it did, as a sentence the UI can show unchanged.
  ///
  /// A string rather than the [SessionEndReason] itself so that the widgets keep
  /// their side of the bargain and never import `peer_coordinator`. Null while
  /// the room is live, and after a deliberate [leave] — there is nothing to
  /// explain about something the user did on purpose.
  String? endNotice;

  /// Why the room closed, for anything that needs to branch on it rather than
  /// display it.
  SessionEndReason? endReason;

  PeerSession? _session;
  final List<StreamSubscription<void>> _subscriptions = [];

  /// Ids of every line already rendered, so a relayed or echoed copy is
  /// dropped instead of shown twice.
  final Set<String> _seen = {};

  String get thisNodeUId => _session?.thisNode.uId ?? '';

  /// Joins the room. Throws nothing: failures land in [status] and
  /// [failureReason] so the UI can show them.
  Future<bool> connect({Duration timeout = const Duration(seconds: 15)}) async {
    if (status.value == ChatStatus.connecting) return false;
    status.value = ChatStatus.connecting;
    failureReason = null;

    final session = PeerSession.create(
      CoordinationConfig(
        name: 'peer_coordinator_chat',
        sessionConfig: CoordinationSessionConfig(
          name: roomName,
          maxNodes: maxNodes,
          heartbeatInterval: heartbeatInterval,
          discoveryInterval: discoveryInterval,
          nodeTimeout: nodeTimeout,
          coordinatorLossPolicy: coordinatorLossPolicy,
        ),
        topologyConfig: HierarchicalTopologyConfig(maxNodes: maxNodes),
        transportConfig: transportConfig,
      ),
      thisNodeConfig: NodeConfig(
        name: displayName,
        id: displayName,
        // Any node may end up coordinating; whoever finds no one to defer to
        // takes the role.
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
      ),
    );
    _session = session;

    // Subscribe before joining: `events` is a broadcast stream and buffers
    // nothing, so anything emitted during election would otherwise be missed.
    _subscriptions.add(session.events.userMessages.listen(_onUserMessage));
    _subscriptions.add(session.events.nodeJoined.listen(_onNodeJoined));
    _subscriptions.add(session.events.nodeLeft.listen(_onNodeLeft));
    _subscriptions.add(session.events.phaseChanges.listen(_onPhaseChanged));
    _subscriptions.add(session.events.sessionEnded.listen(_onSessionEnded));

    try {
      await session.initialize();
      await session.join(timeout);
    } catch (e) {
      failureReason = '$e';
      status.value = ChatStatus.failed;
      await _teardown();
      return false;
    }

    isCoordinator.value = session.isCoordinator;
    _refreshRoster();
    _addSystem(
      session.isCoordinator
          ? 'You are coordinating room "$roomName".'
          : 'Joined room "$roomName".',
    );
    status.value = ChatStatus.connected;
    return true;
  }

  /// Sends a line, and renders it locally straight away.
  ///
  /// Does nothing once the room has closed. The coordination layer would throw a
  /// [StateError] for a send after the session ended — which is the point of it,
  /// and much better than the line silently going nowhere — but a tap handler is
  /// not the place to surface that, and the UI already disables the composer.
  Future<void> send(String text) async {
    final session = _session;
    final trimmed = text.trim();
    if (session == null || trimmed.isEmpty) return;
    if (status.value != ChatStatus.connected) return;

    final message = ChatMessage(
      id: generateUid(),
      fromUId: session.thisNode.uId,
      fromName: displayName,
      text: trimmed,
      sentAt: DateTime.now(),
    );
    _add(message);
    await session.sendUserMessage(
      chatMessageType,
      trimmed,
      message.toPayload(),
    );
  }

  Future<void> leave() async {
    await _teardown();
    status.value = ChatStatus.disconnected;
  }

  void dispose() {
    unawaited(_teardown());
    messages.dispose();
    roster.dispose();
    status.dispose();
    isCoordinator.dispose();
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  void _onUserMessage(UserMessageEvent event) {
    if (event.messageType != chatMessageType) return;
    final message = ChatMessage.fromPayload(event.payload);
    if (message == null) return;

    // A participant's line only ever reaches the coordinator. Pass it on
    // before rendering, so the rest of the room is not waiting on the UI.
    if (event is UserParticipantEvent && (_session?.isCoordinator ?? false)) {
      unawaited(_relay(event));
    }
    _add(message);
  }

  /// Re-broadcasts a participant's line to the whole room.
  ///
  /// The payload is forwarded unchanged: it already carries the author's name,
  /// uId and id, so the relay is invisible to everyone downstream — and the
  /// unchanged id is what lets the original sender drop the copy that comes
  /// back to it.
  Future<void> _relay(UserParticipantEvent event) async {
    try {
      await _session?.sendUserMessage(
        chatMessageType,
        event.description,
        event.payload,
      );
    } catch (e) {
      debugPrint('chat relay failed: $e');
    }
  }

  void _onNodeJoined(NodeJoinedEvent event) {
    _refreshRoster();
    if (event.node.uId == thisNodeUId) return;
    _addSystem('${event.node.name} joined.');
  }

  void _onNodeLeft(NodeLeftEvent event) {
    _refreshRoster();
    _addSystem('${event.node.name} left.');
  }

  /// The room's host has gone, so the room has gone with it.
  ///
  /// Everything below the event is the coordination layer's doing: it has already
  /// stopped this node's timers, dropped the roster and made further sends
  /// throw. All that is left here is to say so and stand down.
  void _onSessionEnded(SessionEndedEvent event) {
    if (status.value == ChatStatus.disconnected) return;
    final notice = _endedMessage(event.reason);
    _addSystem(notice);
    endNotice = notice;
    endReason = event.reason;
    roster.value = const [];
    status.value = ChatStatus.disconnected;
    // Teardown, not disposal: the widgets still read the notifiers to render the
    // closing state, and ConnectPage disposes the session once the route pops.
    unawaited(_teardown());
  }

  String _endedMessage(SessionEndReason reason) => switch (reason) {
    SessionEndReason.coordinatorLeft =>
      'The room host left, so the room has closed.',
    SessionEndReason.coordinatorTimedOut =>
      'Lost contact with the room host. The room has closed.',
    SessionEndReason.coordinatorTransportLost =>
      'The connection to the room host dropped. The room has closed.',
    SessionEndReason.evicted => 'You were disconnected from the room.',
  };

  void _onPhaseChanged(PhaseChangedEvent event) {
    final session = _session;
    if (session == null) return;
    // Election can hand this node the coordinator role after the initial join.
    if (session.isCoordinator != isCoordinator.value) {
      isCoordinator.value = session.isCoordinator;
      if (session.isCoordinator) {
        _addSystem('You are now coordinating this room.');
      }
    }
    _refreshRoster();
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _add(ChatMessage message) {
    if (!_seen.add(message.id)) return;
    messages.value = [...messages.value, message];
  }

  void _addSystem(String text) {
    _add(ChatMessage.system(id: generateUid(), text: text));
  }

  /// `connectedNodes` is the coordinator's view of the room; whether it
  /// includes this node depends on the role, so merge it in and dedupe.
  void _refreshRoster() {
    final session = _session;
    if (session == null) return;
    // Once the room has closed there is no roster, and saying so once is enough.
    // Ending a session drops its topology node by node, so the NodeLeft events
    // land *after* the SessionEnded one and would otherwise rebuild the list
    // with this node alone in it.
    if (status.value == ChatStatus.disconnected) return;
    final byUId = <String, ChatMember>{
      session.thisNode.uId: ChatMember(
        uId: session.thisNode.uId,
        name: session.thisNode.name,
        isSelf: true,
        isCoordinator: session.isCoordinator,
      ),
    };
    for (final node in session.connectedNodes) {
      byUId.putIfAbsent(
        node.uId,
        () => ChatMember(
          uId: node.uId,
          name: node.name,
          isSelf: false,
          isCoordinator: node.uId == session.coordinatorUId,
        ),
      );
    }
    roster.value = byUId.values.toList(growable: false);
  }

  Future<void> _teardown() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await session.dispose();
    } catch (e) {
      debugPrint('chat session teardown: $e');
    }
  }
}

/// One node, as the roster shows it.
class ChatMember {
  const ChatMember({
    required this.uId,
    required this.name,
    required this.isSelf,
    required this.isCoordinator,
  });

  final String uId;
  final String name;
  final bool isSelf;
  final bool isCoordinator;
}
