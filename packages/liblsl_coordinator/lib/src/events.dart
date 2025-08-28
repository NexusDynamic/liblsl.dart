import 'package:liblsl_coordinator/framework.dart';

/// Enum representing different types of events.
enum EventType { system, data, coordination, user }

extension EventTypeExtension on EventType {
  String get shortString {
    switch (this) {
      case EventType.system:
        return 'system';
      case EventType.data:
        return 'data';
      case EventType.coordination:
        return 'coordination';
      case EventType.user:
        return 'user';
    }
  }

  static EventType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'system':
        return EventType.system;
      case 'data':
        return EventType.data;
      case 'coordination':
        return EventType.coordination;
      case 'user':
        return EventType.user;
      default:
        throw ArgumentError('Invalid EventType string: $value');
    }
  }
}

/// Base class for all events in the system.
sealed class Event
    with InstanceUID
    implements IHasMetadata, ITimestamped, ISerializable {
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
    String? uId,
  }) : timestamp = timestamp ?? DateTime.now(),
       name = name ?? 'event-$id',
       _metadata = metadata ?? {} {
    shadowUId = uId;
  }

  /// Gets a metadata value by key, returning [defaultValue] if the
  /// key is not found.
  @override
  dynamic getMetadata(String key, {dynamic defaultValue}) =>
      _metadata[key] ?? defaultValue;

  /// Converts the event to a map representation.
  @override
  Map<String, dynamic> toMap() {
    return {
      'uId': uId,
      'id': id,
      'name': name,
      'timestamp': timestamp.toIso8601String(),
      'eventType': eventType.toString(),
      'metadata': _metadata,
      'description': description,
    };
  }
}

/// System events, e.g., startup, shutdown, errors.
class SystemEvent extends Event {
  SystemEvent({
    required super.id,
    required super.description,
    String? name,
    super.timestamp,
    super.metadata,
    super.uId,
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
    super.uId,
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
    super.uId,
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
    super.uId,
  }) : super(name: name ?? 'user-event-$id', eventType: EventType.user);
}

class EventFactory {
  Event fromMap(Map<String, dynamic> map) {
    final eventTypeStr = map['eventType'] as String?;
    if (eventTypeStr == null) {
      throw ArgumentError('Event type is required in the map');
    }
    final eventType = EventTypeExtension.fromString(eventTypeStr);

    switch (eventType) {
      case EventType.system:
        return SystemEvent(
          id: map['id'],
          name: map['name'],
          description: map['description'] ?? '',
          timestamp:
              map['timestamp'] != null
                  ? DateTime.parse(map['timestamp'])
                  : null,
          metadata:
              map['metadata'] != null
                  ? Map<String, dynamic>.from(map['metadata'])
                  : null,
          uId: map['uId'],
        );
      case EventType.data:
        return DataEvent(
          id: map['id'],
          name: map['name'],
          description: map['description'] ?? '',
          timestamp:
              map['timestamp'] != null
                  ? DateTime.parse(map['timestamp'])
                  : null,
          metadata:
              map['metadata'] != null
                  ? Map<String, dynamic>.from(map['metadata'])
                  : null,
          uId: map['uId'],
        );
      case EventType.coordination:
        return CoordinationEvent(
          id: map['id'],
          name: map['name'],
          description: map['description'] ?? '',
          timestamp:
              map['timestamp'] != null
                  ? DateTime.parse(map['timestamp'])
                  : null,
          metadata:
              map['metadata'] != null
                  ? Map<String, dynamic>.from(map['metadata'])
                  : null,
          uId: map['uId'],
        );
      case EventType.user:
        return UserEvent(
          id: map['id'],
          name: map['name'],
          description: map['description'] ?? '',
          timestamp:
              map['timestamp'] != null
                  ? DateTime.parse(map['timestamp'])
                  : null,
          metadata:
              map['metadata'] != null
                  ? Map<String, dynamic>.from(map['metadata'])
                  : null,
          uId: map['uId'],
        );
    }
  }
}
