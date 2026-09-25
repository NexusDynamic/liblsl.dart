import '../lsl.dart';
import 'server.dart';

const bool supported = false;

Future<LslBridgeServer> start(
  List<LslStreamDescription> streams, {
  required int port,
  required String token,
  required LslInletOptions options,
}) => throw UnsupportedError('Sharing LSL streams needs dart:io');
