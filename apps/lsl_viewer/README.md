# LSL Viewer

View Lab Streaming Layer streams live and XDF recordings (e.g. from
LabRecorder), on desktop, mobile and the web (XDF only: browsers cannot
use LSL).

It is `signal_viewer` with two source providers:

- `LslProvider` (`signal_viewer_lsl`): find streams on the network and show
  each in a tab.
- `XdfProvider` (`signal_viewer_xdf`): open .xdf files of any size, a tab
  per stream.
- `SerialStreamProvider` (`signal_viewer_serial`): serial devices that
  print lines of numbers (e.g. an Arduino), on desktop and in browsers
  with WebSerial.

Each tab has filters, re-referencing, power, signal quality and trigger
decoding; the source setup (View menu) overrides a stream's type and
channel names.

```sh
flutter run -d linux            # or macos, windows, chrome, a device
flutter run -d linux -a recording.xdf
```

hyprview is the same viewer with the Hyperscanner provider added.
