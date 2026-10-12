import 'dart:math' as math;

import 'report.dart';
import 'stats.dart';

/// [report] as plain text, in milliseconds.
String formatReport(Report report) {
  final out = StringBuffer();
  for (final run in report.runs) {
    final first = run.devices.first;
    final duration = first.extra['durationSeconds'];
    out.writeln(
      'Run ${run.runId}: ${first.test} over ${first.backend}, '
      '${first.sampleRate} Hz x ${first.channels} ch'
      '${duration == null ? '' : ', $duration s'}, '
      '${run.devices.length} device(s)',
    );
    for (final warning in run.warnings) {
      out.writeln('  ! $warning');
    }

    if (run.senders.isNotEmpty) {
      out.writeln('\n  Senders (interval ms)');
      for (final s in run.senders) {
        out.writeln(
          '    ${s.device}: sent ${s.sent}'
          '${s.sendMode == null ? '' : ' (${s.sendMode})'}, '
          '${s.achievedRate.toStringAsFixed(2)} Hz achieved, '
          'interval ${_ms(s.sendInterval)}',
        );
      }
    }

    for (final p in run.pairs) {
      out.writeln(
        '\n  ${p.from} -> ${p.to}${p.loopback ? ' (loopback)' : ''}'
        '${p.receiveMode == null ? '' : ' [${p.receiveMode}]'}',
      );
      out.writeln(
        '    received ${p.received}'
        '${p.sent == null ? '' : ' of ${p.sent}'}, '
        'lost ${p.lost} (${(p.lossRate * 100).toStringAsFixed(3)}%)'
        '${_edges(p)}, '
        'duplicates ${p.duplicates}, reordered ${p.reordered}'
        '${p.untimed == 0 ? '' : ', untimed ${p.untimed}'}',
      );
      out.writeln('    latency ms          ${_ms(p.latency)}');
      if (p.latencyFitted != null) {
        out.writeln('    latency ms (fitted) ${_ms(p.latencyFitted)}');
      }
      if (p.latency == null) {
        out.writeln('    uncorrected ms      ${_ms(p.latencyRaw)}');
      }
      if (p.uncertainty case final u?) {
        out.writeln(
          '    clock offset known to ±${_n(u.p50 * 500)} ms (median): every '
          'latency above may be out by that, together; the spread of the '
          'fitted latency is not affected',
        );
      }
      if (p.pollInterval case final poll?) {
        out.writeln(
          '    polled every ${_n(poll * 1e3)} ms: adds '
          '~${_n(poll * 500)} ms mean, ${_n(poll * 1e3 / math.sqrt(12))} ms sd',
        );
      }
      out.writeln('    receive interval ms ${_ms(p.receiveInterval)}');
      if (p.clock case final c?) {
        final drift = c.driftPpm;
        out.writeln(
          '    clock: offset ${_n(c.offsetFirst * 1e3)} -> '
          '${_n(c.offsetLast * 1e3)} ms over ${c.estimates} estimates'
          '${drift == null ? '' : ', drift ${drift.toStringAsFixed(2)}'
                    '${c.driftStdErrPpm == null ? '' : ' ±${c.driftStdErrPpm!.toStringAsFixed(2)}'}'
                    ' ppm'}'
          '${c.residualSd == null ? '' : ', estimates scatter '
                    '${_n(c.residualSd! * 1e3)} ms around the line'}'
          '${c.resets == 0 ? '' : ', ${c.resets} reset(s)'}',
        );
      }
    }

    for (final s in run.symmetry) {
      out.writeln(
        '\n  ${s.a} <-> ${s.b}: ${_n(s.latencyP50 * 1e3)} ms p50, '
        '${_n(s.latencyMean * 1e3)} ms mean, averaged over the two '
        'directions (no clock offset in it); the two offset estimates '
        'disagree by ${_n(s.offsetInconsistency * 1e3)} ms',
      );
    }

    for (final i in run.interactive) {
      out.writeln('\n  ${i.device} (interactive, ms; within the app)');
      if (i.reportedToHeard != null) {
        out.writeln('    touch stamped -> heard  ${_ms(i.reportedToHeard)}');
      }
      if (i.touchToSend != null) {
        out.writeln('    touch heard -> send     ${_ms(i.touchToSend)}');
      }
      for (final entry in i.receiveToShown.entries) {
        out.writeln(
          '    receive -> frame drawn  ${_ms(entry.value)} from ${entry.key}',
        );
      }
    }
    out.writeln();
  }
  return out.toString();
}

/// How many of a pair's lost samples were at the ends of the run, when
/// there are any to tell apart.
String _edges(PairReport p) {
  final edges = p.lostEdges;
  if (edges == null || edges == 0) return '';
  return ': ${p.lostInterior} while receiving, $edges before the first or '
      'after the last received';
}

/// A percentile needs enough values beyond it to mean anything; without
/// them it is left out rather than printed as if it did.
String _ms(Summary? s) => s == null
    ? 'n/a'
    : 'n=${s.count} mean ${_n(s.mean * 1e3)} sd ${_n(s.sd * 1e3)} '
          'min ${_n(s.min * 1e3)} p50 ${_n(s.p50 * 1e3)} '
          'mad ${_n(s.mad * 1e3)} '
          'p95 ${s.reliable(0.95) ? _n(s.p95 * 1e3) : '-'} '
          'p99 ${s.reliable(0.99) ? _n(s.p99 * 1e3) : '-'} '
          'max ${_n(s.max * 1e3)}';

String _n(double value) => value.toStringAsFixed(3);
