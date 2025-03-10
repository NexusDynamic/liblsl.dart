// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

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
          assetName: 'liblsl_native.dart',
          sources: [
            'src/liblsl-1.16.2/src/buildinfo.cpp',
            // 'src/liblsl-1.16.2/src/api_config.cpp',
            // 'src/liblsl-1.16.2/src/api_config.h',
            // 'src/liblsl-1.16.2/src/api_types.hpp',
            // 'src/liblsl-1.16.2/src/cancellable_streambuf.h',
            // 'src/liblsl-1.16.2/src/cancellation.h',
            // 'src/liblsl-1.16.2/src/cancellation.cpp',
            // 'src/liblsl-1.16.2/src/common.cpp',
            // 'src/liblsl-1.16.2/src/common.h',
            // 'src/liblsl-1.16.2/src/consumer_queue.cpp',
            // 'src/liblsl-1.16.2/src/consumer_queue.h',
            // 'src/liblsl-1.16.2/src/data_receiver.cpp',
            // 'src/liblsl-1.16.2/src/data_receiver.h',
            // 'src/liblsl-1.16.2/src/forward.h',
            // 'src/liblsl-1.16.2/src/info_receiver.cpp',
            // 'src/liblsl-1.16.2/src/info_receiver.h',
            // 'src/liblsl-1.16.2/src/inlet_connection.cpp',
            // 'src/liblsl-1.16.2/src/inlet_connection.h',
            // 'src/liblsl-1.16.2/src/lsl_resolver_c.cpp',
            // 'src/liblsl-1.16.2/src/lsl_inlet_c.cpp',
            // 'src/liblsl-1.16.2/src/lsl_outlet_c.cpp',
            // 'src/liblsl-1.16.2/src/lsl_streaminfo_c.cpp',
            // 'src/liblsl-1.16.2/src/lsl_xml_element_c.cpp',
            // 'src/liblsl-1.16.2/src/netinterfaces.h',
            // 'src/liblsl-1.16.2/src/netinterfaces.cpp',
            // 'src/liblsl-1.16.2/src/portable_archive/portable_archive_exception.hpp',
            // 'src/liblsl-1.16.2/src/portable_archive/portable_archive_includes.hpp',
            // 'src/liblsl-1.16.2/src/portable_archive/portable_iarchive.hpp',
            // 'src/liblsl-1.16.2/src/portable_archive/portable_oarchive.hpp',
            // 'src/liblsl-1.16.2/src/resolver_impl.cpp',
            // 'src/liblsl-1.16.2/src/resolver_impl.h',
            // 'src/liblsl-1.16.2/src/resolve_attempt_udp.cpp',
            // 'src/liblsl-1.16.2/src/resolve_attempt_udp.h',
            // 'src/liblsl-1.16.2/src/sample.cpp',
            // 'src/liblsl-1.16.2/src/sample.h',
            // 'src/liblsl-1.16.2/src/send_buffer.cpp',
            // 'src/liblsl-1.16.2/src/send_buffer.h',
            // 'src/liblsl-1.16.2/src/socket_utils.cpp',
            // 'src/liblsl-1.16.2/src/socket_utils.h',
            // 'src/liblsl-1.16.2/src/stream_info_impl.cpp',
            // 'src/liblsl-1.16.2/src/stream_info_impl.h',
            // 'src/liblsl-1.16.2/src/stream_inlet_impl.h',
            // 'src/liblsl-1.16.2/src/stream_outlet_impl.cpp',
            // 'src/liblsl-1.16.2/src/stream_outlet_impl.h',
            // 'src/liblsl-1.16.2/src/tcp_server.cpp',
            // 'src/liblsl-1.16.2/src/tcp_server.h',
            // 'src/liblsl-1.16.2/src/time_postprocessor.cpp',
            // 'src/liblsl-1.16.2/src/time_postprocessor.h',
            // 'src/liblsl-1.16.2/src/time_receiver.cpp',
            // 'src/liblsl-1.16.2/src/time_receiver.h',
            // 'src/liblsl-1.16.2/src/udp_server.cpp',
            // 'src/liblsl-1.16.2/src/udp_server.h',
            // 'src/liblsl-1.16.2/src/util/cast.hpp',
            // 'src/liblsl-1.16.2/src/util/cast.cpp',
            // 'src/liblsl-1.16.2/src/util/endian.cpp',
            // 'src/liblsl-1.16.2/src/util/endian.hpp',
            // 'src/liblsl-1.16.2/src/util/inireader.hpp',
            // 'src/liblsl-1.16.2/src/util/inireader.cpp',
            // 'src/liblsl-1.16.2/src/util/strfuns.hpp',
            // 'src/liblsl-1.16.2/src/util/strfuns.cpp',
            // 'src/liblsl-1.16.2/src/util/uuid.hpp',
            // 'src/liblsl-1.16.2/thirdparty/loguru/loguru.cpp',
            // // Headers
            // 'src/liblsl-1.16.2/include/lsl_c.h',
            // 'src/liblsl-1.16.2/include/lsl_cpp.h',
            // 'src/liblsl-1.16.2/include/lsl/common.h',
            // 'src/liblsl-1.16.2/include/lsl/inlet.h',
            // 'src/liblsl-1.16.2/include/lsl/outlet.h',
            // 'src/liblsl-1.16.2/include/lsl/resolver.h',
            // 'src/liblsl-1.16.2/include/lsl/streaminfo.h',
            // 'src/liblsl-1.16.2/include/lsl/types.h',
            // 'src/liblsl-1.16.2/include/lsl/xml.h',

            // // pugiXML
            // 'src/liblsl-1.16.2/thirdparty/pugixml/pugixml.cpp',
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

            MapEntry('_WIN32_WINNT', '0x0601'), // WINDOWS ONLY
            MapEntry('_WINDOWS', ''), // WINDOWS ONLY
            MapEntry('_MBCS', ''), // WINDOWS ONLY
            MapEntry('WIN32', ''), // WINDOWS ONLY
            MapEntry('_CRT_SECURE_NO_WARNINGS', ''), // WINDOWS ONLY
            MapEntry('_WINDLL', ''), // WINDOWS ONLY
            MapEntry('LSLNOAUTOLINK', ''), // WINDOWS ONLY

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
            '-EHsc', // WINDOWS ONLY
          ]),
    ];

    // Note: These builders need to be run sequentially because they depend on
    // each others output.
    for (final builder in builders) {
      await builder.run(input: input, output: output, logger: logger);
    }
  });
}
