import '../lsl.dart';
import 'server.dart';

const bool supported = false;
const bool relaySupported = false;

Future<LslBridgeServer> start(
  List<LslStreamDescription> streams, {
  required int port,
  required String host,
  required String token,
  required bool acceptPublish,
  required bool localOutlets,
  required List<String> allowedOrigins,
  required LslInletOptions options,
  required LslOutletOptions outletOptions,
  required double Function()? clock,
}) => throw UnsupportedError('Sharing LSL streams needs dart:io');
