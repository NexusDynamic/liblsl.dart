# openbci_cyton

[![Pub Version](https://img.shields.io/pub/v/openbci_cyton)](https://pub.dev/packages/openbci_cyton)

`openbci_cyton` connects to an OpenBCI Cyton biosensing board, with or
without the Daisy module, through its USB dongle. It configures the board
and delivers the streamed samples, with EEG in microvolts and the
accelerometer in g, decoded in the same way as BrainFlow. It also sets the
sampling rate, sends markers, measures electrode impedance, records to the
SD card of the board and reads those recordings. The package is
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
be switched on and the switch of the dongle set to `GPIO_6`. A reset keeps
the sampling rate and the board mode, so `connect` sets them when they are
given (`sampleRate`, `boardMode`) and reads them from the board otherwise.

Each `CytonSample` has the sample number, the EEG values, the accelerometer
values, the six aux bytes, a marker if one was sent, and the number of
samples lost before it, derived from the packet counter of the board.
`CytonBoard.dropped` counts packets that could not be decoded.

## Channels

`configureChannel` sets the power, gain, input, bias and reference (SRB1,
SRB2) of a channel. `CytonChannelSettings.bipolar` removes the SRB2
reference, as for EMG on some of the channels of an EEG cap.
`setChannelEnabled` switches a channel on or off, and `resetChannels`
restores the defaults. The settings are retained (`channels`, `gains`), and
the gains scale the samples. The board accepts these commands while it
streams, without a reply, so a change of gain applies to the samples that
follow.

`setTestSignal` connects every channel to one of the internal test signals
of the ADS1299, such as a square wave of about 1.86 mV, and with `null`
restores the previous settings.

## Sampling rate and board mode

`setSampleRate` sets the rate of the ADS1299 from 250 Hz to 16 kHz. The
radio link of the dongle carries 250 Hz at most, so at higher rates the
board does not stream and only an SD card recording receives the samples.
`setBoardMode` chooses what the aux bytes carry: the accelerometer (the
default), the analog or digital pins, or markers.

## Markers

In `CytonBoardMode.marker`, `marker` places a value in the next sample, as
`CytonSample.marker` and in an SD card recording; the accelerometer is off.
The board receives a marker as a backtick followed by the value. If the
radio loses the backtick, the board takes the value for a command, and
values such as `A` (start an SD card recording), `b` (start streaming) or
`1` (switch channel 1 off) then change its state. `marker` therefore accepts
only values that are not commands: 128 to 239, and the characters
`9fghklmnoBMNOP()+,._|` (`cytonSafeMarkerChars`). The board holds one
marker per sample, so markers are sent at least two samples apart. Markers
sent in the first moments after streaming starts can be lost.

## Electrode impedance

`measureImpedance` and `measureImpedances` measure electrodes one at a
time while the board streams, as the OpenBCI GUI does. The channel is set to
gain 1 without a reference, a lead-off current of 6 nA at 31.25 Hz is
applied to its N input (the usual electrode input with SRB2 referencing) or
its P input, and the impedance follows from the amplitude of the signal at
31.25 Hz, less the series resistance of 2.2 kΩ. The channel's settings are
restored afterwards. With a Daisy, the board streams the mean of two
consecutive samples, which reduces the amplitude at 31.25 Hz to 0.92 of its
value; the measurement corrects for this, whereas the OpenBCI GUI reports
impedances about 8% lower.

## SD card recordings

`startSdRecording` reserves space on the card for a duration
(`CytonSdDuration`, from 5 minutes to 24 hours at 250 Hz;
`CytonSdDuration.forMinutes` chooses one for a rate) and starts streaming,
during which the board writes its samples to the file it names, such as
`OBCI_2A.TXT`. `stopSdRecording` closes the file. At 250 Hz the samples
are streamed as well. The files hold 250 samples per second with a Daisy,
as the board does not average them for the card.

`CytonSdFile.parse` reads such a file, and `CytonSdReader` reads one in
pieces. The file does not record the sampling rate or the gains: the rate is
estimated from the accelerometer, which the board reads at 25 Hz, and the
gains are taken to be 24, unless they are given. In the marker board mode,
the aux values of each line carry the markers. The library
`package:openbci_cyton/xdf.dart` converts a recording to XDF as it is read
(`convertCytonSdToXdf`), so that large files need not be held in memory.

The replies of the board were verified with firmware v3.1.2. Streaming
during an SD card recording, and SD card recordings above 250 Hz, were
verified with a [fork of the firmware](https://github.com/zeyus-archive/OpenBCI_Cyton_Library)
that corrects SD card logging.

## Testing without a board

`package:openbci_cyton/testing.dart` provides `FakeCyton`, a simulated board
that is attached to the far end of a serial connection, such as one side of
a pseudo-terminal pair.

## Related tools

[LSL Viewer](https://github.com/NexusDynamic/liblsl.dart/tree/main/apps/lsl_viewer)
connects to a Cyton under *Serial > Connect an OpenBCI Cyton…*, with its
settings, markers, impedance and SD card recording in the *Cyton* menu, and
opens SD card recordings. The command `lsl cyton <port>` of
[`lsl_tools`](https://pub.dev/packages/lsl_tools) publishes a board as LSL
streams, and `lsl cyton-sd` converts an SD card recording to XDF.
