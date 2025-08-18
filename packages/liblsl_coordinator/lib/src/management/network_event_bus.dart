import 'dart:async';

/// Centralized event system for communication across all layers
abstract class NetworkEventBus {
  /// Publish an event to the bus
  void publish<T extends NetworkEvent>(T event);
  
  /// Subscribe to events of a specific type
  Stream<T> subscribe<T extends NetworkEvent>();
  
  /// Subscribe to all events
  Stream<NetworkEvent> get allEvents;
  
  /// Clear all subscriptions and cleanup
  Future<void> dispose();
}

/// Base class for all events in the system
abstract class NetworkEvent {
  final String eventId;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  
  const NetworkEvent({
    required this.eventId,
    required this.timestamp,
    this.metadata = const {},
  });
}

/// Simple in-memory implementation of NetworkEventBus
class InMemoryNetworkEventBus implements NetworkEventBus {
  final StreamController<NetworkEvent> _controller = StreamController<NetworkEvent>.broadcast();
  
  @override
  void publish<T extends NetworkEvent>(T event) {
    _controller.add(event);
  }
  
  @override
  Stream<T> subscribe<T extends NetworkEvent>() {
    return _controller.stream.where((event) => event is T).cast<T>();
  }
  
  @override
  Stream<NetworkEvent> get allEvents => _controller.stream;
  
  @override
  Future<void> dispose() async {
    await _controller.close();
  }
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
enum EventPriority {
  low,
  normal,
  high,
  critical,
}

/// Enhanced event with category and priority
abstract class CategorizedNetworkEvent extends NetworkEvent {
  final EventCategory category;
  final EventPriority priority;
  
  const CategorizedNetworkEvent({
    required super.eventId,
    required super.timestamp,
    required this.category,
    required this.priority,
    super.metadata = const {},
  });
}

/// System-wide events
class SystemStarted extends CategorizedNetworkEvent {
  SystemStarted() : super(
    eventId: 'system_started_${DateTime.now().millisecondsSinceEpoch}',
    timestamp: DateTime.now(),
    category: EventCategory.management,
    priority: EventPriority.high,
  );
}

class SystemStopped extends CategorizedNetworkEvent {
  SystemStopped() : super(
    eventId: 'system_stopped_${DateTime.now().millisecondsSinceEpoch}',
    timestamp: DateTime.now(),
    category: EventCategory.management,
    priority: EventPriority.high,
  );
}

class SystemError extends CategorizedNetworkEvent {
  final String error;
  final Object? cause;
  
  SystemError(this.error, [this.cause]) : super(
    eventId: 'system_error_${DateTime.now().millisecondsSinceEpoch}',
    timestamp: DateTime.now(),
    category: EventCategory.management,
    priority: EventPriority.critical,
    metadata: {
      'error': error,
      'cause': cause?.toString(),
    },
  );
}