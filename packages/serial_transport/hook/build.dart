import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds the small serial port shim (src/serial_shim.c) used by the desktop
/// transport. All protocol handling is pure Dart, so nothing is built for
/// other targets: Android and iOS apps supply their own transport, and the
/// web uses WebSerial (hooks do not run for web builds).
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final targetOS = input.config.code.targetOS;
    if (!const [OS.linux, OS.macOS, OS.windows].contains(targetOS)) return;

    await CBuilder.library(
      name: 'serial_transport',
      assetName: 'src/native/serial_bindings.g.dart',
      sources: ['src/serial_shim.c'],
      includes: ['src'],
      std: targetOS == OS.windows ? null : 'c11',
      frameworks: targetOS == OS.macOS ? ['IOKit', 'CoreFoundation'] : [],
      libraries: targetOS == OS.windows ? ['setupapi', 'advapi32'] : const [],
    ).run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.WARNING
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
