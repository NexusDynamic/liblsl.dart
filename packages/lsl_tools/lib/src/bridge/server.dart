import 'server_stub.dart' if (dart.library.io) 'server_io.dart' as platform;

import '../lsl.dart';

/// Shares LSL streams over a WebSocket (see `protocol.dart`), so computers
/// on other networks, or browsers, can receive them; with [acceptsPublish]
/// it is also a relay: streams clients publish are shared with every other
/// client. Native only.
abstract class LslBridgeServer {
  /// Whether this platform can share LSL streams (and make outlets for the
  /// streams clients publish).
  static bool get supported => platform.supported;

  /// Whether this platform can run a relay without LSL
  /// (`acceptPublish: true, localOutlets: false`, no [streams]): anywhere
  /// with `dart:io`, e.g. a server with no LSL network.
  static bool get relaySupported => platform.relaySupported;

  /// Share [streams] on [host]:[port] (0 for any free port), to clients
  /// that give [token] (when not empty) and, from browsers, come from one
  /// of [allowedOrigins] (when not empty, e.g. `https://example.org`).
  ///
  /// With [acceptPublish], clients can also publish streams here. Each is
  /// shared with the other clients and, with [localOutlets], also becomes
  /// an LSL outlet on this computer (e.g. a serial device a browser reads).
  static Future<LslBridgeServer> start(
    List<LslStreamDescription> streams, {
    int port = 8765,
    String host = '0.0.0.0',
    String token = '',
    bool acceptPublish = false,
    bool localOutlets = true,
    List<String> allowedOrigins = const [],
    LslInletOptions options = const LslInletOptions(),
    LslOutletOptions outletOptions = const LslOutletOptions(),
  }) => platform.start(
    streams,
    port: port,
    host: host,
    token: token,
    acceptPublish: acceptPublish,
    localOutlets: localOutlets,
    allowedOrigins: allowedOrigins,
    options: options,
    outletOptions: outletOptions,
  );

  /// The port it listens on.
  int get port;

  /// The address it listens on (`0.0.0.0` for all).
  String get host;

  /// The LSL streams on this computer's network that are shared.
  List<LslStreamDescription> get streams;

  /// Share another LSL stream (e.g. one that appeared after starting);
  /// false if it is shared already or is one this server publishes for a
  /// client.
  Future<bool> share(LslStreamDescription stream);

  /// Stop sharing [stream].
  Future<void> unshare(LslStreamDescription stream);

  /// Clients connected now.
  int get clientCount;

  /// The clients connected now.
  List<LslBridgeClientInfo> get clients;

  /// Samples sent so far, to all clients.
  int get sent;

  /// Whether clients may publish streams here.
  bool get acceptsPublish;

  /// Whether streams clients publish also become LSL outlets here.
  bool get localOutlets;

  /// Names of the streams clients publish here now.
  List<String> get published;

  /// Samples received from clients' published streams.
  int get received;

  /// This computer's addresses that clients on other computers can try
  /// (IPv4, loopback last), for showing how to connect.
  Future<List<String>> localAddresses();

  /// Fires when clients or streams come or go.
  Stream<void> get onChange;

  Future<void> close();
}

/// A client connected to an [LslBridgeServer].
class LslBridgeClientInfo {
  /// Where it connects from.
  final String address;

  /// How many streams it receives.
  final int subscriptions;

  /// Names of the streams it publishes.
  final List<String> published;

  const LslBridgeClientInfo(this.address, this.subscriptions, this.published);
}
