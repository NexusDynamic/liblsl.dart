import 'dart:async';

import 'package:liblsl_coordinator/src/event.dart';

/// Abstract interface for managing resources with proper lifecycle
abstract class ResourceManager {
  /// Unique identifier for this resource manager
  String get managerId;

  /// Whether the manager is currently active
  bool get isActive;

  /// Initialize the resource manager
  Future<void> initialize();

  /// Start resource management operations
  Future<void> start();

  /// Stop resource management operations
  Future<void> stop();

  /// Cleanup all managed resources
  Future<void> dispose();

  /// Get current resource usage statistics
  ResourceUsageStats getUsageStats();

  /// Stream of resource events
  Stream<ResourceEvent> get events;
}

/// Resource usage statistics
class ResourceUsageStats {
  final int totalResources;
  final int activeResources;
  final int idleResources;
  final int erroredResources;
  final DateTime lastUpdated;
  final Map<String, dynamic> customMetrics;

  const ResourceUsageStats({
    required this.totalResources,
    required this.activeResources,
    required this.idleResources,
    required this.erroredResources,
    required this.lastUpdated,
    this.customMetrics = const {},
  });

  double get utilizationRate =>
      totalResources > 0 ? activeResources / totalResources : 0.0;
}

/// Resource lifecycle states
enum ResourceState {
  created,
  initializing,
  active,
  idle,
  stopping,
  stopped,
  error,
  disposed,
}

/// Managed resource interface
abstract class ManagedResource {
  /// Unique identifier for this resource
  String get resourceId;

  /// Current state of the resource (renamed to avoid conflicts with session state)
  ResourceState get resourceState;

  /// Metadata associated with this resource
  Map<String, dynamic> get metadata;

  /// Initialize the resource
  Future<void> initialize();

  /// Activate the resource
  Future<void> activate();

  /// Deactivate the resource (but keep it available)
  Future<void> deactivate();

  /// Cleanup and dispose the resource
  Future<void> dispose();

  /// Check if the resource is healthy
  Future<bool> healthCheck();

  /// Stream of resource state changes
  Stream<ResourceStateEvent> get stateChanges;
}

/// Resource events
sealed class ResourceEvent extends TimestampedEvent {
  final String resourceId;

  const ResourceEvent(this.resourceId, DateTime timestamp)
    : super(eventId: 'resource_event_$resourceId', timestamp: timestamp);
}

class ResourceCreated extends ResourceEvent {
  final String resourceType;
  final Map<String, dynamic> metadata;

  ResourceCreated(String resourceId, this.resourceType, this.metadata)
    : super(resourceId, DateTime.now());
}

class ResourceStateChanged extends ResourceEvent {
  final ResourceState oldState;
  final ResourceState newState;
  final String? reason;

  ResourceStateChanged(
    String resourceId,
    this.oldState,
    this.newState, [
    this.reason,
  ]) : super(resourceId, DateTime.now());
}

class ResourceError extends ResourceEvent {
  final String error;
  final Object? cause;

  ResourceError(String resourceId, this.error, [this.cause])
    : super(resourceId, DateTime.now());
}

class ResourceDisposed extends ResourceEvent {
  ResourceDisposed(String resourceId) : super(resourceId, DateTime.now());
}

/// State change events for individual resources
class ResourceStateEvent {
  final String resourceId;
  final ResourceState oldState;
  final ResourceState newState;
  final String? reason;
  final DateTime timestamp;

  const ResourceStateEvent({
    required this.resourceId,
    required this.oldState,
    required this.newState,
    this.reason,
    required this.timestamp,
  });
}
