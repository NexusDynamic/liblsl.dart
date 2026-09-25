import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'lsl_session.dart';
import 'bridge/client.dart';
import 'bridge/protocol.dart';
import 'bridge/server.dart';
import 'lsl_dialogs.dart';
import 'lsl_forward.dart';
import 'lsl_recorder.dart';
import 'lsl_replay.dart';
import 'lsl_test_outlets.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'lsl.dart';

/// LSL settings kept in [Preferences.extra].
extension LslPreferences on Preferences {
  static const key = 'lsl.options';

  /// LSL settings (advanced; the defaults suit most uses).
  LslOptions get lsl {
    final raw = extra[key] ?? '';
    if (raw.isEmpty) return const LslOptions();
    try {
      return LslOptions.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return const LslOptions();
    }
  }

  set lsl(LslOptions o) => extra[key] = jsonEncode(o.toJson());
}

/// Streams received over LSL, one tab each; finds them on the network.
class LslProvider extends SourceProvider {
  @override
  List<String> get prefsKeys => const [LslPreferences.key];

  /// Configure liblsl, which must come before any other LSL call (it is
  /// loaded now only if the settings are not the defaults).
  @override
  Future<void> prepare(Preferences prefs) async {
    try {
      lsl.configure(prefs.lsl.network);
    } catch (e) {
      debugPrint('LSL configuration: $e');
    }
  }

  /// Streams on the network, while the LSL dialog looks for them.
  List<LslStreamDescription> streams = [];
  LslDiscovery? _discovery;
  Timer? _discoveryTimer;

  /// Streams being connected to, by key.
  final Set<String> connecting = {};

  /// Streams shared over the network, while sharing.
  LslBridgeServer? bridgeServer;

  /// Bridges connected to.
  final List<LslBridgeClient> bridges = [];

  /// Share [streams] over a WebSocket on [port].
  Future<void> share(
    List<LslStreamDescription> streams, {
    int port = 8765,
    String token = '',
  }) async {
    await stopSharing();
    try {
      bridgeServer = await LslBridgeServer.start(
        streams,
        port: port,
        token: token,
        options: app.prefs.lsl.inlet,
      );
      _shareTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => notifyListeners(),
      );
      app.setStatus(
        'Sharing ${streams.length} LSL streams on port ${bridgeServer!.port}',
      );
    } catch (e) {
      app.setError('Could not share streams: $e');
    }
    notifyListeners();
  }

  Timer? _shareTimer;

  Future<void> stopSharing() async {
    final s = bridgeServer;
    if (s == null) return;
    bridgeServer = null;
    _shareTimer?.cancel();
    notifyListeners();
    await s.close();
  }

  /// Connect to the bridge at [url]; returns an error message, or null.
  Future<String?> connectBridge(Uri url, {String token = ''}) async {
    try {
      final b = await LslBridgeClient.connect(url, token: token);
      bridges.add(b);
      b.onStreams.listen((_) => notifyListeners(), onDone: notifyListeners);
      notifyListeners();
      return null;
    } catch (e) {
      return 'Could not connect: $e';
    }
  }

  Future<void> disconnectBridge(LslBridgeClient b) async {
    bridges.remove(b);
    for (final s in [...sessions]) {
      if (s.inlet.stream.uid.startsWith('bridge:${b.url.host}:')) {
        await app.closeSession(s);
      }
    }
    await b.close();
    notifyListeners();
  }

  /// View bridged [stream] in a new tab.
  void viewBridged(LslBridgeClient b, BridgeStream stream) {
    if (isOpen(stream.description.key)) return;
    app.addSession(LslSession.fromInlet(b.open(stream), app.prefs.lsl.inlet));
    notifyListeners();
  }

  /// Streams being forwarded under another name.
  final List<LslForward> forwards = [];

  /// Forward the stream of [tab] as [name], with only its shown channels
  /// and its processing if asked.
  Future<void> forward(
    TabEntry tab, {
    required String name,
    required bool shownOnly,
    required bool processed,
  }) async {
    final session = tab.session;
    if (session is! LslSession) return;
    final c = tab.controller;
    try {
      forwards.add(
        await LslForward.start(
          session,
          name: name,
          channels: shownOnly ? ([...c.lanes]..sort()) : null,
          derived: processed ? c.spec : DerivedSpec.none,
          options: app.prefs.lsl.outlet,
        ),
      );
      app.setStatus('Forwarding ${session.info.name} as $name');
    } catch (e) {
      app.setError('Could not forward ${session.info.name}: $e');
    }
    notifyListeners();
  }

  Future<void> stopForward(LslForward f) async {
    forwards.remove(f);
    notifyListeners();
    await f.close();
  }

  /// Synthetic streams being sent (Test outlets).
  final List<LslSignalGenerator> generators = [];

  /// The marker stream the user sends on, once used.
  LslMarkerSender? markers;

  Future<void> startGenerator({
    required String name,
    required int channels,
    required double rate,
    required double frequency,
  }) async {
    await lsl.prepare();
    try {
      generators.add(
        await LslSignalGenerator.start(
          name: name,
          channels: channels,
          rate: rate,
          frequency: frequency,
          options: app.prefs.lsl.outlet,
        ),
      );
      app.setStatus('Sending test stream $name over LSL');
    } catch (e) {
      app.setError('Could not start $name: $e');
    }
    notifyListeners();
  }

  Future<void> stopGenerator(LslSignalGenerator g) async {
    generators.remove(g);
    notifyListeners();
    await g.close();
  }

  /// Send [text] on the marker stream (made on first use).
  Future<void> sendMarker(String text) async {
    try {
      if (markers == null) {
        await lsl.prepare();
        markers = await LslMarkerSender.start(
          name: '${app.config.title} markers',
          options: app.prefs.lsl.outlet,
        );
      }
      await markers!.send(text);
      app.setStatus('Marker sent: $text');
    } catch (e) {
      app.setError('Could not send a marker: $e');
    }
    notifyListeners();
  }

  /// A recording being played over LSL.
  LslReplay? replay;
  bool _startingReplay = false;

  /// The recording of the current tab, if it can be replayed.
  SourceSession? get _replayable {
    final s = app.currentTab?.session;
    return s != null && s.replayable ? s : null;
  }

  /// Play [session] over LSL from [from] seconds, or stop the replay.
  Future<void> toggleReplay(SourceSession session, double from) async {
    if (replay != null) {
      final same = replay!.session == session;
      await stopReplay();
      if (same) return;
    }
    if (!lsl.supported || _startingReplay) return;
    _startingReplay = true;
    await lsl.prepare();
    app.setStatus('Starting LSL replay of ${session.label}…');
    try {
      final r = await LslReplay.start(
        session,
        from: from,
        loop: app.prefs.lsl.replayLoop,
        options: app.prefs.lsl.outlet,
      );
      replay = r;
      r.addListener(() {
        if (replay != r) return;
        if (r.finished) {
          stopReplay();
          app.setStatus('LSL replay of ${session.label} finished');
        } else {
          notifyListeners();
        }
      });
      app.setStatus(
        'Replaying ${session.label} over LSL (${r.streamCount} streams)',
      );
    } catch (e) {
      app.setError('Could not replay ${session.label}: $e');
    } finally {
      _startingReplay = false;
      notifyListeners();
    }
  }

  Future<void> stopReplay() async {
    final r = replay;
    if (r == null) return;
    replay = null;
    notifyListeners();
    await r.close();
  }

  @override
  void sessionClosed(SourceSession session) {
    if (replay?.session == session) stopReplay();
    for (final f in [...forwards]) {
      if (f.session == session) stopForward(f);
    }
  }

  String _replayLabel() {
    final r = replay!;
    return 'Stop LSL replay (${r.position.toStringAsFixed(0)} / '
        '${r.end.toStringAsFixed(0)} s)';
  }

  /// Streams being recorded to XDF.
  LslRecorder? recorder;
  bool _startingRecorder = false;
  Timer? _recordTimer;

  /// Record [streams] to an XDF file the user chooses, or stop recording.
  Future<void> toggleRecording(List<LslStreamDescription> streams) async {
    if (recorder != null) {
      await stopRecording();
      return;
    }
    if (_startingRecorder || streams.isEmpty) return;
    _startingRecorder = true;
    try {
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'lsl_${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.xdf';
      final target = await recordingSink(name, directory: app.prefs.recordDir);
      if (target == null) return;
      final (sink, where) = target;
      app.setStatus('Starting to record ${streams.length} streams…');
      recorder = await LslRecorder.start(streams, sink, where: where);
      _recordTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
      app.setStatus('Recording ${streams.length} LSL streams to $where');
    } catch (e) {
      app.setError('Could not record: $e');
    } finally {
      _startingRecorder = false;
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    final r = recorder;
    if (r == null) return;
    recorder = null;
    _recordTimer?.cancel();
    _recordTimer = null;
    notifyListeners();
    await r.stop();
    app.setStatus(
      'Recorded ${r.sampleCount} samples of ${r.streams.length} streams '
      'to ${r.where}',
    );
  }

  String _elapsed() {
    final d = recorder?.elapsed ?? Duration.zero;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:'
        '${two(d.inSeconds % 60)}';
  }

  bool get supported => lsl.supported;

  /// Look for LSL streams until [stopDiscovery], updating [streams].
  Future<void> startDiscovery() async {
    if (!lsl.supported || _discovery != null) return;
    await lsl.prepare();
    try {
      _discovery = lsl.discover();
    } catch (e) {
      app.setStatus('Could not look for LSL streams: $e');
      return;
    }
    Future<void> poll() async {
      final d = _discovery;
      if (d == null) return;
      try {
        final found = await d.streams();
        if (_discovery != d) return;
        found.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        streams = found;
        notifyListeners();
      } catch (e) {
        app.setStatus('Could not look for LSL streams: $e');
      }
    }

    await poll();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
  }

  void stopDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _discovery?.close();
    _discovery = null;
    streams = [];
  }

  /// The open sessions receiving LSL streams.
  Iterable<LslSession> get sessions => app.sessions.whereType<LslSession>();

  /// Whether the stream [key] is open in a tab.
  bool isOpen(String key) => sessions.any((s) => s.key == key);

  /// The session receiving stream [key], if open.
  LslSession? sessionOf(String key) =>
      sessions.where((s) => s.key == key).firstOrNull;

  /// Receive [stream] in a new tab.
  Future<void> connect(LslStreamDescription stream) async {
    if (isOpen(stream.key) || !connecting.add(stream.key)) return;
    notifyListeners();
    app.setStatus('Connecting to ${stream.name}…');
    try {
      final session = await LslSession.open(stream, app.prefs.lsl.inlet);
      app.addSession(session);
    } catch (e) {
      app.setError('Could not connect to ${stream.name}: $e');
    } finally {
      connecting.remove(stream.key);
      notifyListeners();
    }
  }

  /// Save LSL settings. Network settings apply after a restart.
  Future<void> setOptions(LslOptions o) async {
    app.prefs.lsl = o;
    await app.prefs.save();
  }

  @override
  void dispose() {
    stopDiscovery();
    _recordTimer?.cancel();
    recorder?.stop();
    replay?.close();
    for (final g in generators) {
      g.close();
    }
    markers?.close();
    for (final f in forwards) {
      f.close();
    }
    _shareTimer?.cancel();
    bridgeServer?.close();
    for (final b in bridges) {
      b.close();
    }
    super.dispose();
  }

  // -- UI -------------------------------------------------------------------

  @override
  List<ViewerAction> actions(BuildContext context) => [
    // Also on the web, where LSL itself is not available.
    ViewerAction(
      'LSL',
      bridges.isEmpty
          ? 'Connect to an LSL bridge…'
          : 'LSL bridges (${bridges.length})…',
      onPressed: () => showLslBridge(context, this),
      order: 5,
    ),
    if (supported) ...[
      ViewerAction(
        'LSL',
        'View streams…',
        narrowLabel: 'LSL streams…',
        onPressed: () => showLslStreams(context, this),
      ),
      ViewerAction(
        'LSL',
        recorder == null ? 'Record to XDF…' : 'Stop recording (${_elapsed()})',
        narrowLabel: recorder == null
            ? 'Record LSL to XDF…'
            : 'Stop LSL recording (${_elapsed()})',
        icon: recorder == null ? Icons.fiber_manual_record : Icons.stop,
        onPressed: recorder != null
            ? stopRecording
            : () async {
                final chosen = await showLslRecordStreams(context, this);
                if (chosen != null) await toggleRecording(chosen);
              },
        order: 40,
      ),
      if (_replayable != null || replay != null)
        ViewerAction(
          'LSL',
          replay != null ? _replayLabel() : 'Replay this recording from here',
          icon: replay != null ? Icons.stop : Icons.play_arrow,
          onPressed: replay != null
              ? () {
                  stopReplay();
                  app.setStatus('LSL replay stopped');
                }
              : () => toggleReplay(_replayable!, app.currentTab!.controller.t0),
          order: 20,
        ),
      ViewerAction(
        'LSL',
        'Stream info…',
        onPressed: switch (app.currentTab?.session) {
          final LslSession s => () => showLslStreamInfo(
            context,
            s.inlet.stream,
            session: s,
          ),
          _ => null,
        },
        order: 50,
      ),
      ViewerAction(
        'LSL',
        forwards.isEmpty
            ? 'Forward this stream…'
            : 'Forward… (${forwards.length} forwarded)',
        onPressed: app.currentTab?.session is LslSession || forwards.isNotEmpty
            ? () => showLslForward(context, this)
            : null,
        order: 55,
      ),
      if (LslBridgeServer.supported)
        ViewerAction(
          'LSL',
          bridgeServer == null
              ? 'Share streams over the network…'
              : 'Stop sharing (port ${bridgeServer!.port}, '
                    '${bridgeServer!.clientCount} connected)',
          onPressed: bridgeServer == null
              ? () => showLslShare(context, this)
              : stopSharing,
          order: 57,
        ),
      ViewerAction(
        'LSL',
        'Test outlets…',
        narrowLabel: 'LSL test outlets…',
        onPressed: () => showLslTestOutlets(context, this),
        order: 60,
      ),
      ViewerAction(
        'LSL',
        'Settings…',
        narrowLabel: 'LSL settings…',
        onPressed: () => showLslSettings(context, this),
        order: 100,
        divider: true,
      ),
    ],
  ];

  @override
  List<Widget> toolbar(BuildContext context) => [
    if (supported) ...[
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: () => showLslStreams(context, this),
        icon: const Icon(Icons.hub_outlined),
        label: const Text('LSL'),
      ),
    ],
  ];

  @override
  List<Widget> status(BuildContext context) {
    final r = recorder;
    final replaying = replay;
    final sharing = bridgeServer;
    return [
      if (sharing != null)
        Tooltip(
          message:
              'Sharing ${sharing.streams.length} LSL streams on port '
              '${sharing.port} (${sharing.clientCount} connected)',
          child: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.share, size: 14),
          ),
        ),
      if (replaying != null)
        Tooltip(
          message: 'Replaying ${replaying.session.label} over LSL',
          child: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.podcasts, size: 14),
          ),
        ),
      if (r != null)
        Tooltip(
          message:
              'Recording ${r.streams.length} LSL streams to ${r.where} '
              '(${r.sampleCount} samples)',
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.fiber_manual_record,
                  color: Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'XDF ${_elapsed()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
    ];
  }

  @override
  List<Widget> welcome(BuildContext context) => [
    if (supported)
      OutlinedButton.icon(
        onPressed: () => showLslStreams(context, this),
        icon: const Icon(Icons.hub_outlined),
        label: const Text('View an LSL stream…'),
      )
    else
      OutlinedButton.icon(
        onPressed: () => showLslBridge(context, this),
        icon: const Icon(Icons.hub_outlined),
        label: const Text('Connect to an LSL bridge…'),
      ),
  ];
}
