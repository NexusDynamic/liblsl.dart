import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:timing_core/timing_core.dart';

import 'report_page.dart';
import 'timing_session.dart';

/// Opens the XDF run logs that `transport_timing` writes, and reports
/// across every log that is open.
///
/// The report is where many logs are looked at: a sweep is dozens of files,
/// and a tab for every sender in every one of them would be more tabs than
/// can be told apart. One or two logs open with their tabs, a tab per
/// sender with its latency and clock offset over the run; more open with
/// none, and the report opens the tab of any pair asked for.
///
/// Any other XDF file is refused: this app shows what a timing run
/// measured, and `lsl_viewer` shows XDF recordings as they are (run logs
/// included).
class TimingProvider extends SourceProvider {
  /// The most logs that open with their tabs.
  static const int _withTabs = 2;

  @override
  List<String> get fileExtensions => const ['xdf'];

  /// Reading and analysing a log is done in an isolate.
  @override
  int get concurrentOpens => 4;

  Iterable<TimingSession> get _open =>
      app.sessions.whereType<TimingSession>().where((s) => !s.closed);

  /// The report of the logs open now, once it has been asked for; dropped
  /// when a log opens or closes.
  Future<Report>? _report;

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
    final LoadedLog loaded;
    try {
      loaded = await compute(loadTimingLog, bytes);
    } on FormatException {
      throw FormatException('${file.name} is not a transport_timing run log');
    }
    _report = null;
    return TimingSession(file.name, loaded, path: file.path, nameOf: _nameOf);
  }

  @override
  void filesOpened(List<SourceSession> sessions) {
    final open = _open.toList();
    if (open.length <= _withTabs) {
      for (final session in open) {
        session.show();
      }
    }
    // A name may be the one the logs already open were missing.
    for (final session in open) {
      session.refreshNames();
    }
    // Worked out now, while it is being waited for anyway.
    if (open.length > _withTabs) report();
    notifyListeners();
  }

  @override
  void sessionClosed(SourceSession session) {
    _report = null;
    notifyListeners();
  }

  /// The report across every open log, analysed in an isolate and kept
  /// until a log opens or closes.
  Future<Report> report() => _report ??= () {
    final logs = [for (final session in _open) session.log];
    final count = logs.length;
    return app.busy(
      'Analysing $count log${count == 1 ? '' : 's'}',
      () => _analyse(logs),
    );
  }();

  /// Apart from anything of this object, which an isolate cannot be sent.
  static Future<Report> _analyse(List<RunLog> logs) =>
      Isolate.run(() => analyse(logs));

  /// The session and pair behind a row of the report, if that device's log
  /// has samples from that sender.
  (TimingSession, int)? _find(RunReport run, PairReport pair) {
    for (final session in _open) {
      final h = session.log.header;
      if (h.runId != run.runId || h.deviceName != pair.to) continue;
      final index = session.pairs.indexWhere(
        (p) => p.sourceId == pair.sourceId,
      );
      if (index >= 0) return (session, index);
    }
    return null;
  }

  void _showReport(BuildContext context) => showReport(
    context,
    report(),
    actions: ReportActions(
      hasTrace: (run, pair) => _find(run, pair) != null,
      openTrace: (run, pair) {
        final found = _find(run, pair);
        if (found == null) return;
        final (session, index) = found;
        final key = session.show(index);
        final tab = app.tabs.indexWhere(
          (t) => t.session == session && t.group.members.first.key == key,
        );
        if (tab >= 0) app.current = tab;
      },
      closeRuns: (runIds) async {
        for (final session in _open.toList()) {
          if (runIds == null || runIds.contains(session.log.header.runId)) {
            await app.closeSession(session);
          }
        }
        return _open.isEmpty ? null : await report();
      },
    ),
  );

  String get _summary {
    final logs = _open.length;
    final runs = {for (final s in _open) s.log.header.runId}.length;
    return '$logs log${logs == 1 ? '' : 's'} of '
        '$runs run${runs == 1 ? '' : 's'}';
  }

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
      label: Text(_open.isEmpty ? 'Report' : 'Report · $_summary'),
      onPressed: _open.isEmpty ? null : () => _showReport(context),
    ),
  ];

  /// With logs open and no tab: the way to them.
  @override
  List<Widget> welcome(BuildContext context) => [
    if (_open.isNotEmpty)
      FilledButton.tonalIcon(
        icon: const Icon(Icons.table_chart_outlined),
        label: Text('Report of $_summary'),
        onPressed: () => _showReport(context),
      ),
  ];
}
