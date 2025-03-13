import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/cbuilder/run_cbuilder.dart';
import 'package:native_toolchain_c/src/native_toolchain/android_ndk.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final OS targetOs = input.config.code.targetOS;
    // ignore: unused_local_variable, just because it might be useful later
    final Architecture targetArchitecture =
        input.config.code.targetArchitecture;

    List<String> flags = [];
    List<String> frameworks = [];
    List<String> libraries = [];

    var defines = <String, String?>{
      // copied from CMakeLists.txt...probably needs tweaking
      'VERSION': '1.16.2',
      'LSL_ABI_VERSION': '2',
      'ASIO_NO_DEPRECATED': null,
      'BOOST_ALL_NO_LIB': null,
      'LIBLSL_EXPORTS': null,
      'LSL_VERSION_INFO':
          'git:v1.16.2/branch:v1.16.2/build:dart_native/compiler:unknown',
      'LOGURU_STACKTRACES': '0',
    };

    if (targetOs != OS.windows) {
      // this doesn't work on windows for now
      // see: https://github.com/dart-lang/native/issues/2095
      // and: https://github.com/dart-lang/native/pull/2096
      defines['LSL_LIBRARY_INFO_STR'] =
          '"${defines['LSL_VERSION_INFO']}/link:SHARED"';
    }

    // osx
    if (targetOs == OS.macOS || targetOs == OS.iOS) {
      frameworks.add('Foundation');
    }

    // Android
    if (targetOs == OS.android) {
      // add flag for 16k pages
      flags.add('-Wl,-z,max-page-size=16384');
    }

    // WIN
    if (targetOs == OS.windows) {
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
      libraries.add('winmm');
      libraries.add('iphlpapi');
    }

    final builder = CBuilder.library(
      name: packageName,
      assetName: '$packageName.dart',
      pic: true,
      std: 'c++17',
      sources: [
        'src/liblsl-1.16.2/src/buildinfo.cpp',
        'src/liblsl-1.16.2/src/api_config.cpp',
        'src/liblsl-1.16.2/src/cancellation.cpp',
        'src/liblsl-1.16.2/src/common.cpp',
        'src/liblsl-1.16.2/src/consumer_queue.cpp',
        'src/liblsl-1.16.2/src/data_receiver.cpp',
        'src/liblsl-1.16.2/src/info_receiver.cpp',
        'src/liblsl-1.16.2/src/inlet_connection.cpp',
        'src/liblsl-1.16.2/src/lsl_resolver_c.cpp',
        'src/liblsl-1.16.2/src/lsl_inlet_c.cpp',
        'src/liblsl-1.16.2/src/lsl_outlet_c.cpp',
        'src/liblsl-1.16.2/src/lsl_streaminfo_c.cpp',
        'src/liblsl-1.16.2/src/lsl_xml_element_c.cpp',
        'src/liblsl-1.16.2/src/netinterfaces.cpp',
        'src/liblsl-1.16.2/src/resolver_impl.cpp',
        'src/liblsl-1.16.2/src/resolve_attempt_udp.cpp',
        'src/liblsl-1.16.2/src/sample.cpp',
        'src/liblsl-1.16.2/src/send_buffer.cpp',
        'src/liblsl-1.16.2/src/socket_utils.cpp',
        'src/liblsl-1.16.2/src/stream_info_impl.cpp',
        'src/liblsl-1.16.2/src/stream_outlet_impl.cpp',
        'src/liblsl-1.16.2/src/tcp_server.cpp',
        'src/liblsl-1.16.2/src/time_postprocessor.cpp',
        'src/liblsl-1.16.2/src/time_receiver.cpp',
        'src/liblsl-1.16.2/src/udp_server.cpp',
        'src/liblsl-1.16.2/src/util/cast.cpp',
        'src/liblsl-1.16.2/src/util/endian.cpp',
        'src/liblsl-1.16.2/src/util/inireader.cpp',
        'src/liblsl-1.16.2/src/util/strfuns.cpp',
        'src/liblsl-1.16.2/thirdparty/pugixml/pugixml.cpp',
        'src/liblsl-1.16.2/thirdparty/loguru/loguru.cpp',
        'src/liblsl-1.16.2/lslboost/serialization_objects.cpp',
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
      defines: defines,
      flags: flags,
      frameworks: frameworks,
      libraries: libraries,
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
          final androidArch =
              RunCBuilder.androidNdkClangTargetFlags[targetArchitecture];
          final libPath = '$sysroot/usr/lib/$androidArch/libc++_shared.so';
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
