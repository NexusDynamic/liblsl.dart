/// Coordination over a WebSocket relay hub.
///
/// Web-safe: uses `package:web_socket_channel`, which is one API over
/// `dart:io` sockets on the VM and the browser's WebSocket on the web.
///
/// A node connects to a hub — see `package:peer_coordinator/hub.dart`, or run
/// `dart run peer_coordinator:hub` — which relays frames between peers. The
/// hub is role-blind: election, membership and stream lifecycle all stay
/// client-side, exactly as they are over LSL.
library;

export 'src/websocket/ws_connection.dart'
    show WsConnection, WsInbound, WsSignal;
export 'src/websocket/ws_discovery.dart' show WsDiscovery, WsPeerHandle;
export 'src/websocket/ws_protocol.dart'
    show WsControl, WsFrame, WsSampleFrame, wsProtocolVersion;
export 'src/websocket/ws_stream.dart'
    show
        WsCoordinationStream,
        WsDataStream,
        WsNetworkStreamFactory,
        WsStreamMixin;
export 'src/websocket/ws_transport.dart'
    show WebSocketTransport, WebSocketTransportConfig;
