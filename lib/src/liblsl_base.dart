import 'dart:ffi';
import 'dart:io';
import 'package:system_info2/system_info2.dart';
import 'package:liblsl/liblsl.dart';

/// Checks if you are awesome. Spoiler: you are.
class Awesome {
  bool get isAwesome => true;
}

DynamicLibrary loadLibrary() {
  if (Platform.isWindows) {
    return DynamicLibrary.open(
        '${Directory.current.path}/liblsl/liblsl.1.16.2-win-amd64.dll');
  }
  if (Platform.isMacOS) {
    if (SysInfo.kernelArchitecture == ProcessorArchitecture.arm64) {
      return DynamicLibrary.open(
          '${Directory.current.path}/liblsl/liblsl.1.16.2-osx-arm64.dylib');
    } else {
      return DynamicLibrary.open(
          '${Directory.current.path}/liblsl/liblsl.1.16.2-osx-amd64.dylib');
    }
  } else if (Platform.isLinux) {
    return DynamicLibrary.open(
        '${Directory.current.path}/liblsl/liblsl.1.16.2-linux-amd64.so');
  }
  throw 'libusb dynamic library not found';
}

final liblsl = Liblsl(loadLibrary());
