import 'package:liblsl_coordinator/interfaces.dart';
import 'package:liblsl_coordinator/src/interfaces/identity.dart';

abstract class NetworkSession
    implements
        ManagedResources,
        InitializationRequired,
        Lifecycle,
        UniqueIdentity {}
