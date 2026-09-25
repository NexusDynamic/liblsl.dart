// The `lsl` command line tool: `dart run lsl_tools:lsl --help`.
import 'dart:io';

import 'package:lsl_tools/cli.dart';

Future<void> main(List<String> args) async {
  final code = await runLslCli(args);
  // Inlets and outlets run in isolates; leave without waiting for them.
  exit(code);
}
