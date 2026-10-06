import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:timing_core/timing_core.dart';

import 'report_page.dart';
import 'timing_session.dart';

RunLog _parse(Uint8List bytes) =>
    RunLog.parse(const LineSplitter().convert(utf8.decode(bytes)));

/// Opens `transport_timing` run logs (`.ttlog`): a tab per sender with its
/// latency and clock offset over the run, and a report across every log
/// that is open.
class TimingProvider extends SourceProvider {
  @override
  List<String> get fileExtensions => const ['ttlog'];

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
    final session = TimingSession(
      file.name,
      await compute(_parse, bytes),
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
