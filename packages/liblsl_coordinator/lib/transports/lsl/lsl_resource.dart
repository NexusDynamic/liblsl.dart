import 'package:liblsl_coordinator/liblsl_coordinator.dart';

/// Base class for LSL-owned resources.
///
/// Nothing about the lifecycle bookkeeping was ever LSL-specific, so it now
/// lives in [ManagedResource] where every transport can use it. This subclass
/// remains as the LSL-facing name and to keep `extends LSLResource` working.
class LSLResource extends ManagedResource {
  LSLResource({required super.id, super.manager});

  @override
  String get name => 'lsl-resource-$id';

  @override
  String? get description => 'A LSL Resource with id $id';
}
