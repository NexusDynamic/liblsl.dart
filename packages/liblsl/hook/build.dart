import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/cbuilder/run_cbuilder.dart';
import 'package:native_toolchain_c/src/native_toolchain/android_ndk.dart';

/// It is possible, but untested, to compile liblsl for WASM.
/// Here is the command that successfully compiled it for WASM:
/// ```bash
/// LSL_SRC=./src/liblsl-e9104554
/// PUGIXML_SRC=./src/pugixml
/// emcc -pthread -sPTHREAD_POOL_SIZE=32 -sEXPORT_NAME=liblsl --no-entry \
///       -sENVIRONMENT=web,worker -DVERSION=1.17.5 -DLSL_ABI_VERSION=2 \
///       -DASIO_NO_DEPRECATED -DBOOST_ALL_NO_LIB -DLIBLSL_EXPORTS \
///       -DASIO_DISABLE_VISIBILITY -DLOGURU_DEBUG_LOGGING=0 \
///       -DLSL_VERSION_INFO=git:x/branch:x/build:dart_native/compiler:unknown \
///       -DLOGURU_STACKTRACES=0 -include ./src/include/lsl_lib_version.h \
///       -I$LSL_SRC/lslboost -I$LSL_SRC/include \
///       -I$LSL_SRC/thirdparty/asio \
///       -I$LSL_SRC/thirdparty/loguru \
///       -I$PUGIXML_SRC/src \
///       $LSL_SRC/src/buildinfo.cpp \
///       $LSL_SRC/src/api_config.cpp \
///       $LSL_SRC/src/cancellation.cpp \
///       $LSL_SRC/src/common.cpp \
///       $LSL_SRC/src/consumer_queue.cpp \
///       $LSL_SRC/src/data_receiver.cpp \
///       $LSL_SRC/src/info_receiver.cpp \
///       $LSL_SRC/src/inlet_connection.cpp \
///       $LSL_SRC/src/lsl_resolver_c.cpp \
///       $LSL_SRC/src/lsl_inlet_c.cpp \
///       $LSL_SRC/src/lsl_outlet_c.cpp \
///       $LSL_SRC/src/lsl_streaminfo_c.cpp \
///       $LSL_SRC/src/lsl_xml_element_c.cpp \
///       $LSL_SRC/src/netinterfaces.cpp \
///       $LSL_SRC/src/resolver_impl.cpp \
///       $LSL_SRC/src/resolve_attempt_udp.cpp \
///       $LSL_SRC/src/sample.cpp \
///       $LSL_SRC/src/send_buffer.cpp \
///       $LSL_SRC/src/socket_utils.cpp \
///       $LSL_SRC/src/stream_info_impl.cpp \
///       $LSL_SRC/src/stream_outlet_impl.cpp \
///       $LSL_SRC/src/tcp_server.cpp \
///       $LSL_SRC/src/time_postprocessor.cpp \
///       $LSL_SRC/src/time_receiver.cpp \
///       $LSL_SRC/src/udp_server.cpp \
///       $LSL_SRC/src/util/cast.cpp \
///       $LSL_SRC/src/util/endian.cpp \
///       $LSL_SRC/src/util/inireader.cpp \
///       $LSL_SRC/src/util/strfuns.cpp \
///       $PUGIXML_SRC/src/pugixml.cpp \
///       $LSL_SRC/thirdparty/loguru/loguru.cpp \
///       -o ./liblsl.js
/// ```

/// The default name prefix for dynamic libraries per [OS].
const _dylibPrefix = {
  OS.android: 'lib',
  OS.fuchsia: 'lib',
  OS.iOS: 'lib',
  OS.linux: 'lib',
  OS.macOS: 'lib',
  OS.windows: '',
};

// extension OSLibraryPrefix on OS {
//   /// The prefix for the library name on this OS.
//   ///
//   /// This is used to determine the library name when building a shared
//   /// library.
//   String get libraryPrefix {
//     final prefix = _dylibPrefix[this];
//     if (prefix == null) {
//       throw UnsupportedError('OS $this does not have a library prefix');
//     }
//     return prefix;
//   }
// }

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

/// This is the same as the one in the native_toolchain_c package
/// with the exception of arm, which is just "arm", instead of
/// "armv7a-linux-androideabi".
const androidNdkArchABIMap = {
  Architecture.arm: 'arm-linux-androideabi',
  Architecture.arm64: 'aarch64-linux-android',
  Architecture.ia32: 'i686-linux-android',
  Architecture.x64: 'x86_64-linux-android',
  Architecture.riscv64: 'riscv64-linux-android',
};

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
      const String libLSLBranch = '76b054da';
      const String libLSLPath = 'src/liblsl-$libLSLBranch';
      const String pugixmlPath = 'src/pugixml';
      final OS targetOs = input.config.code.targetOS;
      final packageName = stripPrefix(targetOs, input.packageName);
      final Architecture targetArchitecture =
          input.config.code.targetArchitecture;

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

      if (targetOs == OS.android) {
        // add libc++_shared.so from the NDK
        final aclang = await androidNdkClang.defaultResolver!.resolve(
          logger: Logger(''),
        );
        for (final tool in aclang) {
          if (tool.tool.name == 'Clang') {
            final sysroot = tool.uri.resolve('../sysroot/').toString();
            // use the arch from native_toolchain_c.
            String libPath =
                '${sysroot}usr/lib/${RunCBuilder.androidNdkClangTargetFlags[targetArchitecture]}/libc++_shared.so';
            // check if path exists.
            if (!File(libPath).existsSync()) {
              // if not we can try the alternate map (this will only fix ARM).
              libPath =
                  '${sysroot}usr/lib/${androidNdkArchABIMap[targetArchitecture]}/libc++_shared.so';
            }
            output.assets.code.add(
              CodeAsset(
                package: input.packageName,
                name: 'libc++_shared.so',
                file: Uri.parse(libPath),
                linkMode: DynamicLoadingBundled(),
              ),
            );
            break;
          }
        }
      }
    }
  });
}
