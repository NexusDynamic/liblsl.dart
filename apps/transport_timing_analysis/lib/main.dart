import 'package:nexus_branding/nexus_branding.dart';
import 'package:signal_viewer/signal_viewer.dart';

import 'src/timing_provider.dart';

/// Opens the run logs given on the command line (desktop).
Future<void> main(List<String> args) => runSignalViewer(
  args,
  config: ViewerConfig(
    title: 'Transport Timing Analysis',
    heading: 'Transport Timing Analysis',
    legalese:
        'Latency, jitter, loss and clock drift from transport_timing '
        'run logs.',
    theme: nexusLightTheme(),
    darkTheme: nexusDarkTheme(),
  ),
  providers: [TimingProvider()],
);
