import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/src/event.dart';

/// LSL-specific stream events
sealed class LSLStreamEvent extends StreamEvent {
  final String managerId;

  const LSLStreamEvent(this.managerId, String streamId, DateTime timestamp)
    : super(streamId, timestamp);
}

class LSLOutletCreated extends LSLStreamEvent {
  final String outletId;
  final LSLStreamInfo streamInfo;

  LSLOutletCreated(String managerId, this.outletId, this.streamInfo)
    : super(managerId, outletId, DateTime.now());
}

class LSLOutletDestroyed extends LSLStreamEvent {
  final String outletId;

  LSLOutletDestroyed(String managerId, this.outletId)
    : super(managerId, outletId, DateTime.now());
}

class LSLInletCreated extends LSLStreamEvent {
  final String inletId;
  final LSLStreamInfo streamInfo;

  LSLInletCreated(String managerId, this.inletId, this.streamInfo)
    : super(managerId, inletId, DateTime.now());
}

class LSLInletDestroyed extends LSLStreamEvent {
  final String inletId;

  LSLInletDestroyed(String managerId, this.inletId)
    : super(managerId, inletId, DateTime.now());
}

class LSLResolverCreated extends LSLStreamEvent {
  final String resolverId;
  final String predicate;

  LSLResolverCreated(String managerId, this.resolverId, this.predicate)
    : super(managerId, resolverId, DateTime.now());
}

class LSLResolverDestroyed extends LSLStreamEvent {
  final String resolverId;

  LSLResolverDestroyed(String managerId, this.resolverId)
    : super(managerId, resolverId, DateTime.now());
}

class LSLIsolateControllerCreated extends LSLStreamEvent {
  final String controllerId;

  LSLIsolateControllerCreated(String managerId, this.controllerId)
    : super(managerId, controllerId, DateTime.now());
}

class LSLIsolateControllerDestroyed extends LSLStreamEvent {
  final String controllerId;

  LSLIsolateControllerDestroyed(String managerId, this.controllerId)
    : super(managerId, controllerId, DateTime.now());
}

class LSLStreamError extends LSLStreamEvent {
  final String resourceId;
  final String error;

  LSLStreamError(String managerId, this.resourceId, this.error)
    : super(managerId, resourceId, DateTime.now());
}
