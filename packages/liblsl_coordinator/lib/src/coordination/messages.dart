import 'dart:convert';
import 'package:liblsl_coordinator/framework.dart';

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
  configUpdate,
  nodeLeaving,
}

/// Base class for coordination messages with type safety
abstract class CoordinationMessage {
  final CoordinationMessageType type;
  final String fromNodeUId;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  CoordinationMessage({
    required this.type,
    required this.fromNodeUId,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  })  : timestamp = timestamp ?? DateTime.now(),
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

  ConnectionTestMessage({
    required super.fromNodeUId,
    required this.testId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.connectionTest);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'testId': testId,
        'metadata': metadata,
      };

  factory ConnectionTestMessage.fromMap(Map<String, dynamic> map) =>
      ConnectionTestMessage(
        fromNodeUId: map['fromNodeUId'],
        testId: map['testId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class ConnectionTestResponseMessage extends CoordinationMessage {
  final String testId;
  final bool confirmed;

  ConnectionTestResponseMessage({
    required super.fromNodeUId,
    required this.testId,
    required this.confirmed,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.connectionTestResponse);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'testId': testId,
        'confirmed': confirmed,
        'metadata': metadata,
      };

  factory ConnectionTestResponseMessage.fromMap(Map<String, dynamic> map) =>
      ConnectionTestResponseMessage(
        fromNodeUId: map['fromNodeUId'],
        testId: map['testId'],
        confirmed: map['confirmed'] ?? false,
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.heartbeat);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinOffer);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinRequest);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinAccept);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'acceptedNodeUId': acceptedNodeUId,
        'currentTopology':
            currentTopology.map((n) => n.config.toMap()).toList(),
        'metadata': metadata,
      };

  factory JoinAcceptMessage.fromMap(Map<String, dynamic> map) =>
      JoinAcceptMessage(
        fromNodeUId: map['fromNodeUId'],
        acceptedNodeUId: map['acceptedNodeUId'],
        currentTopology: (map['currentTopology'] as List)
            .map(
              (n) => NodeFactory.createNodeFromConfig(
                NodeConfigFactory().fromMap(n),
              ),
            )
            .toList(),
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class JoinRejectMessage extends CoordinationMessage {
  final String rejectedNodeUId;
  final String reason;

  JoinRejectMessage({
    required super.fromNodeUId,
    required this.rejectedNodeUId,
    required this.reason,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.joinReject);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.createStream);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.startStream);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
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
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class StreamReadyMessage extends CoordinationMessage {
  final String streamName;

  StreamReadyMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.streamReady);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'streamName': streamName,
        'metadata': metadata,
      };

  factory StreamReadyMessage.fromMap(Map<String, dynamic> map) =>
      StreamReadyMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class StopStreamMessage extends CoordinationMessage {
  final String streamName;

  StopStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.stopStream);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'streamName': streamName,
        'metadata': metadata,
      };

  factory StopStreamMessage.fromMap(Map<String, dynamic> map) =>
      StopStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class PauseStreamMessage extends CoordinationMessage {
  final String streamName;

  PauseStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.pauseStream);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'streamName': streamName,
        'metadata': metadata,
      };

  factory PauseStreamMessage.fromMap(Map<String, dynamic> map) =>
      PauseStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.resumeStream);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
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
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class FlushStreamMessage extends CoordinationMessage {
  final String streamName;

  FlushStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.flushStream);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'streamName': streamName,
        'metadata': metadata,
      };

  factory FlushStreamMessage.fromMap(Map<String, dynamic> map) =>
      FlushStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class DestroyStreamMessage extends CoordinationMessage {
  final String streamName;

  DestroyStreamMessage({
    required super.fromNodeUId,
    required this.streamName,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.destroyStream);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'streamName': streamName,
        'metadata': metadata,
      };

  factory DestroyStreamMessage.fromMap(Map<String, dynamic> map) =>
      DestroyStreamMessage(
        fromNodeUId: map['fromNodeUId'],
        streamName: map['streamName'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class UserCoordinationMessage extends CoordinationMessage {
  final String messageId;
  final String description;
  final Map<String, dynamic> payload;

  UserCoordinationMessage({
    required super.fromNodeUId,
    required this.messageId,
    required this.description,
    required this.payload,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.userMessage);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'messageId': messageId,
        'description': description,
        'payload': payload,
        'metadata': metadata,
      };

  factory UserCoordinationMessage.fromMap(Map<String, dynamic> map) =>
      UserCoordinationMessage(
        fromNodeUId: map['fromNodeUId'],
        messageId: map['messageId'],
        description: map['description'],
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
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.configUpdate);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'config': config,
        'metadata': metadata,
      };

  factory ConfigUpdateMessage.fromMap(Map<String, dynamic> map) =>
      ConfigUpdateMessage(
        fromNodeUId: map['fromNodeUId'],
        config: Map<String, dynamic>.from(map['config'] ?? {}),
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class TopologyUpdateMessage extends CoordinationMessage {
  final List<Node> topology;

  TopologyUpdateMessage({
    required super.fromNodeUId,
    required this.topology,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.topologyUpdate);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'topology': topology.map((n) => n.config.toMap()).toList(),
        'metadata': metadata,
      };

  factory TopologyUpdateMessage.fromMap(Map<String, dynamic> map) =>
      TopologyUpdateMessage(
        fromNodeUId: map['fromNodeUId'],
        topology: (map['topology'] as List)
            .map(
              (n) => NodeFactory.createNodeFromConfig(
                NodeConfigFactory().fromMap(n),
              ),
            )
            .toList(),
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}

class NodeLeavingMessage extends CoordinationMessage {
  final String leavingNodeUId;

  NodeLeavingMessage({
    required super.fromNodeUId,
    required this.leavingNodeUId,
    super.timestamp,
    super.metadata,
  }) : super(type: CoordinationMessageType.nodeLeaving);

  @override
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'fromNodeUId': fromNodeUId,
        'timestamp': timestamp.toIso8601String(),
        'leavingNodeUId': leavingNodeUId,
        'metadata': metadata,
      };

  factory NodeLeavingMessage.fromMap(Map<String, dynamic> map) =>
      NodeLeavingMessage(
        fromNodeUId: map['fromNodeUId'],
        leavingNodeUId: map['leavingNodeUId'],
        timestamp: DateTime.parse(map['timestamp']),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
}
