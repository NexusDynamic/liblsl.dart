import 'package:liblsl_coordinator/interfaces.dart';
import 'package:meta/meta.dart';

/// Interface for configuration classes.
abstract interface class IConfig implements ISerializable, IIdentity {
  /// Validates the configuration
  @protected
  bool validate({bool throwOnError = false}) => true;

  /// Creates a copy with modified values
  IConfig copyWith();

  @override
  @mustBeOverridden
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is IConfig &&
        other.runtimeType == runtimeType &&
        other.id == id &&
        other.name == name &&
        other.description == description;
  }

  @override
  @mustBeOverridden
  int get hashCode {
    return id.hashCode ^ name.hashCode ^ description.hashCode;
  }
}

/// Factory interface for creating configurations.
abstract interface class IConfigFactory<T extends IConfig> {
  /// Returns the default / basic config
  T defaultConfig();

  /// Creates a config from a map
  T fromMap(Map<String, dynamic> map);
}

/// Interface for classes that can be configured with an [IConfig]
/// implementation.
abstract interface class IConfigurable<T extends IConfig> {
  T get config;
}
