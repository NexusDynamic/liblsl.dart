/// A viewer for multichannel signals from any source: recordings, live
/// devices, network streams. Sources come from [SourceProvider]s; the
/// viewer shows their streams in tabs, with filtering, re-referencing,
/// power, signal quality and trigger decoding.
///
/// ```dart
/// Future<void> main(List<String> args) => runSignalViewer(
///   args,
///   config: const ViewerConfig(title: 'My viewer', heading: 'My viewer'),
///   providers: [MyDeviceProvider()],
/// );
/// ```
library;

export 'package:signal_core/signal_core.dart';

export 'src/app.dart';
export 'src/display/colors.dart';
export 'src/display/manchester.dart';
export 'src/display/power.dart';
export 'src/display/scale.dart';
export 'src/model/groups.dart';
export 'src/model/stream_info.dart';
export 'src/model/view_settings.dart';
export 'src/platform/files.dart';
export 'src/settings/prefs.dart';
export 'src/sources/columns.dart';
export 'src/sources/live_buffers.dart';
export 'src/sources/live_source.dart';
export 'src/sources/stream_source.dart';
export 'src/ui/app_state.dart';
export 'src/ui/dialogs/dialogs.dart';
export 'src/ui/main_window.dart';
export 'src/ui/panel/controls_panel.dart';
export 'src/ui/panel/quick_bar.dart';
export 'src/ui/plot/alt_views.dart';
export 'src/ui/plot/overview_strip.dart';
export 'src/ui/plot/stream_plot.dart';
export 'src/ui/plot/trace_painter.dart';
export 'src/ui/stream_controller.dart';
export 'src/ui/widgets/widgets.dart';
export 'src/viewer/source.dart';
