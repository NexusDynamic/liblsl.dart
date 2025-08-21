import 'dart:collection';

// typedef DatabaseConfig = ({
//   String host,
//   int port,
//   String database,
//   String? username,
//   String? password,
//   int timeout,
//   bool useSSL,
// });

// extension DatabaseConfigValidation on DatabaseConfig {
//   bool validate() {
//     return host.isNotEmpty &&
//            database.isNotEmpty &&
//            port > 0 && port < 65536 &&
//            timeout > 0;
//   }

//   Map<String, dynamic> toMap() => {
//     'host': host,
//     'port': port,
//     'database': database,
//     if (username != null) 'username': username,
//     if (password != null) 'password': password,
//     'timeout': timeout,
//     'useSSL': useSSL,
//   };
// }

// final DatabaseConfig defaultDatabaseConfig = (
//   host: 'localhost',
//   port: 5432,
//   database: 'my_database',
//   username: null,
//   password: null,
//   timeout: 30,
//   useSSL: false,
// );

extension RecordProperties on Record {
  String ok() {
    this.
  }
}

abstract class Configuration<T extends Configurable, R extends Record> {
  /// keys
  R get record;

  Set<String> get requiredKeys;
  Set<String> get optionalKeys;
  bool get allowUnknownKeys => false;

  Configuration({required Map<String, dynamic> config}) {}

  /// Converts the configuration to a map.
  Map<String, dynamic> toMap();

  /// Validates the configuration.
  bool validate();

  bool keyIsValid(String key) {
    if (!allowUnknownKeys &&
        !requiredKeys.contains(key) &&
        !optionalKeys.contains(key)) {
      return false;
    }
    return true;
  }

  /// Applies the configuration to the given resource.
  void apply(T resource);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      
      final propertyName = _getPropertyName(invocation.memberName);
      
      // Try to get the value from the record using mirrors
      try {
        final instanceMirror = reflect(record);
        final fieldSymbol = Symbol(propertyName);
        return instanceMirror.getField(fieldSymbol).reflectee;
      } catch (e) {
        // If property doesn't exist in record, call super
        return super.noSuchMethod(invocation);
      }
    }
    
    // For non-getters, delegate to super
    return super.noSuchMethod(invocation);
  }
}

abstract class Configurable {
  Configuration get configuration;
}
