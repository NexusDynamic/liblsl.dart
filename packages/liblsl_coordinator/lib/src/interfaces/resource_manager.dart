import 'dart:async';

import 'package:meta/meta.dart';

import 'package:liblsl_coordinator/interfaces.dart';

abstract interface class IResourceManager implements IUniqueIdentity {
  @protected
  FutureOr<void> manageResource<R extends IResource>(R resource);
  @protected
  FutureOr<R> releaseResource<R extends IResource>(String resourceId);
}
