# signal_viewer_serial

[![Pub Version](https://img.shields.io/pub/v/signal_viewer_serial)](https://pub.dev/packages/signal_viewer_serial)

Serial devices for [`signal_viewer`](https://pub.dev/packages/signal_viewer).

`SerialStreamProvider` reads lines of numbers from a serial port and shows
them as a live stream, one tab per device. This is the output of a typical
Arduino sketch that prints sensor values. Values may be separated by commas,
semicolons, tabs or spaces, and a header line or `name:value` pairs give the
channel names. The provider also connects to an OpenBCI Cyton through
[`openbci_cyton`](https://pub.dev/packages/openbci_cyton).

[API documentation](https://pub.dev/documentation/signal_viewer_serial/latest/)

## Installation

```bash
flutter pub add signal_viewer signal_viewer_serial
```

## Usage

```dart
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_serial/signal_viewer_serial.dart';

Future<void> main(List<String> args) => runSignalViewer(
  args,
  config: const ViewerConfig(title: 'My viewer', heading: 'My viewer'),
  providers: [SerialStreamProvider()],
);
```

Ports come from [`serial_transport`](https://pub.dev/packages/serial_transport)
on Linux, macOS, Windows and the web (WebSerial). On other platforms an
application passes its own `SerialPortProvider` to the `SerialStreamProvider`
constructor. LSL Viewer does this for USB serial devices on Android, in
[`serial_ports_io.dart`](https://github.com/NexusDynamic/liblsl.dart/blob/main/apps/lsl_viewer/lib/serial_ports_io.dart).
