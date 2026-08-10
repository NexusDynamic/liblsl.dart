/// Device coordination over Lab Streaming Layer.
///
/// The coordination logic itself — election, membership, heartbeat, stream
/// lifecycle — is transport-neutral and lives in `package:peer_coordinator`,
/// which this library re-exports in full. Import
/// `package:liblsl_coordinator/transports/lsl.dart` for the LSL backend.
library;

export 'package:peer_coordinator/peer_coordinator.dart';
