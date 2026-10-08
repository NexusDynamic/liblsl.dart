# serial_transport

[![Pub Version](https://img.shields.io/pub/v/serial_transport)](https://pub.dev/packages/serial_transport)

`serial_transport` gives Dart programs access to serial ports through one
interface on every platform. On Linux, macOS and Windows it uses native
ports, through a small C library that the package's build hook compiles. In
web browsers it uses WebSerial. On other platforms, such as Android, an
application supplies its own implementation of the `SerialTransport`
interface, for example on top of a USB serial plugin.

In this repository it connects serial devices to
[`openbci_cyton`](https://pub.dev/packages/openbci_cyton) and to the serial
source of [`signal_viewer_serial`](https://pub.dev/packages/signal_viewer_serial).

[API documentation](https://pub.dev/documentation/serial_transport/latest/)

## Installation

```bash
dart pub add serial_transport
```

The native implementation requires a C toolchain when the application is
built. WebSerial is available in Chrome, Edge and Firefox.

## Usage

`SerialPortProvider.platform()` returns the implementation for the current
platform. A port is listed, opened, read from and written to as follows:

```dart
import 'dart:convert';

import 'package:serial_transport/serial_transport.dart';

Future<void> main() async {
  final provider = SerialPortProvider.platform();
  if (!provider.isSupported) return;

  final ports = await provider.listPorts();
  if (ports.isEmpty) return;

  final port = await provider.open(ports.first, baudRate: 115200);
  port.input.listen((bytes) => print('${bytes.length} bytes received'));
  await port.write(ascii.encode('v'));

  await Future<void>.delayed(const Duration(seconds: 1));
  await port.close();
}
```

In a browser, a port appears in `listPorts` only after the user has granted
access to it. `requestPort` opens the browser's port chooser and must be
called from a user gesture such as a click; `requiresUserSelection`
indicates whether this step is needed. On other platforms `requestPort`
returns the first port that matches its filters.

The baud rate is required by UART adapters and ignored by USB CDC devices.
`input` is a single-subscription stream that closes when the port is closed
or the device disconnects.

## Other platforms

A class that implements `SerialTransport` (`input`, `write` and `close`) can
be passed wherever a port is expected. This is how a platform without
built-in support, such as Android, is connected.
