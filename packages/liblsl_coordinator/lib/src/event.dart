abstract class Event {
  final String eventId;

  const Event({required this.eventId});
}

abstract class TimestampedEvent extends Event {
  final DateTime timestamp;

  const TimestampedEvent({required super.eventId, required this.timestamp})
    : super();
}

abstract class AutoTimestampedEvent extends Event {
  final DateTime timestamp;

  AutoTimestampedEvent({required super.eventId, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now(),
      super();
}

/// Common base class for all stream-related events
abstract class StreamEvent extends TimestampedEvent {
  final String streamId;

  const StreamEvent(this.streamId, DateTime timestamp)
    : super(eventId: 'stream_event_$streamId', timestamp: timestamp);
}
