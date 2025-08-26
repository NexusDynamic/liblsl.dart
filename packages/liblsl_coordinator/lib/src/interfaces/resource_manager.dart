import 'dart:async';

import 'package:liblsl_coordinator/interfaces.dart';

abstract interface class IResourceManager implements IUniqueIdentity {
  FutureOr<void> manageResource<R extends IResource>(R resource);

  FutureOr<R> releaseResource<R extends IResource>(String resourceId);
}
