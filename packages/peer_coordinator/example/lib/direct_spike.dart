// SPIKE, throwaway: can two peers open a WebRTC data channel with no hub,
// by exchanging one invite code and one answer code by hand?
//
//   flutter run -t lib/direct_spike.dart -d chrome      (or -d macos)
//
// One side hosts and shows an invite code; the other pastes it and shows an
// answer code; the host pastes that. Each code is a whole session
// description with its ICE candidates in it, so nothing else is exchanged.
// Once the channel opens, the page measures the clock offset and round trip
// with the estimator the transports use.
//
// Opened with `?selftest` it connects two peers inside the page and prints
// the result to the console, which checks the mechanics without a second
// machine (and nothing about real networks).
//
// Keep the tab in front: a hidden tab's timers run once a second, the
// probes of a burst then go out together, and no clock estimate is accepted.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_coordinator/coordination.dart';
import 'package:peer_coordinator/data.dart';

const _stun = [
  {'urls': 'stun:stun.l.google.com:19302'},
];

/// One end of a hand-signalled connection.
class DirectPeer {
  DirectPeer({required this.useStun, this.onChange});

  final bool useStun;
  final VoidCallback? onChange;

  RTCPeerConnection? _connection;
  RTCDataChannel? _channel;

  // Tracked here: the plugin's own `state` is not kept up to date on the web.
  bool _isOpen = false;
  final _watch = Stopwatch();
  final _opened = Completer<void>();
  late final ClockSyncService _sync = ClockSyncService(
    offsets: PeerClockOffsets(),
    sendProbe: (_, wave, _) => _send({'ping': PeerClock.now(), 'wave': wave}),
    onEstimate: (_, estimate) {
      this.estimate = estimate;
      rtts.add(estimate.uncertainty);
      onChange?.call();
    },
  );

  /// What this end gathered: `host 192.168.1.4`, `host (mDNS)`, `srflx …`.
  List<String> candidates = [];
  String state = 'idle';
  Duration? connectedAfter;
  String? route;
  ClockOffsetEstimate? estimate;
  final List<double> rtts = [];
  int sent = 0, received = 0;
  String? problem;

  Future<void> get opened => _opened.future;

  Future<RTCPeerConnection> _open() async {
    final connection = _connection = await createPeerConnection({
      'iceServers': useStun ? _stun : const <Object>[],
      'sdpSemantics': 'unified-plan',
    });
    connection.onConnectionState = (s) {
      state = s.name.replaceFirst('RTCPeerConnectionState', '');
      onChange?.call();
    };
    // Negotiated, as the transport's channels are: both ends create id 1.
    final channel = _channel = await connection.createDataChannel(
      'direct',
      RTCDataChannelInit()
        ..negotiated = true
        ..id = 1,
    );
    channel.onDataChannelState = (s) {
      _isOpen = s == RTCDataChannelState.RTCDataChannelOpen;
      if (!_isOpen) return;
      connectedAfter = _watch.elapsed;
      if (!_opened.isCompleted) _opened.complete();
      _sync.trackPeer('peer');
      _describeRoute();
      onChange?.call();
    };
    channel.onMessage = (m) {
      received++;
      try {
        _onMessage(jsonDecode(m.text) as Map);
      } catch (e) {
        problem = '$e';
      }
    };
    return connection;
  }

  /// The local description once every candidate is in it.
  Future<String> _code(RTCPeerConnection connection) async {
    final gathered = Completer<void>();
    connection.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    if (connection.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      gathered.complete();
    }
    await gathered.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    final local = (await connection.getLocalDescription())!;
    candidates = [
      for (final line in const LineSplitter().convert(local.sdp ?? ''))
        if (line.startsWith('a=candidate:')) _candidate(line),
    ];
    onChange?.call();
    return base64Url.encode(
      utf8.encode(jsonEncode({'type': local.type, 'sdp': local.sdp})),
    );
  }

  /// `a=candidate:… <proto> <priority> <address> <port> typ <type> …`
  static String _candidate(String line) {
    final f = line.split(' ');
    if (f.length < 8) return line;
    final address = f[4].endsWith('.local') ? '(mDNS)' : f[4];
    return '${f[7]} ${f[2].toLowerCase()} $address';
  }

  static RTCSessionDescription _decode(String code, String expected) {
    final json = jsonDecode(utf8.decode(base64Url.decode(code.trim()))) as Map;
    if (json['type'] != expected) {
      throw FormatException('This is not an $expected code');
    }
    return RTCSessionDescription(json['sdp'] as String, expected);
  }

  /// Host, step 1: the invite code.
  Future<String> invite() async {
    _watch.start();
    final connection = await _open();
    await connection.setLocalDescription(await connection.createOffer({}));
    return _code(connection);
  }

  /// Joiner: the answer code for [inviteCode].
  Future<String> join(String inviteCode) async {
    _watch.start();
    final connection = await _open();
    await connection.setRemoteDescription(_decode(inviteCode, 'offer'));
    await connection.setLocalDescription(await connection.createAnswer({}));
    return _code(connection);
  }

  /// Host, step 2.
  Future<void> accept(String answerCode) =>
      _connection!.setRemoteDescription(_decode(answerCode, 'answer'));

  void _send(Map<String, Object?> message) {
    if (!_isOpen) return;
    sent++;
    _channel!.send(RTCDataChannelMessage(jsonEncode(message)));
  }

  void _onMessage(Map<dynamic, dynamic> m) {
    final now = PeerClock.now();
    if (m['ping'] case final num t0) {
      _send({'pong': t0, 'wave': m['wave'], 't1': now, 't2': PeerClock.now()});
    } else if (m['pong'] case final num t0) {
      _sync.recordReply(
        'peer',
        (m['wave'] as num).toInt(),
        ClockProbeSample(
          t0: t0.toDouble(),
          t1: (m['t1'] as num).toDouble(),
          t2: (m['t2'] as num).toDouble(),
          t3: now,
        ),
      );
    }
  }

  /// Which candidates ICE chose, e.g. `host → prflx`.
  Future<void> _describeRoute() async {
    try {
      final stats = await _connection!.getStats();
      final byId = {for (final s in stats) s.id: s};
      for (final s in stats) {
        if (s.type != 'candidate-pair') continue;
        final v = s.values;
        if (v['nominated'] != true && v['selected'] != true) continue;
        final local = byId[v['localCandidateId']]?.values;
        final remote = byId[v['remoteCandidateId']]?.values;
        route =
            '${local?['candidateType'] ?? '?'} → '
            '${remote?['candidateType'] ?? '?'} '
            '(${local?['protocol'] ?? '?'})';
        onChange?.call();
        return;
      }
    } catch (e) {
      route = 'unknown ($e)';
    }
  }

  String get summary {
    String ms(double s) => (s * 1000).toStringAsFixed(2);
    final e = estimate;
    return [
      'state: $state',
      'messages: $sent sent, $received received'
          '${problem == null ? '' : ', problem: $problem'}',
      'candidates: ${candidates.isEmpty ? 'none' : candidates.join(', ')}',
      if (connectedAfter != null)
        'channel open after ${connectedAfter!.inMilliseconds} ms',
      if (route != null) 'route: $route',
      if (e != null)
        'clock offset ${ms(e.offset)} ms ±${ms(e.uncertainty / 2)} ms',
      if (rtts.isNotEmpty)
        'round trip min ${ms(rtts.reduce((a, b) => a < b ? a : b))} / '
            'mean ${ms(rtts.reduce((a, b) => a + b) / rtts.length)} / '
            'max ${ms(rtts.reduce((a, b) => a > b ? a : b))} ms '
            '(${rtts.length} bursts)',
    ].join('\n');
  }

  Future<void> close() async {
    _isOpen = false;
    _sync.dispose();
    for (final close in [_channel?.close, _connection?.close]) {
      try {
        await close?.call();
      } catch (e) {
        debugPrint('close: $e');
      }
    }
  }
}

/// Two peers in this page, signalled through the same codes.
Future<void> _selfTest({required bool useStun}) async {
  final host = DirectPeer(useStun: useStun);
  final joiner = DirectPeer(useStun: useStun);
  try {
    final invite = await host.invite();
    final answer = await joiner.join(invite);
    await host.accept(answer);
    await Future.wait([
      host.opened,
      joiner.opened,
    ]).timeout(const Duration(seconds: 15));
    // One burst of clock probes.
    await Future<void>.delayed(const Duration(seconds: 2));
    debugPrint(
      'SELFTEST OK stun=$useStun invite=${invite.length} chars '
      'answer=${answer.length} chars\n'
      '--- host\n${host.summary}\n--- joiner\n${joiner.summary}',
    );
  } catch (e) {
    debugPrint(
      'SELFTEST FAILED stun=$useStun: $e\n'
      '--- host\n${host.summary}\n--- joiner\n${joiner.summary}',
    );
  } finally {
    await host.close();
    await joiner.close();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb && Uri.base.queryParameters.containsKey('selftest')) {
    _selfTest(useStun: false)
        .then((_) => _selfTest(useStun: true))
        .then((_) => debugPrint('SELFTEST DONE'));
  }
  runApp(const MaterialApp(title: 'Direct WebRTC spike', home: _SpikePage()));
}

class _SpikePage extends StatefulWidget {
  const _SpikePage();

  @override
  State<_SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<_SpikePage> {
  final _pasted = TextEditingController();
  DirectPeer? _peer;
  bool _useStun = false;
  bool _hosting = false;
  String? _code;
  String? _error;

  DirectPeer _start() {
    _peer?.close();
    return _peer = DirectPeer(
      useStun: _useStun,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() => _error = null);
    try {
      await step();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _peer?.close();
    _pasted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text('Direct WebRTC spike (no hub)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Use a public STUN server'),
            subtitle: const Text(
              'Off: only this device\'s own addresses. Takes effect on the '
              'next Host or Join.',
            ),
            value: _useStun,
            onChanged: (v) => setState(() => _useStun = v),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _run(() async {
                  _hosting = true;
                  _code = await _start().invite();
                }),
                child: const Text('Host: create an invite code'),
              ),
              FilledButton.tonal(
                onPressed: () => _run(() async {
                  _hosting = false;
                  _code = await _start().join(_pasted.text);
                }),
                child: const Text('Join: answer the pasted invite'),
              ),
              OutlinedButton(
                onPressed: _hosting && _peer != null
                    ? () => _run(() => _peer!.accept(_pasted.text))
                    : null,
                child: const Text('Host: accept the pasted answer'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pasted,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Paste the other side\'s code here',
            ),
          ),
          if (code != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_hosting ? 'Invite' : 'Answer'} code '
                    '(${code.length} characters): send it to the other side',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ],
            ),
            SelectableText(
              code,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_peer != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(_peer!.summary),
            ),
        ],
      ),
    );
  }
}
