import 'dart:async';
import 'dart:typed_data';

import 'package:peer_coordinator/framework.dart';
import 'package:peer_coordinator/src/websocket/ws_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A relayed message addressed to one of this node's endpoints.
class WsInbound {
  const WsInbound({
    required this.streamName,
    required this.fromEndpointId,
    required this.payload,
  });

  final String streamName;
  final String fromEndpointId;

  /// A JSON-decoded map for control messages, or a [Uint8List] sample frame.
  final Object payload;
}

/// A signalling payload from one peer to another, forwarded by the hub.
///
/// The hub never looks inside [payload] — it checks only that the sender owns
/// [fromEndpointId] — so this carries whatever two peers need to establish a
/// direct connection between themselves. That is what lets a peer-to-peer
/// transport use this hub for discovery and connection setup while its data
/// never crosses it.
class WsSignal {
  const WsSignal({
    required this.fromEndpointId,
    required this.toEndpointId,
    required this.payload,
  });

  /// The endpoint that sent this, as the hub verified it.
  final String fromEndpointId;

  /// One of this connection's own endpoints.
  final String toEndpointId;

  /// Whatever the sender put in. JSON-decoded, and meaningful only to the
  /// transport at both ends.
  final Object? payload;
}

/// The single WebSocket a node holds to the hub.
///
/// All of a node's endpoints — its coordination stream plus every data stream
/// — share one connection, so this owns the socket and demultiplexes on the
/// way in.
///
/// Uses `package:web_socket_channel`, which presents one API over `dart:io`
/// sockets on the VM and the browser's `WebSocket` on the web. That is what
/// lets this file stay in the web-safe part of the package.
class WsConnection {
  WsConnection(this.hubUri);

  final Uri hubUri;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final StreamController<WsInbound> _inbound =
      StreamController<WsInbound>.broadcast();
  final StreamController<WsSignal> _signals =
      StreamController<WsSignal>.broadcast();
  final StreamController<WsFrame> _control =
      StreamController<WsFrame>.broadcast();

  /// endpointId -> hub-assigned slot, learned from `welcome`.
  final Map<String, int> _slots = {};
  final Map<String, Completer<int>> _pendingSlots = {};

  bool _closed = false;
  int _nextQueryId = 1;

  /// Relayed traffic for this node's endpoints.
  Stream<WsInbound> get inbound => _inbound.stream;

  /// Control frames from the hub, for callers that need them directly
  /// (query results, peer departures).
  Stream<WsFrame> get control => _control.stream;

  /// Signalling frames addressed to one of this connection's endpoints.
  ///
  /// A convenience over filtering [control]: a peer-to-peer transport reads this
  /// to set up its direct connections, and nothing else on the socket concerns
  /// it. Broadcast, like the others, so several streams can listen.
  Stream<WsSignal> get signals => _signals.stream;

  bool get isConnected => _channel != null && !_closed;

  Future<void> connect({Duration timeout = const Duration(seconds: 10)}) async {
    if (_channel != null) return;
    final channel = WebSocketChannel.connect(hubUri);
    await channel.ready.timeout(timeout);
    _channel = channel;

    _subscription = channel.stream.listen(
      _onData,
      onDone: _onClosed,
      onError: (Object e) {
        logger.warning('WebSocket error on $hubUri: $e');
        _onClosed();
      },
    );
    logger.fine('Connected to hub at $hubUri');
  }

  void _onData(dynamic data) {
    if (data is String) {
      final WsFrame frame;
      try {
        frame = WsFrame.decode(data);
      } catch (e) {
        logger.warning('Discarding malformed control frame: $e');
        return;
      }
      switch (frame.type) {
        case WsControl.welcome:
          final endpointId = frame.payload['endpointId'] as String;
          final slot = frame.payload['slot'] as int;
          _slots[endpointId] = slot;
          _pendingSlots.remove(endpointId)?.complete(slot);
        case WsControl.message:
          _inbound.add(
            WsInbound(
              streamName: frame.payload['stream'] as String,
              fromEndpointId: frame.payload['from'] as String,
              payload: frame.payload['payload'] as Object,
            ),
          );
        case WsControl.signal:
          _signals.add(
            WsSignal(
              fromEndpointId: frame.payload['from'] as String,
              toEndpointId: frame.payload['to'] as String,
              payload: frame.payload['payload'],
            ),
          );
        default:
          break;
      }
      _control.add(frame);
    } else if (data is List<int>) {
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      if (!WsSampleFrame.isSample(bytes)) return;
      final producer = _endpointForSlot(WsSampleFrame.sourceSlotOf(bytes));
      _inbound.add(
        WsInbound(
          streamName: '', // resolved by the subscribing stream via srcSlot
          fromEndpointId: producer ?? '',
          payload: bytes,
        ),
      );
    }
  }

  String? _endpointForSlot(int slot) {
    for (final entry in _slots.entries) {
      if (entry.value == slot) return entry.key;
    }
    return null;
  }

  void _onClosed() {
    if (_closed) return;
    _closed = true;
    for (final completer in _pendingSlots.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Connection closed'));
      }
    }
    _pendingSlots.clear();
  }

  /// Registers (or re-registers) an endpoint and returns its hub slot.
  ///
  /// Set [publish] false for a consumer-only endpoint: it still needs a slot
  /// and a routing identity so the hub can deliver to it, but it must not
  /// appear in publisher discovery.
  Future<int> announce(PeerDescriptor descriptor, {bool publish = true}) async {
    final endpointId = descriptor.endpointId;
    final known = _slots[endpointId];
    _send(
      WsFrame(known == null ? WsControl.hello : WsControl.update, {
        'peer': descriptor.toJson(),
        'publish': publish,
      }).encode(),
    );
    if (known != null) return known;

    final completer = _pendingSlots.putIfAbsent(endpointId, Completer<int>.new);
    return completer.future.timeout(const Duration(seconds: 10));
  }

  int? slotFor(String endpointId) => _slots[endpointId];

  /// Runs a query. Returns its id so it can be cancelled with [unquery].
  int query(DiscoveryQuery q, {bool continuous = false}) {
    final qid = _nextQueryId++;
    _send(
      WsFrame(WsControl.query, {
        'qid': qid,
        'query': q.toJson(),
        'continuous': continuous,
      }).encode(),
    );
    return qid;
  }

  void unquery(int qid) =>
      _send(WsFrame(WsControl.unquery, {'qid': qid}).encode());

  void subscribe({
    required String streamName,
    required String subscriberEndpointId,
    required List<String> producerEndpointIds,
  }) => _send(
    WsFrame(WsControl.subscribe, {
      'stream': streamName,
      'subscriber': subscriberEndpointId,
      'from': producerEndpointIds,
    }).encode(),
  );

  void publishMessage({
    required String streamName,
    required String fromEndpointId,
    required Object payload,
  }) => _send(
    WsFrame(WsControl.message, {
      'stream': streamName,
      'from': fromEndpointId,
      'payload': payload,
    }).encode(),
  );

  void publishSample(Uint8List frame) => _send(frame);

  /// Sends an opaque payload to one named endpoint, through the hub.
  ///
  /// The hub forwards it verbatim without looking inside, so what goes in
  /// [payload] is entirely between the two peers — a WebRTC offer, an answer, an
  /// ICE candidate. It must be JSON-encodable.
  void sendSignal({
    required String fromEndpointId,
    required String toEndpointId,
    required Object? payload,
  }) => _send(
    WsFrame(WsControl.signal, {
      'from': fromEndpointId,
      'to': toEndpointId,
      'payload': payload,
    }).encode(),
  );

  void _send(Object data) {
    final channel = _channel;
    if (channel == null || _closed) return;
    try {
      channel.sink.add(data);
    } catch (e) {
      logger.warning('Failed to send on $hubUri: $e');
    }
  }

  Future<void> close() async {
    if (_channel == null) return;
    _closed = true;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    unawaited(_inbound.close());
    unawaited(_control.close());
    unawaited(_signals.close());
  }
}
