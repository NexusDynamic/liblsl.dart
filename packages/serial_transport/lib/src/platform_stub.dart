import 'transport.dart';

/// Used on platforms with neither dart:ffi nor dart:js_interop.
SerialPortProvider createPlatformSerialPortProvider() =>
    const UnsupportedSerialPortProvider();

/// A provider for platforms without built-in serial port access.
class UnsupportedSerialPortProvider implements SerialPortProvider {
  const UnsupportedSerialPortProvider();

  @override
  bool get isSupported => false;

  @override
  bool get requiresUserSelection => false;

  @override
  Future<List<SerialPortInfo>> listPorts() async => const [];

  @override
  Future<SerialPortInfo?> requestPort({
    List<SerialPortFilter> filters = const [],
    bool Function(SerialPortInfo port)? where,
  }) async => null;

  @override
  Future<SerialTransport> open(SerialPortInfo port, {int? baudRate}) =>
      throw UnsupportedError(
        'No built-in serial ports on this platform. Provide a SerialTransport '
        '(e.g. from a USB serial plugin on Android).',
      );
}
