import 'dart:async';

/// Extension to add safe event emission to StreamController
extension SafeStreamController<T> on StreamController<T> {
  /// Safely add an event to the stream controller if it's not closed
  ///
  /// This prevents the "Bad state: Cannot add new events after calling close"
  /// error that can occur during resource disposal when multiple components
  /// try to emit events to already-closed controllers.
  void addEvent(T event) {
    if (!isClosed) {
      add(event);
    }
  }

  /// Safely add an error to the stream controller if it's not closed
  void addErrorEvent(Object error, [StackTrace? stackTrace]) {
    if (!isClosed) {
      addError(error, stackTrace);
    }
  }
}
