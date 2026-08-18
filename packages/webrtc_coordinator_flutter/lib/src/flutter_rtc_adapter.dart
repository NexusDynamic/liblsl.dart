/// The `flutter_webrtc` side of the [RtcPeerAdapter] seam.
///
/// Everything here is translation and nothing is policy. The dial state
/// machine, glare resolution, channel-id derivation, routing and framing all
/// live in `webrtc_coordinator`, which is pure Dart and tested headlessly
/// against `FakeRtcPeerAdapter`. What this file adds is the part that genuinely
/// needs a device: real SDP, real ICE, real SCTP.
///
/// The rule the seam is built on — **no `flutter_webrtc` type may cross it** —
/// is why session descriptions and candidates leave here as plain maps and
/// `RTCPeerConnectionState`'s six values leave as [RtcLinkState]'s three.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

final Logger _logger = Logger('webrtc_coordinator_flutter.adapter');

/// An [RtcAdapterFactory] backed by `flutter_webrtc`.
///
/// Pass it straight to `RtcTransportConfig.adapterFactory`:
///
/// ```dart
/// RtcTransportConfig(
///   hubUri: Uri.parse('ws://hub.local:8080'),
///   adapterFactory: flutterWebrtcAdapterFactory,
/// )
/// ```
RtcPeerAdapter flutterWebrtcAdapterFactory(String selfNodeUId) =>
    FlutterRtcPeerAdapter(selfKey: selfNodeUId);

/// Creates real peer connections for one node.
class FlutterRtcPeerAdapter implements RtcPeerAdapter {
  FlutterRtcPeerAdapter({required this.selfKey});

  /// This node's uId. Diagnostic only — WebRTC never sees it; peers are
  /// addressed through the hub's signalling.
  final String selfKey;

  final Map<String, _FlutterRtcPeerLink> _links = {};
  bool _closed = false;

  @override
  Future<RtcPeerLink> createLink(
    String peerKey, {
    List<Map<String, Object?>> iceServers = const [],
  }) async {
    if (_closed) throw StateError('Adapter for $selfKey is closed');
    final existing = _links[peerKey];
    if (existing != null) return existing;

    final connection = await createPeerConnection({
      'iceServers': iceServers,
      // Unified plan is the only semantics current browsers implement, and
      // this connection carries no media anyway.
      'sdpSemantics': 'unified-plan',
    });
    final link = _FlutterRtcPeerLink(
      adapter: this,
      peerKey: peerKey,
      connection: connection,
    );
    _links[peerKey] = link;
    link._wire();
    return link;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final link in _links.values.toList(growable: false)) {
      await link.close();
    }
    _links.clear();
  }

  void _forget(String peerKey) => _links.remove(peerKey);
}

class _FlutterRtcPeerLink implements RtcPeerLink {
  _FlutterRtcPeerLink({
    required this.adapter,
    required this.peerKey,
    required this.connection,
  });

  final FlutterRtcPeerAdapter adapter;
  final RTCPeerConnection connection;

  @override
  final String peerKey;

  final _states = StreamController<RtcLinkState>.broadcast();
  final _candidates = StreamController<Map<String, Object?>>.broadcast();
  final Map<int, _FlutterRtcChannel> _channels = {};

  /// Candidates that arrived before the remote description did.
  ///
  /// ICE routinely delivers these ahead of the answer, and
  /// `setRemoteDescription` must come first or they are rejected. Dropping
  /// them instead of buffering produces a transport that works on a fast LAN
  /// and fails everywhere else.
  final List<RTCIceCandidate> _pendingCandidates = [];

  RtcLinkState _state = RtcLinkState.connecting;
  bool _remoteSet = false;

  @override
  RtcLinkState get state => _state;

  @override
  Stream<RtcLinkState> get states => _states.stream;

  @override
  Stream<Map<String, Object?>> get localCandidates => _candidates.stream;

  void _wire() {
    connection.onIceCandidate = (candidate) {
      if (_candidates.isClosed) return;
      _candidates.add(Map<String, Object?>.from(candidate.toMap() as Map));
    };
    connection.onConnectionState = (state) {
      _setState(_mapState(state));
    };
  }

  /// Six plugin states down to the three the transport branches on.
  ///
  /// `disconnected` is deliberately *not* terminal: ICE reports it for a
  /// transient loss it may well recover from on its own, and treating it as a
  /// departure would tear down a connection that is about to come back. Only
  /// `failed` and `closed` are the end.
  static RtcLinkState _mapState(RTCPeerConnectionState state) =>
      switch (state) {
        RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          RtcLinkState.connected,
        RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
          RtcLinkState.closed,
        RTCPeerConnectionState.RTCPeerConnectionStateNew ||
        RTCPeerConnectionState.RTCPeerConnectionStateConnecting ||
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
          RtcLinkState.connecting,
      };

  @override
  Future<Map<String, Object?>> createOffer() async {
    _ensureOpen();
    final offer = await connection.createOffer({});
    await connection.setLocalDescription(offer);
    return Map<String, Object?>.from(offer.toMap() as Map);
  }

  @override
  Future<Map<String, Object?>> createAnswer(
    Map<String, Object?> remoteOffer,
  ) async {
    _ensureOpen();
    await _applyRemote(remoteOffer, expected: 'offer');
    final answer = await connection.createAnswer({});
    await connection.setLocalDescription(answer);
    return Map<String, Object?>.from(answer.toMap() as Map);
  }

  @override
  Future<void> acceptAnswer(Map<String, Object?> remoteAnswer) async {
    _ensureOpen();
    await _applyRemote(remoteAnswer, expected: 'answer');
  }

  Future<void> _applyRemote(
    Map<String, Object?> description, {
    required String expected,
  }) async {
    final type = description['type'];
    final sdp = description['sdp'];
    if (type is! String || type != expected || sdp is! String) {
      throw ArgumentError.value(
        description,
        'description',
        'not a valid $expected',
      );
    }
    await connection.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteSet = true;
    for (final candidate in _pendingCandidates) {
      await connection.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  @override
  Future<void> addCandidate(Map<String, Object?> candidate) async {
    _ensureOpen();
    final ice = RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      candidate['sdpMLineIndex'] as int?,
    );
    if (!_remoteSet) {
      _pendingCandidates.add(ice);
      return;
    }
    await connection.addCandidate(ice);
  }

  @override
  Future<RtcChannel> openChannel(
    int id, {
    bool ordered = true,
    int? maxRetransmits,
  }) async {
    _ensureOpen();
    final existing = _channels[id];
    if (existing != null) return existing;

    final init = RTCDataChannelInit()
      ..negotiated = true
      ..id = id
      ..ordered = ordered;

    if (maxRetransmits != null) {
      if (maxRetransmits == 0) {
        // `RTCDataChannelInit.toMap` writes the field only `if (maxRetransmits
        // > 0)`, so zero is indistinguishable from unset and the channel comes
        // up fully reliable — silently the opposite of what was asked for.
        // Say so rather than let a benchmark report a latency that a reliable
        // channel produced.
        _logger.warning(
          'maxRetransmits: 0 cannot be expressed through flutter_webrtc '
          '(RTCDataChannelInit.toMap drops non-positive values), so channel '
          '$id to $peerKey will be reliable. Use 1 for near-unreliable '
          'delivery, or `ordered: false` alone for unordered-but-reliable.',
        );
      } else {
        init.maxRetransmits = maxRetransmits;
      }
    }

    // The label is not what pairs the two ends — `negotiated: true` pairs them
    // by [id] — but a deterministic one makes a packet capture readable.
    final native = await connection.createDataChannel('ch-$id', init);
    final channel = _FlutterRtcChannel(link: this, id: id, channel: native);
    _channels[id] = channel;
    channel._wire();
    return channel;
  }

  @override
  Future<void> close() async {
    if (_state == RtcLinkState.closed) return;
    _setState(RtcLinkState.closed);
    for (final channel in _channels.values.toList(growable: false)) {
      await channel.close();
    }
    _channels.clear();
    adapter._forget(peerKey);
    await connection.close();
    await connection.dispose();
    await _states.close();
    await _candidates.close();
  }

  void _forget(int id) => _channels.remove(id);

  void _ensureOpen() {
    if (_state == RtcLinkState.closed) {
      throw StateError('Link ${adapter.selfKey} -> $peerKey is closed');
    }
  }

  void _setState(RtcLinkState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
    if (next == RtcLinkState.closed) {
      for (final channel in _channels.values) {
        channel._failIfNotReady();
      }
    }
  }
}

class _FlutterRtcChannel implements RtcChannel {
  _FlutterRtcChannel({
    required this.link,
    required this.id,
    required this.channel,
  });

  final _FlutterRtcPeerLink link;
  final RTCDataChannel channel;

  @override
  final int id;

  final _messages = StreamController<Object>.broadcast();
  final _readyCompleter = Completer<void>();
  bool _closed = false;

  void _wire() {
    // Keeps "closed before it opened" from surfacing as an unhandled async
    // error when nothing happens to be awaiting `ready`. The handler goes on a
    // derived future so the original's error is intact for real awaiters.
    unawaited(_readyCompleter.future.catchError((Object _) {}));

    channel.onDataChannelState = (state) {
      switch (state) {
        case RTCDataChannelState.RTCDataChannelOpen:
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        case RTCDataChannelState.RTCDataChannelClosed:
          unawaited(close());
        case RTCDataChannelState.RTCDataChannelConnecting:
        case RTCDataChannelState.RTCDataChannelClosing:
          break;
      }
    };
    channel.onMessage = (message) {
      if (_messages.isClosed) return;
      _messages.add(message.isBinary ? message.binary : message.text);
    };

    // A pre-negotiated channel on an already-connected link can be open before
    // the callback is attached, in which case no state change is ever
    // delivered and `ready` would never complete.
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen &&
        !_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  @override
  bool get isOpen =>
      !_closed && channel.state == RTCDataChannelState.RTCDataChannelOpen;

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream<Object> get messages => _messages.stream;

  @override
  void send(Object payload) {
    if (!isOpen) return;
    final message = switch (payload) {
      final Uint8List bytes => RTCDataChannelMessage.fromBinary(bytes),
      final String text => RTCDataChannelMessage(text),
      final List<int> bytes => RTCDataChannelMessage.fromBinary(
        Uint8List.fromList(bytes),
      ),
      _ => throw ArgumentError.value(
        payload,
        'payload',
        'must be a String or a Uint8List',
      ),
    };
    // Fire-and-forget, matching the publish-side guards on every other
    // transport: a stream's `sendData` must not block on the wire, and a send
    // that fails on a channel that just closed is not an error worth throwing
    // from a sample loop.
    unawaited(
      channel.send(message).catchError((Object e) {
        _logger.fine('Send failed on channel $id to ${link.peerKey}: $e');
      }),
    );
  }

  void _failIfNotReady() {
    if (_readyCompleter.isCompleted) return;
    _readyCompleter.completeError(
      StateError('Channel $id closed before it opened'),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _failIfNotReady();
    link._forget(id);
    try {
      await channel.close();
    } catch (e) {
      _logger.fine('Closing channel $id to ${link.peerKey}: $e');
    }
    await _messages.close();
  }
}
