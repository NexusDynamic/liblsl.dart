import 'package:serial_transport/serial_transport.dart';

import 'platform_serial_stub.dart'
    if (dart.library.io) 'platform_serial_io.dart'
    as platform;

/// The serial ports of this platform: serial_transport's on desktop and
/// the web (WebSerial), USB serial devices on Android (through the
/// `usb_serial` plugin: CDC, FTDI such as the OpenBCI dongle, CP210x,
/// CH34x), none on iOS.
SerialPortProvider platformSerialPorts() => platform.platformSerialPorts();
