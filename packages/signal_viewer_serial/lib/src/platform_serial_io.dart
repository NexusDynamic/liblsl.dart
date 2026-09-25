import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:serial_transport/serial_transport.dart';
import 'package:usb_serial/usb_serial.dart';

SerialPortProvider platformSerialPorts() {
  if (Platform.isAndroid) return _AndroidUsbSerialProvider();
  return SerialPortProvider.platform();
}

/// USB CDC serial ports on Android through the `usb_serial` plugin.
class _AndroidUsbSerialProvider implements SerialPortProvider {
  @override
  bool get isSupported => true;

  @override
  bool get requiresUserSelection => false;

  @override
  Future<List<SerialPortInfo>> listPorts() async {
    final devices = await UsbSerial.listDevices();
    return [
      for (final d in devices)
        SerialPortInfo(
          id: '${d.deviceId}',
          description: d.productName ?? d.deviceName,
          vendorId: d.vid,
          productId: d.pid,
          product: d.productName,
          handle: d,
        ),
    ];
  }

  @override
  Future<SerialPortInfo?> requestPort({
    List<SerialPortFilter> filters = const [],
    bool Function(SerialPortInfo port)? where,
  }) async {
    final ports = await listPorts();
    for (final p in ports) {
      if (where == null || where(p)) return p;
    }
    return ports.isEmpty ? null : ports.first;
  }

  @override
  Future<SerialTransport> open(SerialPortInfo port, {int? baudRate}) async {
    final device = port.handle! as UsbDevice;
    final usb = await device.create();
    if (usb == null || !await usb.open()) {
      throw SerialException('Cannot open ${port.description}');
    }
    await usb.setDTR(true);
    await usb.setRTS(true);
    // USB CDC ignores the baud rate; the default matches the native library.
    await usb.setPortParameters(
      baudRate ?? 230400,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    return _UsbTransport(usb);
  }
}

class _UsbTransport implements SerialTransport {
  final UsbPort _port;
  bool _closed = false;

  _UsbTransport(this._port);

  @override
  Stream<Uint8List> get input => _port.inputStream!;

  @override
  Future<void> write(List<int> data) => _port.write(Uint8List.fromList(data));

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _port.close();
  }
}
