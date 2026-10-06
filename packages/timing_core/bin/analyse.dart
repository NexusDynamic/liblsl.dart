import 'dart:convert';
import 'dart:io';

import 'package:timing_core/timing_core.dart';

/// Prints the analysis of run logs.
///
///     dart run timing_core:analyse [--json] <log>...
Future<void> main(List<String> args) async {
  final json = args.contains('--json');
  final paths = args.where((a) => !a.startsWith('-')).toList();
  if (paths.isEmpty) {
    stderr.writeln('Usage: dart run timing_core:analyse [--json] <log>...');
    exitCode = 64;
    return;
  }
  final logs = <RunLog>[];
  for (final path in paths) {
    try {
      logs.add(
        await RunLog.fromStream(
          File(
            path,
          ).openRead().transform(utf8.decoder).transform(const LineSplitter()),
        ),
      );
    } on FormatException catch (e) {
      stderr.writeln('$path: ${e.message}');
      exitCode = 65;
      return;
    } on FileSystemException catch (e) {
      stderr.writeln('$path: ${e.message}');
      exitCode = 66;
      return;
    }
  }
  final report = analyse(logs);
  stdout.write(
    json
        ? '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n'
        : formatReport(report),
  );
}
