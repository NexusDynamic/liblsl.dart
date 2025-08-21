import 'package:meta/meta.dart';

abstract class InitializationRequired {
  /// Ensures that the required initialization has been performed.
  ///
  /// This method should be called before any other operations that depend on
  /// the initialization being complete.
  void ensureInitialized() {
    if (!initialized) {
      throw StateError('Required initialization has not been performed.');
    }
  }

  /// Indicates whether the required initialization has been completed.
  @protected
  bool get initialized;
}
