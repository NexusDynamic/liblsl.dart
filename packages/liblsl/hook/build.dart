// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final logger = Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message));

    final builders = [
      CBuilder.library(
        name: 'liblsl',
        assetName: 'liblsl',
        sources: ['src/liblsl-1.16.2/src/common.cpp'],
        includes: [
          'src/liblsl-1.16.2/lslboost',
          'src/liblsl-1.16.2/include',
          'src/liblsl-1.16.2/thirdparty',
          'src/liblsl-1.16.2/thirdparty/asio',
          'src/liblsl-1.16.2/thirdparty/loguru',
          'src/liblsl-1.16.2/thirdparty/catch2',
          'src/liblsl-1.16.2/thirdparty/pugixml',
        ],
      ),
    ];

    // Note: These builders need to be run sequentially because they depend on
    // each others output.
    for (final builder in builders) {
      await builder.run(input: input, output: output, logger: logger);
    }
  });
}
