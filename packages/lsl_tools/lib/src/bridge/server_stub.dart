import '../lsl.dart';
import 'server.dart';

const bool supported = false;

Future<LslBridgeServer> start(
  List<LslStreamDescription> streams, {
  required int port,
  required String token,
  required bool acceptPublish,
  required LslInletOptions options,
  required LslOutletOptions outletOptions,
}) => throw UnsupportedError('Sharing LSL streams needs dart:io');
