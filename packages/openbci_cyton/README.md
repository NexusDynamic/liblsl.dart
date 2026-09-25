# openbci_cyton

The OpenBCI Cyton (and Cyton + Daisy) over its USB dongle, in pure Dart,
on `serial_transport` (desktop serial ports, WebSerial).

- `CytonBoard.connect`: stops any earlier stream, soft-resets (`v`), finds
  a Daisy (16 channels at 125 Hz, or 8 at 250 Hz), restores the channel
  defaults (`d`).
- `configureChannel`: gain, input, bias, SRB2/SRB1 (`x…X`); gains are kept
  for scaling.
- `samples`: EEG in µV and the accelerometer in g, decoded as BrainFlow
  does, with lost samples counted from the packet counter.
- `package:openbci_cyton/testing.dart`: a simulated board for tests.

The viewer opens a Cyton from Serial > Connect an OpenBCI Cyton…, and
`lsl cyton <port>` (lsl_tools) publishes one as LSL streams.
