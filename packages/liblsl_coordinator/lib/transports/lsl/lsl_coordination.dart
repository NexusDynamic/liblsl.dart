import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:meta/meta.dart';

/// LSL Resource implementation using [InstanceUID] mixin to provide a unique ID
/// for each instance of the class.
class LSLResource with InstanceUID implements IResource {
  @override
  final String id;

  @override
  String get name => 'lsl-resource-$id';

  @override
  String? get description => 'A LSL Resource with id $id';

  @override
  IResourceManager? get manager => _manager;
  IResourceManager? _manager;

  @override
  bool get created => _created;
  @override
  bool get disposed => _disposed;

  bool _created = false;
  bool _disposed = false;

  /// Creates a new LSL resource with the given ID and optional manager.
  LSLResource({required this.id, IResourceManager? manager})
    : _manager = manager;

  @override
  @mustCallSuper
  @mustBeOverridden
  FutureOr<void> create() {
    if (_disposed) {
      throw StateError('Resource has been disposed');
    }
    if (_created) {
      throw StateError('Resource has already been created');
    }
    _created = true;
  }

  @override
  @mustCallSuper
  @mustBeOverridden
  FutureOr<void> dispose() {
    if (!_created) {
      throw StateError('Resource has not been created');
    }
    if (_disposed) {
      throw StateError('Resource has already been disposed');
    }

    _disposed = true;
    _created = false;
  }

  @override
  FutureOr<void> updateManager(IResourceManager? newManager) async {
    if (_disposed) {
      throw StateError('Resource has been disposed');
    }
    if (_manager != null) {
      throw StateError(
        'Resource is already managed by ${_manager!.name} (${_manager!.uId}) '
        'please release it before assigning a new manager',
      );
    }
    _manager = newManager;
  }
}

/// Coordination session implementation using LSL transport.
/// This uses the [RuntimeTypeUID] mixin to provide a unique ID
/// based on the runtime type of the class ([LSLCoordinationSession]).
/// This is because there shouldn't be multiple [LSLCoordinationSession]
/// instances. Other transports may allow multiple instances, and should instead
/// use the [InstanceUID] mixin.
class LSLCoordinationSession extends CoordinationSession with RuntimeTypeUID {
  @override
  String get id => 'lsl-coordination-session';
  @override
  String get name => 'LSL Coordination Session';
  @override
  String get description =>
      'A coordination session using LSL transport for communication';

  /// Managed resources
  /// @TODO: properly implement
  final Map<String, IResource> _resources = {};

  /// Creates a new LSL coordination session with the given configuration.
  /// If no configuration is provided, the default configuration is used.
  LSLCoordinationSession(super.config)
    : _transport =
          (config.transportConfig is LSLTransportConfig)
              ? LSLTransport(
                config: config.transportConfig as LSLTransportConfig,
              )
              : LSLTransport(),
      super();

  /// The LSL transport used for communication.
  final LSLTransport _transport;

  @override
  LSLTransport get transport => _transport;

  @override
  Future<void> manageResource<R extends IResource>(R resource) async {
    resource.updateManager(this);
    _resources[resource.uId] = resource;
  }

  @override
  Future<R> releaseResource<R extends IResource>(String resourceUID) async {
    // for now, remove from the map, but we should proxy
    final resource = _resources.remove(resourceUID);
    if (resource == null) {
      throw StateError('Resource with UID $resourceUID not found');
    }
    return resource as R;
  }

  @override
  String toString() {
    return 'LSLCoordinationSession(name: ${config.name}, maxNodes: ${config.maxNodes}, minNodes: ${config.minNodes})';
  }

  @override
  Future<void> create() async {
    super.create();
    await _transport.createStream(coordinationConfig.streamConfig);
  }

  @override
  Future<void> dispose() async {
    final List<Future> releaseFutures = [];
    for (var resource in _resources.values) {
      final r = await resource.manager?.releaseResource(resource.uId);
      if (r != null) {
        final d = r.dispose();
        if (d is Future) {
          releaseFutures.add(d);
        }
      }
    }
    await Future.wait(releaseFutures);
    _resources.clear();
    super.dispose();
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() {
    super.initialize();
    // TODO: implement initialize
    throw UnimplementedError();
  }

  @override
  Future<void> join() {
    super.join();
    // TODO: implement join
    throw UnimplementedError();
  }

  @override
  Future<void> leave() {
    super.leave();
    // TODO: implement leave
    throw UnimplementedError();
  }

  @override
  Future<void> pause() {
    super.pause();
    // TODO: implement pause
    throw UnimplementedError();
  }

  @override
  Future<void> resume() {
    super.resume();
    // TODO: implement resume
    throw UnimplementedError();
  }
}
