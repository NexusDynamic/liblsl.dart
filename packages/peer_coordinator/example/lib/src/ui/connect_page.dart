import 'package:flutter/material.dart';
import 'package:peer_coordinator/websocket.dart';
// Re-exports peer_coordinator itself, so `ITransportConfig` comes from here
// too and there is nothing to import twice.
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';

import '../chat/chat_session.dart';
import 'chat_page.dart';

/// How messages actually travel between peers.
///
/// Both need the hub — discovery and election run through it either way, and
/// [_Transport.direct] additionally uses it to carry the WebRTC offers and
/// answers, because two peers that have never met cannot exchange an offer
/// over the connection the offer is for. They differ in what happens after
/// that.
enum _Transport {
  /// Every message goes to the hub and back out: two hops, always reliable and
  /// ordered.
  relay('Relay', 'Messages go via the hub — two hops, works anywhere'),

  /// Messages go straight to the peer over a data channel; the hub sees only
  /// signalling. One hop, and the only mode that could offer unreliable
  /// delivery for a latency-critical stream.
  direct(
    'Direct',
    'Peer-to-peer data channels — one hop, needs reachable peers',
  );

  const _Transport(this.label, this.blurb);

  final String label;
  final String blurb;
}

/// Collects everything needed to build a [ChatSession], then joins.
///
/// Joining is the slow part — discovery has to run its full timeout before a
/// node can conclude that nobody else is there and elect itself — so the
/// button shows progress and failures land inline rather than in a dialog.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hubController = TextEditingController(text: 'ws://127.0.0.1:8080');
  final _roomController = TextEditingController(text: 'lounge');

  /// STUN servers for the direct transport, whitespace or comma separated.
  ///
  /// Empty by default, and that is the interesting default: with no ICE
  /// servers the only candidates are host candidates, so a direct connection
  /// on a LAN involves no third party at all. A STUN server is what makes the
  /// same session work across NATs, and it still only reflects an address —
  /// the data never touches it.
  final _stunController = TextEditingController();

  _Transport _transport = _Transport.relay;
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _hubController.dispose();
    _roomController.dispose();
    _stunController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    final session = ChatSession(
      displayName: _nameController.text.trim(),
      roomName: _roomController.text.trim(),
      transportConfig: _transportConfig(Uri.parse(_hubController.text.trim())),
    );

    final joined = await session.connect();
    if (!mounted) {
      session.dispose();
      return;
    }
    if (!joined) {
      setState(() {
        _connecting = false;
        _error = session.failureReason ?? 'Could not reach the hub.';
      });
      session.dispose();
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatPage(session: session)));
    session.dispose();
    if (mounted) setState(() => _connecting = false);
  }

  /// The only line in this app that differs between the two transports.
  ///
  /// `ChatSession` takes an `ITransportConfig` and never asks which one it got
  /// — the whole point of the abstraction — so switching medium changes
  /// nothing else here.
  ITransportConfig _transportConfig(Uri hubUri) => switch (_transport) {
    _Transport.relay => WebSocketTransportConfig(hubUri: hubUri),
    _Transport.direct => RtcTransportConfig(
      hubUri: hubUri,
      adapterFactory: flutterWebrtcAdapterFactory,
      iceServers: _iceServers(),
    ),
  };

  /// The STUN field, in the `{'urls': ...}` form `RtcTransportConfig` wants.
  ///
  /// Empty means host candidates only: no STUN, no TURN, no third party, which
  /// covers devices on one LAN and is the default this example ships with.
  /// Crossing a NAT needs a STUN server, which only tells a peer what its own
  /// public address looks like — the data still goes peer to peer. TURN would
  /// put a relay back on the data path, which is the thing this mode exists to
  /// remove, so [_validateIceServers] turns it away.
  ///
  /// One entry per URL rather than one entry with every URL: the `urls` list on
  /// a single entry means "one server, reachable these ways", which is not what
  /// a list of different servers is.
  List<Map<String, Object?>> _iceServers() => [
    for (final url in _splitServers(_stunController.text)) {'urls': url},
  ];

  /// Splits on commas or whitespace, so a pasted list works however it came.
  static Iterable<String> _splitServers(String value) => value
      .split(RegExp(r'[,\s]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);

  /// What the globe button fills in. A well-known public STUN server, so
  /// testing across the internet does not start with finding one.
  static const String _publicStun = 'stun:stun.l.google.com:19302';

  /// Rejects what `RtcTransportConfig` would accept but this mode should not.
  ///
  /// Only reachable while [_Transport.direct] is selected — the field is not in
  /// the tree otherwise, so the form never runs this for a relay session.
  String? _validateIceServers(String? value) {
    final text = value?.trim() ?? '';
    // Empty is the LAN case, and the default: host candidates only.
    if (text.isEmpty) return null;
    for (final url in _splitServers(text)) {
      final scheme = url.split(':').first.toLowerCase();
      if (scheme == 'turn' || scheme == 'turns') {
        // Not a validation technicality: a TURN-relayed connection sends the
        // bytes through someone else's server, so it is peer-to-peer in name
        // only and the halved hop count this mode exists for does not survive
        // it. Relay mode is the honest way to have a relay.
        return 'TURN relays the data — use Relay mode instead';
      }
      if (scheme != 'stun' && scheme != 'stuns') {
        return 'Must start with stun: — e.g. $_publicStun';
      }
      if (url.length <= scheme.length + 1) return 'No host after "$scheme:"';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('peer_coordinator chat')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      helperText: 'Shown to everyone else in the room',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? 'Pick a name' : null,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<_Transport>(
                    segments: [
                      for (final option in _Transport.values)
                        ButtonSegment(value: option, label: Text(option.label)),
                    ],
                    selected: {_transport},
                    onSelectionChanged: _connecting
                        ? null
                        : (selection) =>
                              setState(() => _transport = selection.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _transport.blurb,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _hubController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Hub URL',
                      helperText:
                          'Discovery and signalling, on both transports',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateHubUri,
                  ),
                  if (_transport == _Transport.direct) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _stunController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'STUN servers (optional)',
                        helperText: 'Leave empty on a LAN — no third party',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Use a public STUN server',
                          icon: const Icon(Icons.public),
                          onPressed: _connecting
                              ? null
                              : () => setState(
                                  () => _stunController.text = _publicStun,
                                ),
                        ),
                      ),
                      validator: _validateIceServers,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _roomController,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _connecting ? null : _join(),
                    decoration: const InputDecoration(
                      labelText: 'Room',
                      helperText: 'Nodes only find each other within a room',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? 'Pick a room' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _connecting ? null : _join,
                    child: _connecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Join'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text('Start a hub first:', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SelectableText(
                    'dart run peer_coordinator:hub --host 0.0.0.0 --port 8080',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mirrors what both transport configs will reject, so the user finds out
  /// before a join attempt rather than after one. They agree on the hub URI —
  /// `RtcTransportConfig` needs the same socket for signalling.
  String? _validateHubUri(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || !uri.hasAuthority) return 'Not a URL';
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      return 'Must start with ws:// or wss://';
    }
    return null;
  }
}
