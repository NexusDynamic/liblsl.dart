import 'dart:async';

/// Interface for managing the lifecycle of an object.
abstract interface class ILifecycle {
  /// Indicates whether the [ILifecycle] implementation has been created.
  bool get created;

  /// Indicates whether the [ILifecycle] implementation has been disposed.
  bool get disposed;

  /// Creates.
  FutureOr<void> create();

  /// Disposes the [ILifecycle] implementation, releasing any resources.
  FutureOr<void> dispose();
}

/// Interface for classes that can be initialized.
abstract interface class IInitializable {
  /// Indicates whether the required initialization has been completed.
  bool get initialized;

  /// Initializes the lifecycle, preparing it for use.
  FutureOr<void> initialize();
}

/// Interface for classes that can be paused and resumed.
abstract interface class IPausable {
  bool get paused;

  /// Pauses the implementation.
  FutureOr<void> pause();

  /// Resumes the implementation.
  FutureOr<void> resume();
}

/// Interface for classes that can be started and stopped.
abstract interface class IStartable {
  /// Indicates whether the [IStartable] has been started.
  bool get started;

  /// Indicates whether the [IStartable] has been stopped.
  bool get stopped;

  /// Starts the lifecycle.
  FutureOr<void> start();

  /// Stops the lifecycle.
  FutureOr<void> stop();
}

/// Interface for classes that can join and leave.
abstract interface class IJoinable {
  /// Indicates whether the [IJoinable] is currently joined.
  bool get joined;

  /// Join
  FutureOr<void> join();

  /// Leaves
  FutureOr<void> leave();
}
