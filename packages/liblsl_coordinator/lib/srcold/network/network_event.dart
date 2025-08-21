import '../event.dart';

/// Base class for all events in the system
abstract class NetworkEvent extends AutoTimestampedEvent {
  final Map<String, dynamic> metadata;

  NetworkEvent({
    required super.eventId,
    super.timestamp,
    this.metadata = const {},
  }) : super();
}

/// Event categories for filtering and organization
enum EventCategory {
  network,
  session,
  node,
  stream,
  transport,
  protocol,
  management,
}

/// Event priority levels
enum EventPriority { low, normal, high, critical }

/// Enhanced event with category and priority
abstract class CategorizedNetworkEvent extends NetworkEvent {
  final EventCategory category;
  final EventPriority priority;

  CategorizedNetworkEvent({
    required super.eventId,
    required super.timestamp,
    required this.category,
    required this.priority,
    super.metadata = const {},
  });
}

/// System-wide events
class SystemStarted extends CategorizedNetworkEvent {
  SystemStarted()
    : super(
        eventId: 'system_started_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        category: EventCategory.management,
        priority: EventPriority.high,
      );
}

class SystemStopped extends CategorizedNetworkEvent {
  SystemStopped()
    : super(
        eventId: 'system_stopped_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        category: EventCategory.management,
        priority: EventPriority.high,
      );
}

class SystemError extends CategorizedNetworkEvent {
  final String error;
  final Object? cause;

  SystemError(this.error, [this.cause])
    : super(
        eventId: 'system_error_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        category: EventCategory.management,
        priority: EventPriority.critical,
        metadata: {'error': error, 'cause': cause?.toString()},
      );
}
