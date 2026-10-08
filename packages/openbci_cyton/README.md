# openbci_cyton

[![Pub Version](https://img.shields.io/pub/v/openbci_cyton)](https://pub.dev/packages/openbci_cyton)

`openbci_cyton` connects to an OpenBCI Cyton biosensing board, with or
without the Daisy module, through its USB dongle. It configures the board
and delivers the streamed samples, with EEG in microvolts and the
accelerometer in g, decoded in the same way as BrainFlow. The package is
pure Dart and uses [`serial_transport`](https://pub.dev/packages/serial_transport)
for the serial connection, so it runs on desktop platforms and, with
WebSerial, in Chrome and Edge.

[API documentation](https://pub.dev/documentation/openbci_cyton/latest/)

## Installation

```bash
dart pub add openbci_cyton serial_transport
```

## Usage

```dart
import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:serial_transport/serial_transport.dart';

Future<void> main() async {
  final provider = SerialPortProvider.platform();
  final ports = await provider.listPorts();
  if (ports.isEmpty) return;
  final transport = await provider.open(ports.first, baudRate: cytonBaudRate);

  final board = await CytonBoard.connect(transport);
  print('${board.channelCount} channels at ${board.rate} Hz');

  board.samples.listen((sample) => print(sample.eeg));
  await board.start();
  await Future<void>.delayed(const Duration(seconds: 5));
  await board.stop();
  await board.close();
}
```

`CytonBoard.connect` stops any stream left running from an earlier session,
resets the board, detects a Daisy module and restores the default channel
settings. With a Daisy the board provides 16 channels at 125 Hz, and
otherwise 8 channels at 250 Hz. If the board does not reply, the board must
be switched on and the switch of the dongle set to `GPIO_6`.

`configureChannel` sets the gain, input type, bias and reference (SRB1,
SRB2) of a channel. The gains are retained and used to scale the samples.

Each `CytonSample` has the sample number, the EEG values, the accelerometer
values, and the number of samples lost before it, derived from the packet
counter of the board. `CytonBoard.dropped` counts packets that could not be
decoded.

## Testing without a board

`package:openbci_cyton/testing.dart` provides `FakeCyton`, a simulated board
that is attached to the far end of a serial connection, such as one side of
a pseudo-terminal pair.

## Related tools

[LSL Viewer](https://github.com/NexusDynamic/liblsl.dart/tree/main/apps/lsl_viewer)
connects to a Cyton under *Serial > Connect an OpenBCI Cyton…*, and the
command `lsl cyton <port>` of
[`lsl_tools`](https://pub.dev/packages/lsl_tools) publishes a board as LSL
streams.
