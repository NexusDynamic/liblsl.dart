/// Serial ports on every platform Dart runs on: native ports on Linux,
/// macOS and Windows (through a small C shim built by the package's build
/// hook), WebSerial in browsers, and [SerialTransport] for anything else
/// (e.g. a USB serial plugin on Android).
library;

export 'src/transport.dart';
