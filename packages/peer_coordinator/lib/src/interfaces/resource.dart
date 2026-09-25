import 'dart:async';

import 'package:peer_coordinator/interfaces.dart';

abstract interface class IResource implements IUniqueIdentity, ILifecycle {
  /// gets the resource manager that manages this resource
  IResourceManager? get manager;

  FutureOr<void> updateManager(IResourceManager? newManager);
}
