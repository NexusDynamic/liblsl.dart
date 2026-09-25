# LSL Viewer

View Lab Streaming Layer streams live and XDF recordings (e.g. from
LabRecorder), on desktop, mobile and the web (XDF only: browsers cannot
use LSL).

It is `signal_viewer` with two source providers:

- `LslProvider` (`signal_viewer_lsl`): find streams on the network and show
  each in a tab.
- `XdfProvider` (`signal_viewer_xdf`): open .xdf files of any size, a tab
  per stream.
- `SerialStreamProvider` (`signal_viewer_serial`): the OpenBCI Cyton (+
  Daisy), and serial devices that print lines of numbers (e.g. an
  Arduino): on desktop, on Android over USB, and in Chrome and Edge with
  WebSerial.

In a browser, LSL itself is not available (liblsl needs the system's
sockets and threads): serial devices and XDF files work, and live LSL
streams can be viewed through a bridge (LSL > Connect to an LSL bridge…,
shared from a desktop with "Share streams over the network…" or
`lsl share`).

Each tab has filters, re-referencing, power, signal quality and trigger
decoding; the source setup (View menu) overrides a stream's type and
channel names.

```sh
flutter run -d linux            # or macos, windows, chrome, a device
flutter run -d linux -a recording.xdf
```

hyprview is the same viewer with the Hyperscanner provider added.
