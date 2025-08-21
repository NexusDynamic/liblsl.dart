import 'package:uuid/uuid.dart';

abstract interface class IIdentity {
  /// Returns a unique identifier for the identity.
  String get id;

  /// Returns a human-readable name for the identity.
  String get name;

  /// Returns a description of the identity.
  String? get description;
}

abstract interface class IUniqueIdentity extends IIdentity {
  /// Returns a unique identifier that is guaranteed to be globally unique.
  final String uId = Uuid().v4();
}
