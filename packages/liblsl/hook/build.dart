import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// The default name prefix for dynamic libraries per [OS].
const _dylibPrefix = {
  OS.android: 'lib',
  OS.fuchsia: 'lib',
  OS.iOS: 'lib',
  OS.linux: 'lib',
  OS.macOS: 'lib',
  OS.windows: '',
};

String stripPrefix(OS os, String name) {
  final prefix = _dylibPrefix[os];
  if (prefix == null) {
    throw UnsupportedError('OS $os does not have a library prefix');
  }
  if (name.startsWith(prefix)) {
    return name.substring(prefix.length);
  }
  return name;
}

/// Fetches pugixml source (v1.15) via git clone if not already present.
/// This mirrors the CMake FetchContent behavior in Dependencies.cmake.
Future<void> _fetchPugixml(String pugixmlPath) async {
  final dir = Directory(pugixmlPath);
  // This might need to be more robust in the future.
  // For now, the only version used so far is v1.15
  if (dir.existsSync()) return;

  final result = await Process.run('git', [
    'clone',
    '--depth',
    '1',
    '--branch',
    'v1.15',
    'https://github.com/zeux/pugixml.git',
    pugixmlPath,
  ]);
  if (result.exitCode != 0) {
    throw Exception(
      'Failed to fetch pugixml v1.15: ${result.stderr}\n'
      'Ensure git is installed and you have network access.',
    );
  }
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.config.buildCodeAssets) {
      // This needs to be manually copied from CMakeLists.txt.
      const String libLSLVersion = '1.17.5';
      const String libLSLBranch = '9f0b6122';
      const String libLSLPath = 'src/liblsl-$libLSLBranch';
      const String pugixmlPath = 'src/pugixml';
      final OS targetOs = input.config.code.targetOS;
      final packageName = stripPrefix(targetOs, input.packageName);

      // Fetch pugixml source (mirrors CMake FetchContent in Dependencies.cmake).
      await _fetchPugixml(pugixmlPath);

      List<String> flags = [];
      List<String> frameworks = [];
      List<String> libraries = [];

      var defines = <String, String?>{
        // copied from CMakeLists.txt.
        'VERSION': libLSLVersion,
        'LSL_ABI_VERSION': '2',
        'ASIO_NO_DEPRECATED': null,
        'ASIO_DISABLE_VISIBILITY': null,
        'BOOST_ALL_NO_LIB': null,
        'LIBLSL_EXPORTS': null,
        'LSL_VERSION_INFO':
            'git:$libLSLVersion/branch:$libLSLBranch/build:dart_native/compiler:unknown',
        'LOGURU_STACKTRACES': '0',
        'LOGURU_DEBUG_LOGGING': '0',
      };

      var forcedIncludes = <String>[];
      // This is the crossplatform fix for the previous workaround
      // that required a define with quoatation marks around it
      // which breaks CL.exe.
      forcedIncludes.add('src/include/lsl_lib_version.h');

      // osx
      if (targetOs == OS.macOS || targetOs == OS.iOS) {
        // Required to compile on OSX with Apple targets.
        frameworks.add('Foundation');
      }

      // Android
      if (targetOs == OS.android) {
        // Add flag for 16k pages.
        flags.add('-Wl,-z,max-page-size=16384');
      }

      // WIN
      if (targetOs == OS.windows) {
        defines.addAll({
          '_WIN32_WINNT': '0x0601',
          '_CRT_SECURE_NO_WARNINGS': null,
          'LSLNOAUTOLINK': null,
        });
        flags.add('/EHsc');
        libraries.addAll(['winmm', 'iphlpapi', 'mswsock', 'ws2_32']);
      }

      final builder = CBuilder.library(
        name: packageName,
        assetName: 'native_liblsl.dart',
        pic: true,
        std: 'c++17',
        sources: [
          '$libLSLPath/src/buildinfo.cpp',
          '$libLSLPath/src/api_config.cpp',
          '$libLSLPath/src/cancellation.cpp',
          '$libLSLPath/src/common.cpp',
          '$libLSLPath/src/consumer_queue.cpp',
          '$libLSLPath/src/data_receiver.cpp',
          '$libLSLPath/src/info_receiver.cpp',
          '$libLSLPath/src/inlet_connection.cpp',
          '$libLSLPath/src/lsl_resolver_c.cpp',
          '$libLSLPath/src/lsl_inlet_c.cpp',
          '$libLSLPath/src/lsl_outlet_c.cpp',
          '$libLSLPath/src/lsl_streaminfo_c.cpp',
          '$libLSLPath/src/lsl_xml_element_c.cpp',
          '$libLSLPath/src/netinterfaces.cpp',
          '$libLSLPath/src/resolver_impl.cpp',
          '$libLSLPath/src/resolve_attempt_udp.cpp',
          '$libLSLPath/src/sample.cpp',
          '$libLSLPath/src/send_buffer.cpp',
          '$libLSLPath/src/socket_utils.cpp',
          '$libLSLPath/src/stream_info_impl.cpp',
          '$libLSLPath/src/stream_outlet_impl.cpp',
          '$libLSLPath/src/tcp_server.cpp',
          '$libLSLPath/src/time_postprocessor.cpp',
          '$libLSLPath/src/time_receiver.cpp',
          '$libLSLPath/src/udp_server.cpp',
          '$libLSLPath/src/util/cast.cpp',
          '$libLSLPath/src/util/endian.cpp',
          '$libLSLPath/src/util/inireader.cpp',
          '$libLSLPath/src/util/strfuns.cpp',
          '$pugixmlPath/src/pugixml.cpp',
          '$libLSLPath/thirdparty/loguru/loguru.cpp',
        ],
        language: Language.cpp,
        includes: [
          '$libLSLPath/lslboost',
          '$libLSLPath/include',
          '$libLSLPath/thirdparty/asio',
          '$libLSLPath/thirdparty/loguru',
          '$pugixmlPath/src',
        ],
        defines: defines,
        flags: flags,
        frameworks: frameworks,
        libraries: libraries,
        forcedIncludes: forcedIncludes,
      );

      await builder.run(
        input: input,
        output: output,
        logger: Logger('')
          ..level = Level.ALL
          ..onRecord.listen((record) => print(record.message)),
      );
    }
  });
}
