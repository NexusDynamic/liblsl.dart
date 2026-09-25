import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_lsl/signal_viewer_lsl.dart';
import 'package:signal_viewer_serial/signal_viewer_serial.dart';
import 'package:signal_viewer_xdf/signal_viewer_xdf.dart';

/// How the LSL Viewer presents itself.
const lslViewerConfig = ViewerConfig(
  title: 'LSL Viewer',
  heading: 'LSL Viewer',
  legalese:
      'View Lab Streaming Layer streams and XDF recordings.\n'
      'Built on liblsl.dart.',
);

/// What the LSL Viewer opens: LSL streams, XDF recordings and serial
/// devices that print numbers.
List<SourceProvider> lslViewerProviders() => [
  LslProvider(),
  XdfProvider(),
  SerialStreamProvider(),
];

/// Opens the XDF recordings given on the command line (desktop).
Future<void> main(List<String> args) => runSignalViewer(
  args,
  config: lslViewerConfig,
  providers: lslViewerProviders(),
);
