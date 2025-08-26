import 'package:liblsl_coordinator/framework.dart';
import 'dart:async';

/// Interface for all transport configurations.
abstract interface class ITransportConfig implements IConfig {}

/// Interface for all transport implementations.
abstract interface class ITransport<T extends ITransportConfig>
    implements IConfigurable<T>, IInitializable, IIdentity, ILifecycle {
  /// Creates a stream with the current transport for the given configuration.
  FutureOr<NetworkStream> createStream(
    NetworkStreamConfig streamConfig, {
    CoordinationSession? coordinationSession,
  });
}
