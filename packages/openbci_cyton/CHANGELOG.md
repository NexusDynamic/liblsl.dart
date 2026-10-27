## 0.2.0

- Sampling rate (`setSampleRate`) and board mode (`setBoardMode`), set on
  connecting or read from the board.
- Channels switched on and off, changed while streaming, and reset; the
  internal test signals.
- Markers (`marker`) in the marker board mode, restricted to values that
  the board cannot take for commands and spaced two samples apart;
  `CytonSample.marker` and `CytonSample.aux`. A marker survives the loss of
  the other packet of a Daisy pair.
- Electrode impedance (`measureImpedance`), corrected for the averaging of
  samples with a Daisy.
- SD card recordings: `startSdRecording`, `stopSdRecording`, and the files
  read by `CytonSdFile` and `CytonSdReader`, or converted to XDF in pieces by
  `convertCytonSdToXdf` (`package:openbci_cyton/xdf.dart`).
- `stop` waits for the packets still on their way, so that replies to the
  commands that follow are read correctly.
- `CytonChannelSettings` moved to `settings.dart` (exported as before), with
  `copyWith`, `commandFor` and equality; `CytonBoard.gains` is read-only.

## 0.1.0

- Initial version: `CytonBoard` (reset, Daisy detection, channel settings,
  streaming) and `CytonDecoder` (packets to µV, as BrainFlow decodes them).
