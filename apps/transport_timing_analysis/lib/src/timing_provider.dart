import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:timing_core/timing_core.dart';

import 'report_page.dart';
import 'timing_session.dart';

/// Opens the XDF run logs that `transport_timing` writes: a tab per sender
/// with its latency and clock offset over the run, and a report across
/// every log that is open.
///
/// Any other XDF file is refused: this app shows what a timing run
/// measured, and `lsl_viewer` shows XDF recordings as they are (run logs
/// included).
class TimingProvider extends SourceProvider {
  @override
  List<String> get fileExtensions => const ['xdf'];

  Iterable<TimingSession> get _open =>
      app.sessions.whereType<TimingSession>().where((s) => !s.closed);

  /// The device that sends as [sourceId], if its log is open.
  String? _nameOf(String sourceId) {
    for (final session in _open) {
      if (session.log.header.sourceId == sourceId) {
        return session.log.header.deviceName;
      }
    }
    return null;
  }

  @override
  Future<SourceSession> openFile(PickedFile file) async {
    final source = file.spec.open();
    final Uint8List bytes;
    try {
      bytes = await source.read(0, source.length);
    } finally {
      await source.close();
    }
    final RunLog log;
    try {
      log = await compute(RunLog.parse, bytes);
    } on FormatException {
      throw FormatException('${file.name} is not a transport_timing run log');
    }
    final session = TimingSession(
      file.name,
      log,
      path: file.path,
      nameOf: _nameOf,
    );
    // Its name may be the one the logs already open were missing; they
    // look it up again once it has joined them.
    final others = _open.toList();
    Future<void>.delayed(Duration.zero, () {
      for (final other in others) {
        if (!other.closed) other.refreshNames();
      }
      notifyListeners();
    });
    return session;
  }

  @override
  void sessionClosed(SourceSession session) => notifyListeners();

  void _showReport(BuildContext context) =>
      showReport(context, analyse([for (final session in _open) session.log]));

  @override
  List<ViewerAction> actions(BuildContext context) => [
    ViewerAction(
      'Timing',
      'Report…',
      narrowLabel: 'Timing report…',
      icon: Icons.table_chart_outlined,
      onPressed: _open.isEmpty ? null : () => _showReport(context),
    ),
  ];

  @override
  List<Widget> toolbar(BuildContext context) => [
    TextButton.icon(
      icon: const Icon(Icons.table_chart_outlined),
      label: const Text('Report'),
      onPressed: _open.isEmpty ? null : () => _showReport(context),
    ),
  ];
}
