import 'package:meta/meta.dart';

abstract interface class IConfig {
  /// Validates the configuration
  @protected
  bool validate({bool throwOnError = false}) => true;

  /// Converts to map for serialization
  Map<String, dynamic> toMap();

  /// Creates a copy with modified values
  IConfig copyWith();
}

abstract interface class IConfigurable<T extends IConfig> {
  T get config;
}
