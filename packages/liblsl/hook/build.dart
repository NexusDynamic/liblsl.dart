import 'dart:io';
import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/cbuilder/run_cbuilder.dart';
import 'package:native_toolchain_c/src/native_toolchain/android_ndk.dart';

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

void main(List<String> args) async {
  await build(args, (input, output) async {
    // This needs to be manually copied from CMakeLists.txt.
    const String libLSLVersion = '1.16.2';
    const String libLSLBranch = '7e61a2e';
    const String libLSLPath = 'src/liblsl-$libLSLBranch';
    final packageName = input.packageName;
    final OS targetOs = input.config.code.targetOS;
    final Architecture targetArchitecture =
        input.config.code.targetArchitecture;

    List<String> flags = [];
    List<String> frameworks = [];
    List<String> libraries = [];

    var defines = <String, String?>{
      // copied from CMakeLists.txt.
      'VERSION': libLSLVersion,
      'LSL_ABI_VERSION': '2',
      'ASIO_NO_DEPRECATED': null,
      'BOOST_ALL_NO_LIB': null,
      'LIBLSL_EXPORTS': null,
      'LSL_VERSION_INFO':
          'git:$libLSLVersion/branch:$libLSLBranch/build:dart_native/compiler:unknown',
      'LOGURU_STACKTRACES': '0',
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
      // @TODO: check which of these are actually necessary.
      defines.addAll({
        '_WIN32_WINNT': '0x0601',
        '_WINDOWS': null,
        '_MBCS': null,
        'WIN32': null,
        '_CRT_SECURE_NO_WARNINGS': null,
        '_WINDLL': null,
        'LSLNOAUTOLINK': null,
      });
      flags.add('/EHsc');
      // Required for ASIO I think.
      libraries.add('winmm');
      // Required for the network interface.
      libraries.add('iphlpapi');
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
        '$libLSLPath/thirdparty/pugixml/pugixml.cpp',
        '$libLSLPath/thirdparty/loguru/loguru.cpp',
      ],
      language: Language.cpp,
      includes: [
        '$libLSLPath/lslboost',
        '$libLSLPath/include',
        '$libLSLPath/thirdparty',
        '$libLSLPath/thirdparty/asio',
        '$libLSLPath/thirdparty/loguru',
        '$libLSLPath/thirdparty/pugixml',
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
      logger:
          Logger('')
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
              package: packageName,
              name: 'libc++_shared.so',
              file: Uri.parse(libPath),
              linkMode: DynamicLoadingBundled(),
              os: targetOs,
              architecture: targetArchitecture,
            ),
          );
          break;
        }
      }
    }
  });
}
