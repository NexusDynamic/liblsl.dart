import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'lsl_session.dart';
import 'lsl_dialogs.dart';
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
    super.dispose();
  }

  // -- UI -------------------------------------------------------------------

  @override
  List<ViewerAction> actions(BuildContext context) => [
    if (supported) ...[
      ViewerAction(
        'LSL',
        'View streams…',
        narrowLabel: 'LSL streams…',
        onPressed: () => showLslStreams(context, this),
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
  List<Widget> welcome(BuildContext context) => [
    if (supported)
      OutlinedButton.icon(
        onPressed: () => showLslStreams(context, this),
        icon: const Icon(Icons.hub_outlined),
        label: const Text('View an LSL stream…'),
      ),
  ];
}
