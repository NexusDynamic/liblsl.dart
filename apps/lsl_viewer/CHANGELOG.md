## 0.3.0

- Values are kept and shown as recorded instead of as 32-bit floats.
  The initial versions used that for memory efficiency, so it stays as
  an option, but is disabled by default. This could be useful for the
  web version mainly.
- Replaying a recording sends each stream in exactly as recorded.
- 64-bit integer streams in the web app show a warning because the
  browser rounds values beyond ±2^53.

## Unreleased

- OpenBCI Cyton: the *Cyton* menu for board settings, test signals,
  electrode impedance, markers and SD card recording, and tabs for channels
  used for EMG; SD card recordings (`OBCI_XX.TXT`) open as recordings
  (`signal_viewer_serial` ^0.2.0).
- The macOS app sandbox now permits serial and USB devices, so the Cyton and
  other serial devices can be opened, and files chosen in the open and save
  dialogs.
- The macOS icon is opaque, so that macOS fills the icon shape with it.

## 0.2.2

- Cascaded performance improvements for the UI from `signal_viewer` ^0.1.2.

## 0.2.1

- Requires `signal_viewer_lsl` ^0.2.1.

## 0.2.0

- Event-driven LSL sample delivery
- Per-hop timing for bridged streams
- Bridge option to skip jitter smoothing and time correction
- Updated to liblsl 1.1.0

## 0.1.1

- Placeholder app icon

## 0.1.0

- Initial version
- Live LSL stream viewer
- XDF recording viewer
- Serial device support on desktop, web and Android
- Publish streams from a browser through the LSL bridge
