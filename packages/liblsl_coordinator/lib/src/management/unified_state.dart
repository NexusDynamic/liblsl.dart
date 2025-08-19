import 'resource_manager.dart';
import '../session/coordination_session.dart';

/// Unified lifecycle states that can represent both resource and session states
/// 
/// This enum unifies ResourceState and SessionState concepts since they
/// represent the same lifecycle from different perspectives
enum LifecycleState {
  /// Resource created but not initialized / Session not connected
  created,
  
  /// Resource initializing / Session discovering peers and joining
  initializing,
  
  /// Resource/Session fully active and operational
  active,
  
  /// Resource idle (initialized but not active) / Session connected but not active
  idle,
  
  /// Resource/Session stopping or leaving
  stopping,
  
  /// Resource stopped / Session disconnected
  stopped,
  
  /// Resource/Session in error state
  error,
  
  /// Resource fully disposed (terminal state)
  disposed,
}

/// Extensions to provide backward compatibility and semantic meaning
extension LifecycleStateExtensions on LifecycleState {
  /// Convert to legacy ResourceState for backward compatibility
  ResourceState get asResourceState {
    switch (this) {
      case LifecycleState.created:
        return ResourceState.created;
      case LifecycleState.initializing:
        return ResourceState.initializing;
      case LifecycleState.active:
        return ResourceState.active;
      case LifecycleState.idle:
        return ResourceState.idle;
      case LifecycleState.stopping:
        return ResourceState.stopping;
      case LifecycleState.stopped:
        return ResourceState.stopped;
      case LifecycleState.error:
        return ResourceState.error;
      case LifecycleState.disposed:
        return ResourceState.disposed;
    }
  }
  
  /// Convert to legacy SessionState for backward compatibility
  SessionState get asSessionState {
    switch (this) {
      case LifecycleState.created:
        return SessionState.disconnected;
      case LifecycleState.initializing:
        return SessionState.discovering; // Could also be joining
      case LifecycleState.active:
        return SessionState.active;
      case LifecycleState.idle:
        return SessionState.disconnected; // Idle sessions are effectively disconnected
      case LifecycleState.stopping:
        return SessionState.leaving;
      case LifecycleState.stopped:
        return SessionState.disconnected;
      case LifecycleState.error:
        return SessionState.error;
      case LifecycleState.disposed:
        return SessionState.disconnected; // Disposed sessions are disconnected
    }
  }
  
  /// Check if this state represents an operational state
  bool get isOperational => this == LifecycleState.active;
  
  /// Check if this state represents a transitional state
  bool get isTransitional => [
    LifecycleState.initializing,
    LifecycleState.stopping,
  ].contains(this);
  
  /// Check if this state represents a stable state
  bool get isStable => !isTransitional;
  
  /// Check if this state represents an error condition
  bool get isError => this == LifecycleState.error;
  
  /// Check if this state represents a terminal state (can't transition from)
  bool get isTerminal => [
    LifecycleState.disposed,
  ].contains(this);
  
  /// Check if this state represents an inactive state
  bool get isInactive => [
    LifecycleState.created,
    LifecycleState.idle,
    LifecycleState.stopped,
    LifecycleState.disposed,
  ].contains(this);
}

/// Create LifecycleState from ResourceState
LifecycleState lifecycleStateFromResourceState(ResourceState resourceState) {
  switch (resourceState) {
    case ResourceState.created:
      return LifecycleState.created;
    case ResourceState.initializing:
      return LifecycleState.initializing;
    case ResourceState.active:
      return LifecycleState.active;
    case ResourceState.idle:
      return LifecycleState.idle;
    case ResourceState.stopping:
      return LifecycleState.stopping;
    case ResourceState.stopped:
      return LifecycleState.stopped;
    case ResourceState.error:
      return LifecycleState.error;
    case ResourceState.disposed:
      return LifecycleState.disposed;
  }
}

/// Create LifecycleState from SessionState
LifecycleState lifecycleStateFromSessionState(SessionState sessionState) {
  switch (sessionState) {
    case SessionState.disconnected:
      return LifecycleState.stopped;
    case SessionState.discovering:
      return LifecycleState.initializing;
    case SessionState.joining:
      return LifecycleState.initializing;
    case SessionState.active:
      return LifecycleState.active;
    case SessionState.leaving:
      return LifecycleState.stopping;
    case SessionState.error:
      return LifecycleState.error;
  }
}