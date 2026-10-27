## 0.2.0

- The *Cyton* menu for a connected OpenBCI Cyton: board settings (channel
  use, power, gain, input, bias, SRB2, SRB1, test signals), pausing,
  electrode impedance, markers, and SD card recording at up to 16 kHz.
- Channels used for EMG or other signals appear in tabs of their own.
- The marker board mode, with a tab of the board's markers.
- `CytonSdProvider` opens the Cyton's SD card recordings (`OBCI_XX.TXT`),
  read and converted to XDF in pieces.
- Requires `signal_viewer` ^0.2.0.

## 0.1.1

- Requires `signal_viewer` ^0.2.0.

## 0.1.0

- Initial version: `SerialStreamProvider` and `SerialStreamSession` read
  lines of numbers (or name:value pairs) from serial ports as live streams.
