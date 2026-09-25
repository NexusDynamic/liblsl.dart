import 'server_stub.dart' if (dart.library.io) 'server_io.dart' as platform;

import '../lsl.dart';

/// Shares LSL streams over a WebSocket (see `protocol.dart`), so computers
/// on other networks, or browsers, can receive them. Native only.
abstract class LslBridgeServer {
  /// Whether this platform can share streams.
  static bool get supported => platform.supported;

  /// Share [streams] on [port] (0 for any free port), to clients that give
  /// [token] (when not empty).
  static Future<LslBridgeServer> start(
    List<LslStreamDescription> streams, {
    int port = 8765,
    String token = '',
    LslInletOptions options = const LslInletOptions(),
  }) => platform.start(streams, port: port, token: token, options: options);

  /// The port it listens on.
  int get port;

  /// The streams shared.
  List<LslStreamDescription> get streams;

  /// Clients connected now.
  int get clientCount;

  /// Samples sent so far, to all clients.
  int get sent;

  Future<void> close();
}
