import 'package:liblsl_coordinator/framework.dart';

/// Enum representing different types of events.
enum EventType { system, data, coordination, user }

/// Base class for all events in the system.
sealed class Event
    with InstanceUID
    implements IHasMetadata, ITimestamped, IUniqueIdentity, ISerializable {
  /// User-specified identifier for the event, for the message UID
  /// see [InstanceUID.uId]
  @override
  final String id;

  /// Name of the event (~ category / type)
  @override
  final String name;

  /// Timestamp of the event
  @override
  final DateTime timestamp;

  /// Event message / description
  @override
  final String description;

  /// Metadata associated with the event
  late final Map<String, dynamic> _metadata;

  /// Metadata associated with the event
  @override
  Map<String, dynamic> get metadata => Map.unmodifiable(_metadata);
  final EventType eventType;

  /// Creates a new [Event] with the given parameters.
  /// If [timestamp] is not provided, the current time is used.
  /// If [name] is not provided, a default name based on the event ID is used.
  Event({
    required this.id,
    String? name,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
    this.eventType = EventType.user,
    required this.description,
  }) : timestamp = timestamp ?? DateTime.now(),
       name = name ?? 'event-$id',
       _metadata = metadata ?? {};

  /// Gets a metadata value by key, returning [defaultValue] if the
  /// key is not found.
  @override
  dynamic getMetadata(String key, {dynamic defaultValue}) =>
      _metadata[key] ?? defaultValue;

  /// Converts the event to a map representation.
  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'timestamp': timestamp.toIso8601String(),
      'eventType': eventType.toString(),
      'metadata': _metadata,
    };
  }
}

/// System events, e.g., startup, shutdown, errors.
sealed class SystemEvent extends Event {
  SystemEvent({
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(name: name ?? 'system-event-$id', eventType: EventType.system);
}

/// Data events, e.g. sample received, sample sent.
class DataEvent extends Event {
  DataEvent({
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(name: name ?? 'data-event-$id', eventType: EventType.data);
}

/// Coordination events, e.g., node joined, node left, stream added.
class CoordinationEvent extends Event {
  CoordinationEvent({
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(
         name: name ?? 'coordination-event-$id',
         eventType: EventType.coordination,
       );
}

/// User-defined events.
class UserEvent extends Event {
  UserEvent({
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(name: name ?? 'user-event-$id', eventType: EventType.user);
}

/// Event for controlling data stream operations
class StreamControlEvent extends CoordinationEvent {
  /// The action to perform (start, stop, pause, resume)
  final String action;
  
  /// The name/ID of the stream to control
  final String streamName;
  
  StreamControlEvent({
    required this.action,
    required this.streamName,
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(name: name ?? 'stream-control-$id');
  
  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map['action'] = action;
    map['streamName'] = streamName;
    return map;
  }
}

/// Discovery events for stream resolution
abstract class DiscoveryEvent extends CoordinationEvent {
  DiscoveryEvent({
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
  }) : super(name: name ?? 'discovery-event-$id');
}
