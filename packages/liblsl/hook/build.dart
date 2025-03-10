// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;

    final builder = CBuilder.library(
        name: packageName,
        assetName: '$packageName.dart',
        sources: [
          'src/liblsl-1.16.2/src/buildinfo.cpp',
        ],
        language: Language.cpp,
        includes: [
          'src/liblsl-1.16.2/lslboost',
          'src/liblsl-1.16.2/include',
          'src/liblsl-1.16.2/thirdparty',
          'src/liblsl-1.16.2/thirdparty/asio',
          'src/liblsl-1.16.2/thirdparty/loguru',
          'src/liblsl-1.16.2/thirdparty/catch2',
          'src/liblsl-1.16.2/thirdparty/pugixml',
        ],
        defines: Map<String, String>.fromEntries([
          // copied from CMakeLists.txt...probably needs tweaking
          MapEntry('VERSION', '1.16.2'),
          MapEntry('LSL_ABI_VERSION', '2'),
          MapEntry('LSL_DEBUGLOG', '0'),
          MapEntry('LSL_UNIXFOLDERS', '1'),
          MapEntry('LSL_FORCE_FANCY_LIBNAME', '0'),
          MapEntry('LSL_BUILD_EXAMPLES', '0'),
          MapEntry('LSL_BUILD_STATIC', '0'),
          MapEntry('LSL_LEGACY_CPP_ABI', '0'),
          MapEntry('LSL_OPTIMIZATIONS', '1'),
          MapEntry('LSL_UNITTESTS', '0'),
          MapEntry('LSL_BUNDLED_BOOST', '1'),
          MapEntry('LSL_BUNDLED_PUGIXML', '1'),
          MapEntry('LSL_SLIMARCHIVE', '0'),
          MapEntry('LSL_TOOLS', '0'),

          // MapEntry('_WIN32_WINNT', '0x0601'), // WINDOWS ONLY
          // MapEntry('_WINDOWS', ''), // WINDOWS ONLY
          // MapEntry('_MBCS', ''), // WINDOWS ONLY
          // MapEntry('WIN32', ''), // WINDOWS ONLY
          // MapEntry('_CRT_SECURE_NO_WARNINGS', ''), // WINDOWS ONLY
          // MapEntry('_WINDLL', ''), // WINDOWS ONLY
          // MapEntry('LSLNOAUTOLINK', ''), // WINDOWS ONLY

          MapEntry('ASIO_NO_DEPRECATED', ''),

          MapEntry('BOOST_ALL_NO_LIB', ''),

          MapEntry('LIBLSL_EXPORTS', ''),
          MapEntry('lsl_EXPORTS', ''),
          MapEntry('LSL_VERSION_INFO',
              'git:v1.16.2/branch:v1.16.2/build:dart_native/compiler:xxx'),
          MapEntry('LSL_VERSION_INFO',
              'git:v1.16.2/branch:v1.16.2/build:dart_native/compiler:xxx/link:SHARED'),
          MapEntry('LOGURU_STACKTRACES', '0'),
        ]),
        flags: [
          '-std=c++17',
          '-fPIC',
          // '-EHsc', // WINDOWS ONLY
        ]);

    await builder.run(
        input: input,
        output: output,
        logger: Logger('')
          ..level = Level.ALL
          ..onRecord.listen((record) => print(record.message)));
  });
}
