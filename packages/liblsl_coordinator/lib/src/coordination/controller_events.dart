import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';

/// Sealed hierarchy for coordination controller events.
///
/// These events flow through the controller's single event stream,
/// replacing the previous multiple StreamController approach.
/// Use pattern matching (switch) for exhaustive handling.
sealed class ControllerEvent {
  final String fromNodeUId;
  final DateTime timestamp;

  ControllerEvent({required this.fromNodeUId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

// =============================================================================
// Phase Events
// =============================================================================

/// Emitted when the coordination phase changes.
final class PhaseChangedEvent extends ControllerEvent {
  final CoordinationPhase phase;

  PhaseChangedEvent({required this.phase, required super.fromNodeUId});
}

// =============================================================================
// Node Events
// =============================================================================

/// Base class for node-related events.
sealed class NodeEvent extends ControllerEvent {
  final Node node;

  NodeEvent({required this.node, required super.fromNodeUId});
}

/// Emitted when a node joins the coordination session.
final class NodeJoinedEvent extends NodeEvent {
  NodeJoinedEvent({required super.node, required super.fromNodeUId});
}

/// Emitted when a node leaves the coordination session.
final class NodeLeftEvent extends NodeEvent {
  NodeLeftEvent({required super.node, required super.fromNodeUId});
}

// =============================================================================
// Stream Lifecycle Events
// =============================================================================

/// Base class for stream lifecycle events.
sealed class StreamLifecycleEvent extends ControllerEvent {
  final String streamName;

  StreamLifecycleEvent({
    required this.streamName,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Command to create a data stream.
final class StreamCreateEvent extends StreamLifecycleEvent {
  final DataStreamConfig streamConfig;

  StreamCreateEvent({
    required super.streamName,
    required this.streamConfig,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Command to start a data stream.
final class StreamStartEvent extends StreamLifecycleEvent {
  final DataStreamConfig streamConfig;
  final DateTime? startAt;

  StreamStartEvent({
    required super.streamName,
    required this.streamConfig,
    this.startAt,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Notification that a stream is ready for operation.
final class StreamReadyEvent extends StreamLifecycleEvent {
  StreamReadyEvent({
    required super.streamName,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Command to stop a data stream.
final class StreamStopEvent extends StreamLifecycleEvent {
  StreamStopEvent({
    required super.streamName,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Command to pause a data stream.
final class StreamPauseEvent extends StreamLifecycleEvent {
  StreamPauseEvent({
    required super.streamName,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Command to resume a paused data stream.
final class StreamResumeEvent extends StreamLifecycleEvent {
  final bool flushBeforeResume;

  StreamResumeEvent({
    required super.streamName,
    this.flushBeforeResume = true,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Command to flush stream buffers.
final class StreamFlushEvent extends StreamLifecycleEvent {
  StreamFlushEvent({
    required super.streamName,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// Command to destroy a data stream.
final class StreamDestroyEvent extends StreamLifecycleEvent {
  StreamDestroyEvent({
    required super.streamName,
    required super.fromNodeUId,
    super.timestamp,
  });
}

// =============================================================================
// User Message Events
// =============================================================================

/// Base class for user-defined message events.
sealed class UserMessageEvent extends ControllerEvent {
  final String messageId;
  final String description;
  final Map<String, dynamic> payload;

  UserMessageEvent({
    required this.messageId,
    required this.description,
    required this.payload,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// User message from coordinator (broadcast to all).
final class UserCoordinationEvent extends UserMessageEvent {
  UserCoordinationEvent({
    required super.messageId,
    required super.description,
    required super.payload,
    required super.fromNodeUId,
    super.timestamp,
  });
}

/// User message from participant (to coordinator).
final class UserParticipantEvent extends UserMessageEvent {
  UserParticipantEvent({
    required super.messageId,
    required super.description,
    required super.payload,
    required super.fromNodeUId,
    super.timestamp,
  });
}

// =============================================================================
// Configuration Events
// =============================================================================

/// Configuration update from coordinator.
final class ConfigUpdateEvent extends ControllerEvent {
  final Map<String, dynamic> config;

  ConfigUpdateEvent({
    required this.config,
    required super.fromNodeUId,
    super.timestamp,
  });
}

// =============================================================================
// Extension for convenient Stream filtering
// =============================================================================

/// Extension methods for filtering controller event streams.
extension ControllerEventStreamExtensions on Stream<ControllerEvent> {
  /// Helper to filter and cast stream events by type.
  Stream<T> _ofType<T extends ControllerEvent>() =>
      where((event) => event is T).cast<T>();

  /// Filter to phase change events only.
  Stream<PhaseChangedEvent> get phaseChanges => _ofType<PhaseChangedEvent>();

  /// Filter to node joined events only.
  Stream<NodeJoinedEvent> get nodeJoined => _ofType<NodeJoinedEvent>();

  /// Filter to node left events only.
  Stream<NodeLeftEvent> get nodeLeft => _ofType<NodeLeftEvent>();

  /// Filter to all stream lifecycle events.
  Stream<StreamLifecycleEvent> get streamLifecycle =>
      _ofType<StreamLifecycleEvent>();

  /// Filter to stream create events only.
  Stream<StreamCreateEvent> get streamCreate => _ofType<StreamCreateEvent>();

  /// Filter to stream start events only.
  Stream<StreamStartEvent> get streamStart => _ofType<StreamStartEvent>();

  /// Filter to stream ready events only.
  Stream<StreamReadyEvent> get streamReady => _ofType<StreamReadyEvent>();

  /// Filter to stream stop events only.
  Stream<StreamStopEvent> get streamStop => _ofType<StreamStopEvent>();

  /// Filter to stream pause events only.
  Stream<StreamPauseEvent> get streamPause => _ofType<StreamPauseEvent>();

  /// Filter to stream resume events only.
  Stream<StreamResumeEvent> get streamResume => _ofType<StreamResumeEvent>();

  /// Filter to stream flush events only.
  Stream<StreamFlushEvent> get streamFlush => _ofType<StreamFlushEvent>();

  /// Filter to stream destroy events only.
  Stream<StreamDestroyEvent> get streamDestroy => _ofType<StreamDestroyEvent>();

  /// Filter to all user message events.
  Stream<UserMessageEvent> get userMessages => _ofType<UserMessageEvent>();

  /// Filter to coordinator user messages only.
  Stream<UserCoordinationEvent> get userCoordinationMessages =>
      _ofType<UserCoordinationEvent>();

  /// Filter to participant user messages only.
  Stream<UserParticipantEvent> get userParticipantMessages =>
      _ofType<UserParticipantEvent>();

  /// Filter to config update events only.
  Stream<ConfigUpdateEvent> get configUpdates => _ofType<ConfigUpdateEvent>();
}
