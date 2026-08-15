import 'dart:convert';
import 'package:peer_coordinator/framework.dart';

/// Base coordination message types
enum CoordinationMessageType {
  heartbeat,
  connectionTest,
  connectionTestResponse,
  joinOffer,
  joinRequest,
  joinAccept,
  joinReject,
  topologyUpdate,
  createStream,
  startStream,
  streamReady,
  stopStream,
  pauseStream,
  resumeStream,
  flushStream,
  destroyStream,
  userMessage,
  userParticipantMessage,
  configUpdate,
  nodeLeaving,
}

/// Base class for coordination messages with type safety
abstract class CoordinationMessage {
  final CoordinationMessageType type;
  final String messageId;
  final String? parentMessageId;
  final String fromNodeUId;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  /// Transport-observed timing for the message this was decoded from.
  ///
  /// Deliberately *not* part of [toMap]/[fromMap]: it describes the trip this
  /// message just made, so it is filled in on receipt rather than carried on
  /// the wire. Mutable so the controller can attach it at the decode site
  /// without every message subclass having to thread it through its factory.
  ///
  /// Null on locally-constructed (outgoing) messages.
  MessageTiming? transportTiming;

  /// The sender's [PeerClock] reading, in the sender's own clock domain, for
  /// transports that do not put a sender clock on the wire themselves.
  ///
  /// Stored in [metadata] so it round-trips through the existing wire format
  /// with no protocol change. See [NetworkStream.carriesSenderClock].
  static const String senderClockKey = 'sender_clock';

  double? get senderClock => (metadata[senderClockKey] as num?)?.toDouble();

  CoordinationMessage({
    required this.type,
    required this.fromNodeUId,
    String? messageId,
    this.parentMessageId,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) : timestamp = timestamp ?? DateTime.now(),
       messageId = messageId ?? generateUid(),
       metadata = metadata ?? {};

  Map<String, dynamic> toMap();

  factory CoordinationMessage.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final typeStr = map['type'] as String;
    final type = CoordinationMessageType.values.firstWhere(
      (t) => t.name == typeStr,
    );

    switch (type) {
      case CoordinationMessageType.heartbeat:
        return HeartbeatMessage.fromMap(map);
      case CoordinationMessageType.connectionTest:
        return ConnectionTestMessage.fromMap(map);
      case CoordinationMessageType.connectionTestResponse:
        return ConnectionTestResponseMessage.fromMap(map);
      case CoordinationMessageType.joinRequest:
        return JoinRequestMessage.fromMap(map);
      case CoordinationMessageType.joinAccept:
        return JoinAcceptMessage.fromMap(map);
      case CoordinationMessageType.joinReject:
        return JoinRejectMessage.fromMap(map);
      case CoordinationMessageType.topologyUpdate:
        return TopologyUpdateMessage.fromMap(map);
      case CoordinationMessageType.createStream:
        return CreateStreamMessage.fromMap(map);
      case CoordinationMessageType.startStream:
        return StartStreamMessage.fromMap(map);
      case CoordinationMessageType.streamReady:
        return StreamReadyMessage.fromMap(map);
      case CoordinationMessageType.stopStream:
        return StopStreamMessage.fromMap(map);
      case CoordinationMessageType.pauseStream:
        return PauseStreamMessage.fromMap(map);
      case CoordinationMessageType.resumeStream:
        return ResumeStreamMessage.fromMap(map);
      case CoordinationMessageType.flushStream:
        return FlushStreamMessage.fromMap(map);
      case CoordinationMessageType.destroyStream:
        return DestroyStreamMessage.fromMap(map);
      case CoordinationMessageType.userMessage:
        return UserCoordinationMessage.fromMap(map);
      case CoordinationMessageType.userParticipantMessage:
        return UserParticipantMessage.fromMap(map);
      case CoordinationMessageType.configUpdate:
        return ConfigUpdateMessage.fromMap(map);
      case CoordinationMessageType.nodeLeaving:
        return NodeLeavingMessage.fromMap(map);
      case CoordinationMessageType.joinOffer:
        return JoinOfferMessage.fromMap(map);
    }
  }

  String toJson() => jsonEncode(toMap());
}

class ConnectionTestMessage extends CoordinationMessage {
  final String testId;

  /// The peer this test is addressed to, or null to accept any responder.
  ///
  /// Coordination traffic has no addressing of its own: a participant's message
  /// reaches only the coordinator, but anything the *coordinator* sends is
  /// broadcast to every participant. Without a target, one coordinator-initiated
  /// probe would be answered by every participant at once.
  final String? toNodeUId;

  /// Identifies the clock-sync burst this probe belongs to, or null if this is
  /// an ordinary connection test rather than a clock probe.
  ///
  /// Replies quoting a wave that is no longer in flight are stale and dropped —
  /// see [PeerClockEstimator.addSample].
  final int? waveId;

  ConnectionTestMessage({
    required super.fromNodeUId,
    required this.testId,
    this.toNodeUId,
    this.waveId,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.connectionTest);

  /// Whether this message is meant for [nodeUId].
  bool addressedTo(String nodeUId) =>
      toNodeUId == null || toNodeUId == nodeUId;

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'testId': testId,
    if (toNodeUId != null) 'toNodeUId': toNodeUId,
    if (waveId != null) 'waveId': waveId,
    'metadata': metadata,
  };

  factory ConnectionTestMessage.fromMap(Map<String, dynamic> map) =>
      ConnectionTestMessage(
        fromNodeUId: map['fromNodeUId'],
        testId: map['testId'],
        toNodeUId: map['toNodeUId'] as String?,
        waveId: (map['waveId'] as num?)?.toInt(),
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class ConnectionTestResponseMessage extends CoordinationMessage {
  final String testId;
  final bool confirmed;

  /// The peer that sent the request, so the other participants this was
  /// broadcast to can ignore it. See [ConnectionTestMessage.toNodeUId].
  final String? toNodeUId;

  /// Echoed from the request. Null for a plain connection test.
  final int? waveId;

  /// `t0` — the requester's clock when it put the request on the wire, echoed
  /// back verbatim.
  ///
  /// Echoing it rather than having the requester remember it mirrors liblsl,
  /// whose responder writes `t0` straight back into the reply
  /// (`udp_server.cpp:160-163`), and spares the requester a per-probe table
  /// keyed on send time.
  final double? requestSenderClock;

  /// `t1` — the responder's clock when the request arrived.
  final double? requestReceivedClock;

  ConnectionTestResponseMessage({
    required super.fromNodeUId,
    required this.testId,
    required this.confirmed,
    this.toNodeUId,
    this.waveId,
    this.requestSenderClock,
    this.requestReceivedClock,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.connectionTestResponse);

  /// Whether this message is meant for [nodeUId].
  bool addressedTo(String nodeUId) =>
      toNodeUId == null || toNodeUId == nodeUId;

  /// Whether this reply carries the timestamps a clock probe needs.
  bool get isClockProbe =>
      waveId != null &&
      requestSenderClock != null &&
      requestReceivedClock != null;

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'testId': testId,
    'confirmed': confirmed,
    if (toNodeUId != null) 'toNodeUId': toNodeUId,
    if (waveId != null) 'waveId': waveId,
    if (requestSenderClock != null) 'requestSenderClock': requestSenderClock,
    if (requestReceivedClock != null)
      'requestReceivedClock': requestReceivedClock,
    'metadata': metadata,
  };

  factory ConnectionTestResponseMessage.fromMap(Map<String, dynamic> map) =>
      ConnectionTestResponseMessage(
        fromNodeUId: map['fromNodeUId'],
        testId: map['testId'],
        confirmed: map['confirmed'] ?? false,
        toNodeUId: map['toNodeUId'] as String?,
        waveId: (map['waveId'] as num?)?.toInt(),
        requestSenderClock: (map['requestSenderClock'] as num?)?.toDouble(),
        requestReceivedClock: (map['requestReceivedClock'] as num?)?.toDouble(),
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class HeartbeatMessage extends CoordinationMessage {
  final String nodeRole;
  final bool isCoordinator;

  HeartbeatMessage({
    required super.fromNodeUId,
    required this.nodeRole,
    required this.isCoordinator,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.heartbeat);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'nodeRole': nodeRole,
    'isCoordinator': isCoordinator,
    'metadata': metadata,
  };

  factory HeartbeatMessage.fromMap(Map<String, dynamic> map) =>
      HeartbeatMessage(
        fromNodeUId: map['fromNodeUId'],
        nodeRole: map['nodeRole'],
        isCoordinator: map['isCoordinator'] ?? false,
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class JoinOfferMessage extends CoordinationMessage {
  final String sessionId;
  final Node targetNode;

  JoinOfferMessage({
    required super.fromNodeUId,
    required this.sessionId,
    required this.targetNode,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinOffer);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'sessionId': sessionId,
    'targetNode': targetNode.config.toMap(),
    'metadata': metadata,
  };

  factory JoinOfferMessage.fromMap(Map<String, dynamic> map) =>
      JoinOfferMessage(
        fromNodeUId: map['fromNodeUId'],
        sessionId: map['sessionId'],
        targetNode: NodeFactory.createNodeFromConfig(
          NodeConfigFactory().fromMap(map['targetNode']),
        ),
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class JoinRequestMessage extends CoordinationMessage {
  final Node requestingNode;
  final String sessionId;

  JoinRequestMessage({
    required super.fromNodeUId,
    required this.requestingNode,
    required this.sessionId,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinRequest);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'requestingNode': requestingNode.config.toMap(),
    'sessionId': sessionId,
    'metadata': metadata,
  };

  factory JoinRequestMessage.fromMap(Map<String, dynamic> map) =>
      JoinRequestMessage(
        fromNodeUId: map['fromNodeUId'],
        requestingNode: NodeFactory.createNodeFromConfig(
          NodeConfigFactory().fromMap(map['requestingNode']),
        ),
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        sessionId: map['sessionId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class JoinAcceptMessage extends CoordinationMessage {
  final String acceptedNodeUId;
  final List<Node> currentTopology;

  JoinAcceptMessage({
    required super.fromNodeUId,
    required this.acceptedNodeUId,
    required this.currentTopology,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinAccept);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'acceptedNodeUId': acceptedNodeUId,
    'currentTopology': currentTopology.map((n) => n.config.toMap()).toList(),
    'metadata': metadata,
  };

  factory JoinAcceptMessage.fromMap(Map<String, dynamic> map) {
    final topology = (map['currentTopology'] as List)
        .map(
          (n) =>
              NodeFactory.createNodeFromConfig(NodeConfigFactory().fromMap(n)),
        )
        .toList();

    return JoinAcceptMessage(
      fromNodeUId: map['fromNodeUId'],
      acceptedNodeUId: map['acceptedNodeUId'],
      currentTopology: topology,
      messageId: map['messageId'],
      parentMessageId: map['parentMessageId'],
      timestamp: DateTime.parse(map['timestamp']),
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }
}

class JoinRejectMessage extends CoordinationMessage {
  final String rejectedNodeUId;
  final String reason;

  JoinRejectMessage({
    required super.fromNodeUId,
    required this.rejectedNodeUId,
    required this.reason,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinReject);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'rejectedNodeUId': rejectedNodeUId,
    'reason': reason,
    'metadata': metadata,
  };

  factory JoinRejectMessage.fromMap(Map<String, dynamic> map) =>
      JoinRejectMessage(
        fromNodeUId: map['fromNodeUId'],
        rejectedNodeUId: map['rejectedNodeUId'],
        reason: map['reason'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class CreateStreamMessage extends CoordinationMessage {
  final String streamName;
  final DataStreamConfig streamConfig;

  CreateStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    required this.streamConfig,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.createStream);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'streamConfig': streamConfig.toMap(),
    'metadata': metadata,
  };

  factory CreateStreamMessage.fromMap(Map<String, dynamic> map) =>
      CreateStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        streamConfig: DataStreamConfigFactory().fromMap(map['streamConfig']),
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class StartStreamMessage extends CoordinationMessage {
  final String streamName;
  final DataStreamConfig streamConfig;
  final DateTime? startAt; // Optional future start time

  StartStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    required this.streamConfig,
    this.startAt,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.startStream);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'streamConfig': streamConfig.toMap(),
    'startAt': startAt?.toIso8601String(),
    'metadata': metadata,
  };

  factory StartStreamMessage.fromMap(Map<String, dynamic> map) =>
      StartStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        streamConfig: DataStreamConfigFactory().fromMap(map['streamConfig']),
        startAt: map['startAt'] != null ? DateTime.parse(map['startAt']) : null,
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class StreamReadyMessage extends CoordinationMessage {
  final String streamName;

  StreamReadyMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.streamReady);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'metadata': metadata,
  };

  factory StreamReadyMessage.fromMap(Map<String, dynamic> map) =>
      StreamReadyMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class StopStreamMessage extends CoordinationMessage {
  final String streamName;

  StopStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.stopStream);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'metadata': metadata,
  };

  factory StopStreamMessage.fromMap(Map<String, dynamic> map) =>
      StopStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class PauseStreamMessage extends CoordinationMessage {
  final String streamName;

  PauseStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.pauseStream);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'metadata': metadata,
  };

  factory PauseStreamMessage.fromMap(Map<String, dynamic> map) =>
      PauseStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class ResumeStreamMessage extends CoordinationMessage {
  final String streamName;
  final bool flushBeforeResume;

  ResumeStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    this.flushBeforeResume = true,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.resumeStream);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'flushBeforeResume': flushBeforeResume,
    'metadata': metadata,
  };

  factory ResumeStreamMessage.fromMap(Map<String, dynamic> map) =>
      ResumeStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        flushBeforeResume: map['flushBeforeResume'] ?? true,
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class FlushStreamMessage extends CoordinationMessage {
  final String streamName;

  FlushStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.flushStream);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'metadata': metadata,
  };

  factory FlushStreamMessage.fromMap(Map<String, dynamic> map) =>
      FlushStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class DestroyStreamMessage extends CoordinationMessage {
  final String streamName;

  DestroyStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.destroyStream);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'timestamp': timestamp.toIso8601String(),
    'streamName': streamName,
    'metadata': metadata,
  };

  factory DestroyStreamMessage.fromMap(Map<String, dynamic> map) =>
      DestroyStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class UserCoordinationMessage extends CoordinationMessage {
  final String messageType;
  final String description;
  final Map<String, dynamic> payload;

  UserCoordinationMessage({
    required super.fromNodeUId,
    required this.messageType,
    required this.description,
    required this.payload,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.userMessage);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'timestamp': timestamp.toIso8601String(),
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'messageType': messageType,
    'description': description,
    'payload': payload,
    'metadata': metadata,
  };

  factory UserCoordinationMessage.fromMap(Map<String, dynamic> map) =>
      UserCoordinationMessage(
        fromNodeUId: map['fromNodeUId'],
        messageType: map['messageType'],
        description: map['description'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        payload: Map<String, dynamic>.from(map['payload'] ?? {}),
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class UserParticipantMessage extends CoordinationMessage {
  final String messageType;
  final String description;
  final Map<String, dynamic> payload;

  UserParticipantMessage({
    required super.fromNodeUId,
    required this.messageType,
    required this.description,
    required this.payload,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.userParticipantMessage);

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'fromNodeUId': fromNodeUId,
      'timestamp': timestamp.toIso8601String(),
      'messageId': messageId,
      'parentMessageId': parentMessageId,
      'messageType': messageType,
      'description': description,
      'payload': payload,
      'metadata': metadata,
    };
  }

  factory UserParticipantMessage.fromMap(Map<String, dynamic> map) =>
      UserParticipantMessage(
        fromNodeUId: map['fromNodeUId'],
        description: map['description'],
        messageType: map['messageType'],
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        payload: Map<String, dynamic>.from(map['payload'] ?? {}),
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class ConfigUpdateMessage extends CoordinationMessage {
  final Map<String, dynamic> config;

  ConfigUpdateMessage({
    required super.fromNodeUId,
    required this.config,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.configUpdate);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'timestamp': timestamp.toIso8601String(),
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'config': config,
    'metadata': metadata,
  };

  factory ConfigUpdateMessage.fromMap(Map<String, dynamic> map) =>
      ConfigUpdateMessage(
        fromNodeUId: map['fromNodeUId'],
        config: Map<String, dynamic>.from(map['config'] ?? {}),
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class TopologyUpdateMessage extends CoordinationMessage {
  final List<Node> topology;

  TopologyUpdateMessage({
    required super.fromNodeUId,
    required this.topology,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.topologyUpdate);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'timestamp': timestamp.toIso8601String(),
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'topology': topology.map((n) => n.config.toMap()).toList(),
    'metadata': metadata,
  };

  factory TopologyUpdateMessage.fromMap(
    Map<String, dynamic> map,
  ) => TopologyUpdateMessage(
    fromNodeUId: map['fromNodeUId'],
    topology: (map['topology'] as List)
        .map(
          (n) =>
              NodeFactory.createNodeFromConfig(NodeConfigFactory().fromMap(n)),
        )
        .toList(),
    timestamp: DateTime.parse(map['timestamp']),
    messageId: map['messageId'],
    parentMessageId: map['parentMessageId'],
    metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
  );
}

class NodeLeavingMessage extends CoordinationMessage {
  final String leavingNodeUId;

  NodeLeavingMessage({
    required super.fromNodeUId,
    required this.leavingNodeUId,
    super.messageId,
    super.parentMessageId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.nodeLeaving);

  @override
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'fromNodeUId': fromNodeUId,
    'timestamp': timestamp.toIso8601String(),
    'messageId': messageId,
    'parentMessageId': parentMessageId,
    'leavingNodeUId': leavingNodeUId,
    'metadata': metadata,
  };

  factory NodeLeavingMessage.fromMap(Map<String, dynamic> map) =>
      NodeLeavingMessage(
        fromNodeUId: map['fromNodeUId'],
        leavingNodeUId: map['leavingNodeUId'],
        timestamp: DateTime.parse(map['timestamp']),
        messageId: map['messageId'],
        parentMessageId: map['parentMessageId'],
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}
