/// An in-process [RtcPeerAdapter] that behaves enough like WebRTC to test
/// against.
///
/// The whole value of the adapter seam depends on this file being honest. The
/// properties that matter most, because getting any of them wrong would let
/// the suite validate behaviour no real transport has:
///
/// 1. **Delivery is asynchronous.** Every send hops a microtask before it
///    arrives, the way `InMemoryBus` is careful to. A synchronous fake makes
///    ordering bugs invisible and lets tests depend on send-then-assert.
/// 2. **Negotiation is a real handshake.** Offer, answer and candidates travel
///    through the caller, so the transport's signalling path is exercised
///    rather than short-circuited. A link that never receives an answer never
///    connects, and a channel opened on it never becomes ready.
/// 3. **Creating a link or a channel suspends.** In the real binding both are
///    platform-channel round trips, so there is a window between "is there one
///    already?" and "here it is" in which a second caller can arrive — and the
///    mesh routinely has two, its own dial and the peer's inbound `open`
///    signal. A fake that answered synchronously would close that window for
///    free and let the suite pass while a device built two connections for one
///    peer, or two halves of one pre-negotiated channel.
///
/// It does not model: media, bandwidth, packet loss, ICE restarts, or the
/// difference between reliable and unreliable delivery beyond recording the
/// requested mode. Anything in that list is only exercised on a device.
library;

import 'dart:async';

import '../rtc_adapter.dart';

/// One [RtcPeerLink.openChannel] call, as the transport made it.
///
/// Recorded and never removed, so a test can assert on what the transport
/// *asked for* — in particular the reliability mode, which the fake honours by
/// remembering rather than by dropping packets. Only a device proves the mode
/// does anything; this proves the transport requested it.
class FakeChannelRequest {
  const FakeChannelRequest({
    required this.peerKey,
    required this.id,
    required this.ordered,
    required this.maxRetransmits,
  });

  final String peerKey;
  final int id;
  final bool ordered;
  final int? maxRetransmits;

  @override
  String toString() =>
      'FakeChannelRequest($peerKey, id: $id, ordered: $ordered, '
      'maxRetransmits: $maxRetransmits)';
}

/// The shared switchboard fake links find each other through.
///
/// Real peers find each other over the network; fake ones need a rendezvous.
/// One bus per test, passed to every [FakeRtcPeerAdapter] in it.
class FakeRtcBus {
  final Map<String, FakeRtcPeerAdapter> _adapters = {};

  /// Delay applied to every delivery. Zero still means asynchronous — a
  /// microtask hop — not synchronous.
  Duration deliveryDelay = Duration.zero;

  /// Adapters currently on the bus.
  Iterable<FakeRtcPeerAdapter> get adapters => _adapters.values;

  /// The adapter for [selfKey], if it is still open.
  FakeRtcPeerAdapter? adapterFor(String selfKey) => _adapters[selfKey];

  void _register(FakeRtcPeerAdapter adapter) =>
      _adapters[adapter.selfKey] = adapter;

  void _unregister(String selfKey) => _adapters.remove(selfKey);

  /// The link on [peerKey]'s side that faces [fromKey], if it exists yet.
  _FakeRtcPeerLink? _linkBetween({
    required String peerKey,
    required String fromKey,
  }) => _adapters[peerKey]?._links[fromKey];

  /// One suspension, sized like a delivery. What makes "asked for" and "have
  /// it" distinct events for link and channel creation.
  Future<void> _hop() => Future<void>.delayed(deliveryDelay);

  Future<void> _deliver(void Function() action) async {
    if (deliveryDelay == Duration.zero) {
      // A microtask, not a synchronous call: the minimum hop that still makes
      // "sent" and "arrived" distinct events.
      await Future<void>.delayed(Duration.zero);
    } else {
      await Future<void>.delayed(deliveryDelay);
    }
    action();
  }
}

/// A pure-Dart [RtcPeerAdapter] for one peer.
class FakeRtcPeerAdapter implements RtcPeerAdapter {
  FakeRtcPeerAdapter({required this.selfKey, required this.bus}) {
    bus._register(this);
  }

  /// This peer's key — the node uId the remote side will name.
  final String selfKey;
  final FakeRtcBus bus;

  final Map<String, _FakeRtcPeerLink> _links = {};

  /// Links still being built. The real binding needs this and so does the
  /// fake, now that [createLink] suspends like the real one.
  final Map<String, Future<RtcPeerLink>> _pendingLinks = {};
  bool _closed = false;

  /// Every channel this adapter was asked to open, in order and cumulative.
  final List<FakeChannelRequest> openedChannels = [];

  /// Links currently open, for tests that assert on release.
  Iterable<RtcPeerLink> get links => _links.values;

  /// Peers this adapter currently holds a connection to.
  Set<String> get peerKeys => _links.keys.toSet();

  /// Channel ids currently open to [peerKey].
  ///
  /// Shrinks as channels are released, unlike [openedChannels] — which is the
  /// distinction `removeInlet` exists to make.
  Set<int> openChannelIdsTo(String peerKey) => {
    for (final MapEntry(key: id, value: channel)
        in (_links[peerKey]?._channels ?? const <int, _FakeRtcChannel>{})
            .entries)
      if (!channel._closed) id,
  };

  @override
  Future<RtcPeerLink> createLink(
    String peerKey, {
    List<Map<String, Object?>> iceServers = const [],
  }) async {
    if (_closed) throw StateError('Adapter for $selfKey is closed');
    final existing = _links[peerKey];
    if (existing != null) return existing;
    return _pendingLinks[peerKey] ??= _createLink(peerKey);
  }

  Future<RtcPeerLink> _createLink(String peerKey) async {
    try {
      // The gap a platform-channel round trip leaves. See the class comment.
      await bus._hop();
      final link = _FakeRtcPeerLink(adapter: this, peerKey: peerKey);
      _links[peerKey] = link;
      return link;
    } finally {
      _pendingLinks.remove(peerKey);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final link in _links.values.toList(growable: false)) {
      await link.close();
    }
    _links.clear();
    _pendingLinks.clear();
    bus._unregister(selfKey);
  }

  void _forget(String peerKey) => _links.remove(peerKey);
}

class _FakeRtcPeerLink implements RtcPeerLink {
  _FakeRtcPeerLink({required this.adapter, required this.peerKey});

  final FakeRtcPeerAdapter adapter;

  @override
  final String peerKey;

  final _states = StreamController<RtcLinkState>.broadcast();
  final _candidates = StreamController<Map<String, Object?>>.broadcast();
  final Map<int, _FakeRtcChannel> _channels = {};

  /// Channels still being opened. See the class comment on [FakeRtcPeerAdapter].
  final Map<int, Future<RtcChannel>> _pendingChannels = {};

  RtcLinkState _state = RtcLinkState.connecting;
  bool _localSet = false;
  bool _remoteSet = false;

  /// Candidates that arrived before the remote description did.
  ///
  /// Real ICE routinely delivers these out of order, and a transport that
  /// dropped them would work on a fast LAN and fail everywhere else — so the
  /// fake buffers them too, and a test can assert the transport survives it.
  final List<Map<String, Object?>> _pendingCandidates = [];
  final List<Map<String, Object?>> _acceptedCandidates = [];

  /// Candidates applied so far, for tests.
  List<Map<String, Object?>> get acceptedCandidates =>
      List.unmodifiable(_acceptedCandidates);

  @override
  RtcLinkState get state => _state;

  @override
  Stream<RtcLinkState> get states => _states.stream;

  @override
  Stream<Map<String, Object?>> get localCandidates => _candidates.stream;

  @override
  Future<Map<String, Object?>> createOffer() async {
    _ensureOpen();
    _localSet = true;
    _emitCandidate();
    return {'type': 'offer', 'sdp': 'fake-offer:${adapter.selfKey}->$peerKey'};
  }

  @override
  Future<Map<String, Object?>> createAnswer(
    Map<String, Object?> remoteOffer,
  ) async {
    _ensureOpen();
    if (remoteOffer['type'] != 'offer') {
      throw ArgumentError.value(remoteOffer, 'remoteOffer', 'not an offer');
    }
    _applyRemote();
    _localSet = true;
    _emitCandidate();
    // The answerer is connected as soon as it has both descriptions; the
    // offerer gets there when the answer comes back.
    _setState(RtcLinkState.connected);
    return {
      'type': 'answer',
      'sdp': 'fake-answer:${adapter.selfKey}->$peerKey',
    };
  }

  @override
  Future<void> acceptAnswer(Map<String, Object?> remoteAnswer) async {
    _ensureOpen();
    if (remoteAnswer['type'] != 'answer') {
      throw ArgumentError.value(remoteAnswer, 'remoteAnswer', 'not an answer');
    }
    if (!_localSet) {
      throw StateError('acceptAnswer before createOffer on ${adapter.selfKey}');
    }
    _applyRemote();
    _setState(RtcLinkState.connected);
  }

  @override
  Future<void> addCandidate(Map<String, Object?> candidate) async {
    _ensureOpen();
    if (!_remoteSet) {
      _pendingCandidates.add(candidate);
      return;
    }
    _acceptedCandidates.add(candidate);
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
    return _pendingChannels[id] ??= _openChannel(
      id,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    );
  }

  Future<RtcChannel> _openChannel(
    int id, {
    required bool ordered,
    int? maxRetransmits,
  }) async {
    try {
      return await _buildChannel(
        id,
        ordered: ordered,
        maxRetransmits: maxRetransmits,
      );
    } finally {
      _pendingChannels.remove(id);
    }
  }

  Future<RtcChannel> _buildChannel(
    int id, {
    required bool ordered,
    int? maxRetransmits,
  }) async {
    // The gap a platform-channel round trip leaves.
    await adapter.bus._hop();
    _ensureOpen();
    final channel = _FakeRtcChannel(
      link: this,
      id: id,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    );
    _channels[id] = channel;
    adapter.openedChannels.add(
      FakeChannelRequest(
        peerKey: peerKey,
        id: id,
        ordered: ordered,
        maxRetransmits: maxRetransmits,
      ),
    );
    // Pre-negotiated channels open as soon as the connection does — and only
    // then, which is what makes `ready` worth awaiting.
    if (_state == RtcLinkState.connected) channel._open();
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
    _pendingChannels.clear();
    adapter._forget(peerKey);
    await _states.close();
    await _candidates.close();
  }

  /// Fails the link, as an ICE failure would. For tests.
  Future<void> simulateFailure() => close();

  void _ensureOpen() {
    if (_state == RtcLinkState.closed) {
      throw StateError('Link ${adapter.selfKey} -> $peerKey is closed');
    }
  }

  void _applyRemote() {
    _remoteSet = true;
    _acceptedCandidates.addAll(_pendingCandidates);
    _pendingCandidates.clear();
  }

  void _setState(RtcLinkState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
    if (next == RtcLinkState.connected) {
      for (final channel in _channels.values) {
        channel._open();
      }
    }
  }

  void _emitCandidate() {
    final candidate = {
      'candidate': 'fake-host:${adapter.selfKey}',
      'sdpMid': '0',
      'sdpMLineIndex': 0,
    };
    unawaited(
      adapter.bus._deliver(() {
        if (!_candidates.isClosed) _candidates.add(candidate);
      }),
    );
  }

  /// The channel with the same id on the far side, once it exists.
  _FakeRtcChannel? _peerChannel(int id) => adapter.bus
      ._linkBetween(peerKey: peerKey, fromKey: adapter.selfKey)
      ?._channels[id];
}

class _FakeRtcChannel implements RtcChannel {
  _FakeRtcChannel({
    required this.link,
    required this.id,
    required this.ordered,
    required this.maxRetransmits,
  }) {
    _readyGuard;
  }

  final _FakeRtcPeerLink link;

  @override
  final int id;

  /// Recorded, not enforced — the fake delivers everything reliably. A test can
  /// assert the transport *requested* the right mode; only a device proves the
  /// mode does anything.
  final bool ordered;
  final int? maxRetransmits;

  final _messages = StreamController<Object>.broadcast();
  final _readyCompleter = Completer<void>();
  bool _isOpen = false;
  bool _closed = false;

  /// Keeps "closed before it opened" from surfacing as an unhandled async
  /// error when nothing happens to be awaiting [ready]. Attaching the handler
  /// to a *derived* future leaves the original's error intact for real
  /// awaiters.
  late final Object? _readyGuard = () {
    unawaited(_readyCompleter.future.catchError((Object _) {}));
    return null;
  }();

  @override
  bool get isOpen => _isOpen && !_closed;

  @override
  Future<void> get ready {
    _readyGuard;
    return _readyCompleter.future;
  }

  @override
  Stream<Object> get messages => _messages.stream;

  @override
  void send(Object payload) {
    if (!isOpen) return;
    if (payload is! String && payload is! List<int>) {
      throw ArgumentError.value(
        payload,
        'payload',
        'must be a String or a Uint8List',
      );
    }
    final peer = link._peerChannel(id);
    if (peer == null) return;
    unawaited(
      link.adapter.bus._deliver(() {
        if (peer.isOpen && !peer._messages.isClosed) {
          peer._messages.add(payload);
        }
      }),
    );
  }

  void _open() {
    if (_isOpen || _closed) return;
    _isOpen = true;
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _isOpen = false;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(
        StateError('Channel $id closed before it opened'),
      );
    }
    await _messages.close();
  }
}
