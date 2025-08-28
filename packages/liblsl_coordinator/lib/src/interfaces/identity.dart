import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';
export 'package:uuid/uuid.dart';

/// The default function to generate a unique ID.
/// Uses the [Uuid] package to generate a version 4 UUID.
/// This is a convenience function and [Uuid] is re-exported for direct use
/// if needed.
String generateUid() => Uuid().v4();

/// Basic identity interface
abstract interface class IIdentity {
  /// Returns a unique identifier for the identity.
  String get id;

  /// Returns a human-readable name for the identity.
  String get name;

  /// Returns a description of the identity.
  String? get description;
}

/// Interface for classes that have a globally unique identity.
abstract interface class IUniqueIdentity implements IIdentity {
  /// Returns a unique identifier that is guaranteed to be globally unique.
  String get uId;
}

/// Interface for classes that have a timestamp.
abstract interface class ITimestamped {
  /// Returns a timestamp for the object.
  /// This is intentionally generic, as it is not always going to be something
  /// specific like a creation time or modification time.
  DateTime get timestamp;
}

/// Mixin that provides automatic unique ID generation based on the
/// runtime type.
mixin RuntimeTypeUID on IUniqueIdentity {
  static final Map<Type, String> _idCache = {};

  @override
  String get uId => _idCache.putIfAbsent(runtimeType, () => Uuid().v4());
}

/// Mixin for per-instance unique IDs
mixin InstanceUID implements IUniqueIdentity {
  @protected
  String? shadowUId;

  @override
  String get uId => shadowUId ??= generateUid();
}
