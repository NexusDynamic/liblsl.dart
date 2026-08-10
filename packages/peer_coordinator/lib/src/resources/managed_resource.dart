import 'dart:async';

import 'package:peer_coordinator/framework.dart';
import 'package:meta/meta.dart';

/// Applies the single-owner rule for [IResource.updateManager] and returns the
/// manager the resource should now hold.
///
/// Extracted because [IResource] is implemented both by classes (which can
/// extend [ManagedResource]) and by mixins on [NetworkStream] (which cannot),
/// so the check had been copy-pasted. The rule itself is the important part:
/// a resource may go owned → unowned or unowned → owned, but never directly
/// from one owner to another. That is what makes [PeerHandle.take] safe —
/// there is no instant at which two managers both believe they may free it.
IResourceManager? resolveManagerUpdate({
  required IResourceManager? current,
  required IResourceManager? next,
  required bool disposed,
}) {
  if (disposed) {
    throw StateError('Resource has been disposed');
  }
  if (current == next) {
    logger.finest(
      'Resource manager is already set to ${next?.name} (${next?.uId})',
    );
    return current;
  }
  if (current != null && next != null) {
    throw StateError(
      'Resource is already managed by ${current.name} (${current.uId}) '
      'please release it before assigning a new manager',
    );
  }
  return next;
}

/// A resource with a create/dispose lifecycle and single-owner semantics.
///
/// There is nothing transport-specific here — it is the plain [IResource]
/// bookkeeping every transport needs: guard against double-create and
/// double-dispose, and refuse to be adopted by a second manager without being
/// released from the first.
///
/// That last rule is what keeps ownership transfers honest. [PeerHandle.take]
/// depends on it: a handle can only move from discovery to a stream by first
/// being released, so there is never a moment where two owners both believe
/// they may free the underlying resource.
class ManagedResource with InstanceUID implements IResource {
  /// Creates a resource with the given [id] and optional initial [manager].
  ManagedResource({required this.id, IResourceManager? manager})
    : _manager = manager;

  @override
  final String id;

  @override
  String get name => 'resource-$id';

  @override
  String? get description => 'A managed resource with id $id';

  @override
  IResourceManager? get manager => _manager;
  IResourceManager? _manager;

  @override
  bool get created => _created;

  @override
  bool get disposed => _disposed;

  bool _created = false;
  bool _disposed = false;

  /// Marks the resource created.
  ///
  /// Not `@mustBeOverridden`: this implementation is complete and usable on
  /// its own, and requiring every subclass to override it only produced empty
  /// overrides. Subclasses that do override must still call super.
  @override
  @mustCallSuper
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
  FutureOr<void> dispose() {
    if (_disposed) {
      throw StateError('Resource has already been disposed');
    }

    _disposed = true;
    _created = false;
  }

  @override
  void updateManager(IResourceManager? newManager) {
    _manager = resolveManagerUpdate(
      current: _manager,
      next: newManager,
      disposed: _disposed,
    );
  }
}
