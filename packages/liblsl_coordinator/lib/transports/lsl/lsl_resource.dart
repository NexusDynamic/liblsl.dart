import 'dart:async';

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
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
    if (_disposed) {
      throw StateError('Resource has already been disposed');
    }

    _disposed = true;
    _created = false;
  }

  @override
  void updateManager(IResourceManager? newManager) {
    if (_disposed) {
      throw StateError('Resource has been disposed');
    }
    if (_manager == newManager) {
      logger.finest(
        'Resource manager is already set to ${newManager?.name} (${newManager?.uId})',
      );
      return;
    }
    if (_manager != null && newManager != null) {
      throw StateError(
        'Resource is already managed by ${_manager!.name} (${_manager!.uId}) '
        'please release it before assigning a new manager',
      );
    }
    _manager = newManager;
  }
}
