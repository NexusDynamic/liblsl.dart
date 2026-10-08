# signal_viewer_xdf

[![Pub Version](https://img.shields.io/pub/v/signal_viewer_xdf)](https://pub.dev/packages/signal_viewer_xdf)

[XDF](https://github.com/sccn/xdf/wiki/Specifications) recordings for
[`signal_viewer`](https://pub.dev/packages/signal_viewer).

`XdfProvider` opens `.xdf` files, such as those written by LabRecorder, and
shows each stream in a tab. Files are indexed in one pass and read on
demand, so recordings larger than memory can be viewed. Reading and clock
synchronisation come from the [`xdf`](https://pub.dev/packages/xdf) package.

[API documentation](https://pub.dev/documentation/signal_viewer_xdf/latest/)

## Installation

```bash
flutter pub add signal_viewer signal_viewer_xdf
```

## Usage

```dart
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_xdf/signal_viewer_xdf.dart';

Future<void> main(List<String> args) => runSignalViewer(
  args,
  config: const ViewerConfig(title: 'My viewer', heading: 'My viewer'),
  providers: [XdfProvider()],
);
```

The provider works on all platforms, including the web, where the file is
read in the browser.
