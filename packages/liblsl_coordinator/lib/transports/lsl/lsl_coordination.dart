import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

/// A [PeerSession] backed by Lab Streaming Layer.
///
/// The session flow itself — election, join, stream lifecycle, user messages,
/// teardown — is transport-neutral and lives in [PeerSession]. This subclass
/// only pins the transport to LSL and narrows the return types, so existing
/// code that expects `LSLDataStream` back from [createDataStream] keeps
/// compiling unchanged.
class LSLCoordinationSession extends PeerSession {
  /// Creates a session over LSL.
  ///
  /// The transport is built from [CoordinationConfig.transportConfig] when it
  /// is an [LSLTransportConfig], and from LSL defaults otherwise.
  // Not a super parameter: `config` has to be read by _transportFor before it
  // is forwarded, which a super parameter cannot express.
  // ignore: use_super_parameters
  LSLCoordinationSession(CoordinationConfig config, {super.thisNodeConfig})
    : super(config, transport: _transportFor(config));

  static LSLTransport _transportFor(CoordinationConfig config) {
    final transportConfig = config.transportConfig;
    return transportConfig is LSLTransportConfig
        ? LSLTransport(config: transportConfig)
        : LSLTransport();
  }

  @override
  String get id => 'lsl-coordination-session';

  @override
  String get name => 'LSL Coordination Session';

  @override
  String get description => 'LSL coordination session';

  @override
  LSLTransport get transport => super.transport as LSLTransport;

  // Return-type covariance: the base returns DataStream, and the LSL factory
  // only ever produces LSLDataStream, so narrowing here is sound and spares
  // callers a downcast.
  @override
  Future<LSLDataStream> createDataStream(DataStreamConfig config) async =>
      await super.createDataStream(config) as LSLDataStream;

  @override
  Future<LSLDataStream> getDataStream(String name) async =>
      await super.getDataStream(name) as LSLDataStream;
}
