import 'package:uuid/uuid.dart';

abstract class Identity {
  /// Returns a unique identifier for the identity.
  String get id;

  /// Returns a human-readable name for the identity.
  String get name;

  /// Returns a description of the identity.
  String? get description;
}

abstract class UniqueIdentity extends Identity {
  /// Returns a unique identifier that is guaranteed to be globally unique.
  String get uId;
  static const Uuid _uuid = Uuid();

  static String generateUniqueId() {
    return _uuid.v4();
  }
}
