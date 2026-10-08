# signal_viewer

A Flutter viewer for multichannel signals such as EEG, from recordings, live
devices and network streams. It is the viewer behind
[LSL Viewer](https://nexusdynamic.org/liblsl.dart/lsl_viewer/), packaged so
that other applications can use it with their own data sources.

The viewer shows each stream in a tab, with filtering, re-referencing, power
spectra, signal quality and trigger decoding. Signal processing and the
summary pyramids used for fast overviews of long recordings come from
[`signal_core`](https://pub.dev/packages/signal_core), which this package
re-exports.

Data reaches the viewer through `SourceProvider`s. A provider opens
`SourceSession`s (a file, a device, a network stream) and can add its own
menu entries, toolbar items, welcome screen buttons and status bar items.
Providers for common sources are available as separate packages:
[`signal_viewer_lsl`](https://pub.dev/packages/signal_viewer_lsl) for Lab
Streaming Layer streams,
[`signal_viewer_xdf`](https://pub.dev/packages/signal_viewer_xdf) for XDF
recordings and
[`signal_viewer_serial`](https://pub.dev/packages/signal_viewer_serial) for
serial devices.

```dart
import 'package:signal_viewer/signal_viewer.dart';

Future<void> main(List<String> args) => runSignalViewer(
  args,
  config: const ViewerConfig(title: 'My viewer', heading: 'My viewer'),
  providers: [MyDeviceProvider()],
);
```

The viewer runs on Linux, macOS, Windows, Android, iOS and the web.

## Dropping files on Linux

Files can be dropped on the window on desktop platforms, through
[`desktop_drop`](https://pub.dev/packages/desktop_drop). With desktop_drop
0.8.4, drops from some Linux file managers (Dolphin, for example) arrive
empty. An application can use the patched copy kept in this repository until
that is fixed upstream:

```yaml
dependency_overrides:
  desktop_drop:
    git:
      url: https://github.com/NexusDynamic/liblsl.dart
      path: third_party/desktop_drop
```
