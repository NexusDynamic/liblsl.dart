@TestOn('browser')
library;

import 'package:serial_transport/serial_transport.dart';
import 'package:test/test.dart';

void main() {
  final provider = SerialPortProvider.platform();

  test('the platform provider is WebSerial', () {
    expect(provider.requiresUserSelection, isTrue);
  });

  test('lists granted ports without throwing', () async {
    if (!provider.isSupported) {
      markTestSkipped('WebSerial not available in this browser');
      return;
    }
    // A test browser has not granted any ports.
    expect(await provider.listPorts(), isEmpty);
  });

  test('opening a non-WebSerial port is rejected', () {
    expect(
      () => provider.open(const SerialPortInfo(id: '/dev/ttyACM0')),
      throwsA(anyOf(isArgumentError, isUnsupportedError)),
    );
  });
}
