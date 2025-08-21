import 'package:liblsl_coordinator/interfaces.dart';
import 'package:meta/meta.dart';

class CoordinationSessionConfig implements IConfig {
  /// Human-readable name for the session.
  final String name;

  /// Maximum number of nodes allowed in the session.
  /// if [maxNodes] < 1, it means unlimited.
  final int maxNodes;

  /// Minimum number of nodes required in the session.
  final int minNodes;

  CoordinationSessionConfig({
    required this.name,
    this.maxNodes = 10,
    this.minNodes = 1,
  }) {
    validate(throwOnError: true);
  }

  /// Validates the configuration.
  @override
  bool validate({bool throwOnError = false}) {
    if (name.isEmpty) {
      if (throwOnError) {
        throw ArgumentError('Session name cannot be empty');
      }
      return false;
    }
    if (minNodes < 1) {
      if (throwOnError) {
        throw ArgumentError('Minimum nodes must be at least 1');
      }
      return false;
    }
    if (maxNodes >= 1 && maxNodes < minNodes) {
      if (throwOnError) {
        throw ArgumentError(
          'Max nodes must be greater than or equal to min nodes if specified',
        );
      }
      return false;
    }
    return true;
  }

  @override
  Map<String, dynamic> toMap() {
    return {'name': name, 'maxNodes': maxNodes, 'minNodes': minNodes};
  }

  @override
  String toString() {
    return 'NetworkSessionConfig(name: $name, maxNodes: $maxNodes, minNodes: $minNodes)';
  }

  @override
  CoordinationSessionConfig copyWith({
    String? name,
    int? maxNodes,
    int? minNodes,
  }) {
    return CoordinationSessionConfig(
      name: name ?? this.name,
      maxNodes: maxNodes ?? this.maxNodes,
      minNodes: minNodes ?? this.minNodes,
    );
  }
}

abstract class CoordinationSession
    implements
        IResourceManager,
        IInitializable,
        ILifecycle,
        IJoinable,
        IPausable,
        IUniqueIdentity,
        IConfigurable<CoordinationSessionConfig> {
  @override
  final CoordinationSessionConfig config;

  @override
  String get name => config.name;

  @override
  String get id => config.hashCode.toString();

  @override
  bool get created => _created;

  @override
  bool get initialized => _initialized;

  @override
  bool get joined => _joined;

  @override
  bool get disposed => _disposed;
  @override
  bool get paused => _paused;

  bool _created = false;
  bool _initialized = false;
  bool _joined = false;
  bool _disposed = false;
  bool _paused = false;

  /// Unique identifier for the session.
  CoordinationSession(this.config)
    : assert(config.validate(), 'Invalid session config');

  @override
  @mustCallSuper
  @mustBeOverridden
  Future<void> create() async {
    if (_created) return;
    _created = true;
  }

  @override
  @mustCallSuper
  @mustBeOverridden
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _created = false;
    _initialized = false;
    _joined = false;
    _paused = false;
  }

  @override
  @mustCallSuper
  @mustBeOverridden
  Future<void> initialize() async {
    if (_initialized) return;
    await create();
    _initialized = true;
  }

  @override
  @mustCallSuper
  @mustBeOverridden
  Future<void> join() async {
    if (_joined) return;
    _joined = true;
  }

  @override
  @mustCallSuper
  @mustBeOverridden
  Future<void> leave() async {
    if (!_joined) return;
    _joined = false;
  }

  @override
  @mustCallSuper
  @mustBeOverridden
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
  }
}
