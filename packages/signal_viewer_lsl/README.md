# signal_viewer_lsl

[![Pub Version](https://img.shields.io/pub/v/signal_viewer_lsl)](https://pub.dev/packages/signal_viewer_lsl)

[Lab Streaming Layer](https://labstreaminglayer.org/) (LSL) streams for
[`signal_viewer`](https://pub.dev/packages/signal_viewer).

`LslProvider` finds the streams on the network and shows each one in a tab.
It also records streams to XDF, replays recordings as streams, forwards
streams, and shares them with other networks or a browser through the LSL
bridge. The LSL facade, recorder and bridge come from
[`lsl_tools`](https://pub.dev/packages/lsl_tools), which this package
re-exports.

[API documentation](https://pub.dev/documentation/signal_viewer_lsl/latest/)

## Installation

```bash
flutter pub add signal_viewer signal_viewer_lsl
```

## Usage

```dart
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_lsl/signal_viewer_lsl.dart';

Future<void> main(List<String> args) => runSignalViewer(
  args,
  config: const ViewerConfig(title: 'My viewer', heading: 'My viewer'),
  providers: [LslProvider()],
);
```

LSL is available on desktop and mobile platforms. The package can be
imported on the web, where `LslBackend.supported` is false and liblsl is not
loaded.
