/// Standalone WebSocket relay hub.
///
///     dart run peer_coordinator:hub [--port 8080] [--host 0.0.0.0]
///
/// Nodes then coordinate through it by using a `WebSocketTransportConfig`
/// pointing at `ws://<host>:<port>`.
///
/// The hub is role-blind: it relays frames and tracks who is connected, and
/// knows nothing about election, membership or streams.
library;

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/peer_coordinator.dart';

Future<void> main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen(Log.defaultPrinter);

  var port = 8080;
  var host = InternetAddress.loopbackIPv4;
  for (var i = 0; i < args.length - 1; i++) {
    switch (args[i]) {
      case '--port':
        port = int.parse(args[i + 1]);
      case '--host':
        // 0.0.0.0 to accept connections from other machines.
        host = InternetAddress(args[i + 1]);
    }
  }

  final hub = await CoordinationHub.serve(address: host, port: port);
  stdout.writeln('Coordination hub on ws://${host.address}:${hub.port}');
  stdout.writeln('Press Ctrl-C to stop.');

  await ProcessSignal.sigint.watch().first;
  await hub.close();
}
