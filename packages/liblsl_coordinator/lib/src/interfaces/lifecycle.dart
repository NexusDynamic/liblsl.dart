import 'dart:async';

abstract interface class ILifecycle {
  bool get created;
  bool get disposed;
  FutureOr<void> create();
  FutureOr<void> dispose();
}

abstract interface class IInitializable {
  /// Indicates whether the required initialization has been completed.
  bool get initialized;

  FutureOr<void> initialize();
}

abstract interface class IPausable {
  bool get paused;

  /// Pauses the lifecycle.
  FutureOr<void> pause();

  /// Resumes the lifecycle.
  FutureOr<void> resume();
}

abstract interface class IStartable {
  bool get started;
  bool get stopped;

  /// Starts the lifecycle.
  FutureOr<void> start();

  /// Stops the lifecycle.
  FutureOr<void> stop();
}

abstract interface class IJoinable {
  bool get joined;

  /// Joins the lifecycle, indicating that it is ready to be used.
  FutureOr<void> join();

  /// Leaves the lifecycle, indicating that it is no longer needed.
  FutureOr<void> leave();
}
